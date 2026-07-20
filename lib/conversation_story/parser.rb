# frozen_string_literal: true

require "json"

module ConversationStory
  # Reads a Claude conversation log (a .jsonl file, one JSON record per line) and
  # produces the intermediate "document": a Ruby hash matching the schema in
  # notes/intermediate-schema.md, ready to serialize as YAML.
  #
  # Mountain 1 granularity: ONE event per record (per line). The golden test
  # asserts event_count == line count. Block-level splitting (a thinking block
  # and a tool_use block inside one assistant record becoming their own cards)
  # is a later mountain; here the whole record is a single card.
  #
  # The schema is the contract: known event kinds store only named fields.
  # Unrecognized record types fall back to kind `unknown` with `detail.raw` kept
  # verbatim, so nothing in the log is silently lost.
  class Parser
    # top-level record `type` -> schema kind. `user` is refined by its content
    # (a plain string is a message; an array carries a tool_result). Any type
    # not listed here falls through to `unknown` (the fallback), keeping its raw
    # record so we never lose data while still discovering the format.
    TYPE_TO_KIND = {
      "assistant"             => "assistant_message",
      "system"                => "system",
      "attachment"            => "attachment",
      "file-history-snapshot" => "file_snapshot",
      "permission-mode"       => "permission_mode",
      "queue-operation"       => "queue_operation",
    }.freeze

    # Harness bookkeeping — records that are not part of the conversation "from
    # Jess's perspective". They are still parsed into events (so nothing is lost
    # and event_count == line count), but flagged `hidden: true` so the renderer
    # skips them. See notes/2026-07-20-session-6-hidden-events.md for the full
    # rationale (which types, and why the ones we KEEP are worth keeping).
    #
    # Whole kinds that are always hidden:
    HIDDEN_KINDS = %w[system file_snapshot permission_mode].freeze
    # Attachment subtypes that are pure context-loading / hook plumbing. The two
    # conversation-relevant attachments stay visible: `queued_command` (delivered
    # queued input AND background <task-notification>s — "the agent being nudged")
    # and `task_reminder` (the system nudging the agent about pending tasks).
    HIDDEN_ATTACHMENT_TYPES = %w[
      hook_success deferred_tools_delta mcp_instructions_delta skill_listing
    ].freeze
    # The unsent-prompt buffer (a `last-prompt` record → `unknown` fallback).
    HIDDEN_RECORD_TYPES = %w[last-prompt].freeze
    # queue-operation stays fully visible — including the bare `dequeue`/`remove`
    # markers — so the enqueue→deliver lifecycle (and whether a background result
    # landed mid-turn or as its own turn) is legible.

    ELLIPSIS = "…"
    SUMMARY_LIMIT = 140

    # @param log_path [String] path to the top-level conversation .jsonl.
    def initialize(log_path)
      @log_path = log_path
      @log_file = File.basename(log_path)            # source.file (with .jsonl)
      @log_name = File.basename(log_path, ".jsonl")  # the `ref` prefix (no ext)
    end

    # @return [Hash] the intermediate document (YAML-serializable with string
    #   keys and plain scalars only, so YAML.safe_load round-trips it).
    def to_document
      records = read_records
      events  = records.map { |lineno, rec| build_event(lineno, rec) }
      { "meta" => build_meta(records, events), "events" => events }
    end

    private

    # @return [Array<[Integer, Hash]>] 1-based line number paired with the parsed
    #   record. Blank lines are skipped but still advance the line counter, so
    #   source.line stays exact against the committed log.
    def read_records
      out = []
      File.foreach(@log_path).with_index(1) do |raw, lineno|
        next if raw.strip.empty?
        out << [lineno, JSON.parse(raw)]
      end
      out
    end

    # ---- one event per record ------------------------------------------------

    def build_event(lineno, rec)
      kind = kind_for(rec)
      event = {
        "id"      => rec["uuid"] || "line-#{lineno}",
        # a short, human-referable handle built from provenance: "<name>:<line>"
        # (e.g. episode-8-before:9). Stable to cite when discussing an event.
        "ref"     => "#{@log_name}:#{lineno}",
        "agent"   => agent_for(rec),
        "parent"  => rec["parentUuid"],
        "kind"    => kind,
        "role"    => rec.dig("message", "role"),
        "at"      => rec["timestamp"],
        "summary" => summary_for(kind, rec),
        "source"  => { "file" => @log_file, "line" => lineno },
      }
      add_detail(event, kind, rec)
      add_assistant_fields(event, rec) if kind == "assistant_message"
      event["hidden"] = true if hidden?(kind, rec)
      event
    end

    # Is this record harness bookkeeping the renderer should skip? See the
    # HIDDEN_* constants above.
    def hidden?(kind, rec)
      return true if HIDDEN_KINDS.include?(kind)
      return true if HIDDEN_RECORD_TYPES.include?(rec["type"])
      return true if kind == "attachment" &&
                     HIDDEN_ATTACHMENT_TYPES.include?(rec.dig("attachment", "type"))

      false
    end

    def kind_for(rec)
      type = rec["type"]
      return "unknown" unless TYPE_TO_KIND.key?(type) || type == "user"

      if type == "user"
        # a tool_result arrives as a user-role record whose content is an array
        rec.dig("message", "content").is_a?(Array) ? "tool_result" : "user_message"
      else
        TYPE_TO_KIND.fetch(type)
      end
    end

    # (c) prefer an explicit agentId (subagent records carry one); else `main`.
    def agent_for(rec)
      id = rec["agentId"] || rec.dig("message", "agentId")
      id ? "agent-#{id}".sub(/\Aagent-agent-/, "agent-") : "main"
    end

    # ---- summaries (one line, whitespace collapsed) --------------------------

    def summary_for(kind, rec)
      case kind
      when "user_message"      then truncate(rec.dig("message", "content").to_s)
      when "assistant_message" then assistant_summary(rec)
      when "tool_result"       then tool_result_summary(rec)
      when "system"            then system_summary(rec)
      when "attachment"        then attachment_summary(rec)
      when "file_snapshot"     then "File history snapshot"
      when "permission_mode"   then "Permission mode: #{rec["permissionMode"]}"
      when "queue_operation"   then queue_summary(rec)
      else                          "#{rec["type"]} record"
      end
    end

    def assistant_summary(rec)
      blocks = Array(rec.dig("message", "content"))
      text = blocks.select { |b| b["type"] == "text" }
                   .map { |b| b["text"] }.join(" ").strip
      return truncate(text) unless text.empty?

      tools = blocks.select { |b| b["type"] == "tool_use" }.map { |b| b["name"] }
      return truncate("Tool call: #{tools.join(", ")}") unless tools.empty?

      "Thinking#{ELLIPSIS}"
    end

    def tool_result_summary(rec)
      text = extract_text(rec.dig("message", "content"))
      text.empty? ? "Tool result" : truncate(text)
    end

    def system_summary(rec)
      sub = rec["subtype"] || "system"
      count = rec["hookCount"]
      count ? "#{sub} — #{count} hook#{"s" unless count == 1}" : sub
    end

    def attachment_summary(rec)
      att = rec["attachment"] || {}
      label = [att["type"], att["hookName"] || att["hookEvent"]].compact.join(": ")
      label.empty? ? "Attachment" : label
    end

    def queue_summary(rec)
      op = rec["operation"] || "queue"
      # the content is a <task-notification> blob; a short verb is enough here
      "Queue #{op}"
    end

    # ---- detail payload (drill-in) -------------------------------------------
    #
    # Known kinds get a named `detail.text` (the renderer reads the schema, never
    # the log). Only `unknown` keeps `detail.raw` verbatim.

    def add_detail(event, kind, rec)
      case kind
      when "user_message"
        event["detail"] = { "text" => rec.dig("message", "content").to_s }
      when "assistant_message"
        text = Array(rec.dig("message", "content"))
               .select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n\n")
        event["detail"] = { "text" => text } unless text.strip.empty?
      when "tool_result"
        text = extract_text(rec.dig("message", "content"))
        event["detail"] = { "text" => text } unless text.empty?
      when "queue_operation"
        # `enqueue` carries the queued payload (a queued user message, or a
        # background <task-notification> like "…failed with exit code 1").
        # `dequeue`/`remove` are bare markers with no content.
        content = rec["content"].to_s
        event["detail"] = { "text" => content } unless content.strip.empty?
      when "attachment"
        text = attachment_detail_text(rec)
        event["detail"] = { "text" => text } unless text.strip.empty?
      when "unknown"
        event["detail"] = { "raw" => rec }
      end
    end

    # The human-relevant body of a (visible) attachment: `queued_command` carries
    # a `prompt` (the delivered notification/input); other attachments may carry a
    # `content` array of text blocks.
    def attachment_detail_text(rec)
      att = rec["attachment"] || {}
      return att["prompt"].to_s if att["prompt"]

      extract_text(att["content"])
    end

    # (b) named token + turn fields on assistant turns.
    def add_assistant_fields(event, rec)
      msg = rec["message"] || {}
      event["model"]         = msg["model"] if msg["model"]
      event["stop_reason"]   = msg["stop_reason"]
      event["stop_details"]  = msg["stop_details"]
      event["stop_sequence"] = msg["stop_sequence"]

      usage = msg["usage"]
      return unless usage.is_a?(Hash)

      event["tokens"] = {
        "input"          => usage["input_tokens"],
        "output"         => usage["output_tokens"],
        "cache_creation" => usage["cache_creation_input_tokens"],
        "cache_read"     => usage["cache_read_input_tokens"],
        "ephemeral_1h"   => usage.dig("cache_creation", "ephemeral_1h_input_tokens"),
        "ephemeral_5m"   => usage.dig("cache_creation", "ephemeral_5m_input_tokens"),
        "service_tier"   => usage["service_tier"],
      }
    end

    # ---- meta ----------------------------------------------------------------

    def build_meta(records, events)
      recs = records.map { |_lineno, rec| rec }
      {
        "source"      => @log_file,
        "name"        => File.basename(@log_path, ".jsonl"),
        "session_id"  => first_present(recs, "sessionId"),
        "git_branch"  => first_present(recs, "gitBranch"),
        "cwd"         => first_present(recs, "cwd"),
        "version"     => first_present(recs, "version"),
        "model"       => events.map { |e| e["model"] }.compact.first,
        "started_at"  => events.map { |e| e["at"] }.compact.first,
        "ended_at"    => events.map { |e| e["at"] }.compact.last,
        "timezone"    => "UTC",
        "event_count" => events.size,
        "agents"      => build_agents,
      }
    end

    def first_present(recs, key)
      recs.each { |r| return r[key] if r[key] }
      nil
    end

    # meta.agents: `main` plus every subagent described by a sibling
    # subagents/*.meta.json. Mountain 1 lists them but does not yet inline their
    # events (that's the `subagent` kind / nested story, a later mountain).
    def build_agents
      agents = [{ "id" => "main" }]
      dir = File.join(File.dirname(@log_path),
                      File.basename(@log_path, ".jsonl"), "subagents")
      Dir.glob(File.join(dir, "*.meta.json")).sort.each do |meta_path|
        meta = JSON.parse(File.read(meta_path))
        id = File.basename(meta_path, ".meta.json") # e.g. agent-ae20659fd0f63295e
        agents << {
          "id"          => id,
          "agent_type"  => meta["agentType"],
          "description" => meta["description"],
        }
      rescue JSON::ParserError
        next
      end
      agents
    end

    # ---- text helpers --------------------------------------------------------

    # Collapse all whitespace to single spaces and cut to one readable line.
    def truncate(str, limit = SUMMARY_LIMIT)
      s = str.to_s.gsub(/\s+/, " ").strip
      s.length > limit ? "#{s[0, limit - 1].rstrip}#{ELLIPSIS}" : s
    end

    # tool_result content is either a String or an array of {type:text, text:…}
    # (and occasionally other block types we ignore for the summary).
    def extract_text(content)
      case content
      when String then content
      when Array
        content.flat_map do |block|
          next block unless block.is_a?(Hash)

          inner = block["content"] || block["text"]
          inner.is_a?(Array) ? extract_text(inner) : inner
        end.compact.join("\n").strip
      else ""
      end
    end
  end
end
