# frozen_string_literal: true

require "json"

module ConversationStory
  # Reads a Claude conversation log (a .jsonl file, one JSON record per line) and
  # produces the intermediate "document": a Ruby hash matching the schema in
  # notes/intermediate-schema.md, ready to serialize as YAML.
  #
  # Mountain 1 granularity: ONE event per record (per line). The golden test
  # asserts event_count == line count. Splitting an assistant record's blocks
  # into separate cards is still out of scope — but every assistant record in
  # the example logs carries exactly one content block, so classifying the
  # record's `kind` by that block's type (thinking / tool_use / text) is not
  # block-splitting, just a finer-grained `kind` for the one block present.
  #
  # The schema is the contract: known event kinds store only named fields.
  # Unrecognized record types fall back to kind `unknown` with `detail.raw` kept
  # verbatim, so nothing in the log is silently lost.
  class Parser
    # top-level record `type` -> schema kind, for types with a fixed kind.
    # `user` and `assistant` are refined by content shape (see user_kind /
    # assistant_kind). Any type not listed here falls through to `unknown`.
    TYPE_TO_KIND = {
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
    # and `task_reminder` (the system nudging the agent about pending tasks) —
    # except a `task_reminder` with itemCount 0 has nothing to show, so those
    # are hidden individually below rather than by type.
    HIDDEN_ATTACHMENT_TYPES = %w[
      hook_success deferred_tools_delta mcp_instructions_delta skill_listing
    ].freeze
    # The unsent-prompt buffer (a `last-prompt` record → `unknown` fallback).
    HIDDEN_RECORD_TYPES = %w[last-prompt].freeze
    # queue-operation and task_notification stay fully visible — including the
    # bare `dequeue`/`remove` markers — so the enqueue→deliver lifecycle (and
    # whether a background result landed mid-turn or as its own turn) is legible.

    # A background task result arrives mid-conversation as a plain `user`
    # record whose string content is this XML blob — NOT something Jess typed.
    TASK_NOTIFICATION_TAG = "<task-notification>"

    # tool_use `name` -> which input key is worth surfacing as the one-line
    # "primary arg" (in card summaries and the Fields section). Anything not
    # listed here shows no primary arg (just the tool name).
    PRIMARY_ARG_KEY = {
      "Read" => "file_path", "Write" => "file_path", "Edit" => "file_path",
      "Bash" => "command", "Grep" => "pattern", "Glob" => "pattern",
    }.freeze

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
      link_related_events!(events)
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
      event["operation"] = rec["operation"] if kind == "queue_operation"
      add_detail(event, kind, rec)
      add_assistant_fields(event, rec) if rec["type"] == "assistant"
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
      return true if kind == "attachment" &&
                     rec.dig("attachment", "type") == "task_reminder" &&
                     rec.dig("attachment", "itemCount").to_i.zero?

      false
    end

    def kind_for(rec)
      case rec["type"]
      when "user"      then user_kind(rec)
      when "assistant" then assistant_kind(rec)
      else TYPE_TO_KIND.fetch(rec["type"], "unknown")
      end
    end

    # a tool_result arrives as a user-role record whose content is an array; a
    # delivered background-task result arrives as a user-role record whose
    # string content is a <task-notification> blob — not something Jess typed.
    def user_kind(rec)
      content = rec.dig("message", "content")
      return "tool_result" if content.is_a?(Array)
      return "task_notification" if content.is_a?(String) &&
                                     content.strip.start_with?(TASK_NOTIFICATION_TAG)

      "user_message"
    end

    # every assistant record observed carries exactly one content block; its
    # type picks the finer-grained kind (tool_use -> tool_call, thinking ->
    # thinking, text -> assistant_message). Order matters if that ever changes:
    # a tool_use or thinking block is more informative than an empty text block.
    def assistant_kind(rec)
      blocks = Array(rec.dig("message", "content"))
      return "tool_call" if blocks.any? { |b| b["type"] == "tool_use" }
      return "thinking" if blocks.any? { |b| b["type"] == "thinking" }

      "assistant_message"
    end

    # (c) prefer an explicit agentId (subagent records carry one); else `main`.
    def agent_for(rec)
      id = rec["agentId"] || rec.dig("message", "agentId")
      id ? "agent-#{id}".sub(/\Aagent-agent-/, "agent-") : "main"
    end

    # ---- summaries (one line, whitespace collapsed) --------------------------

    def summary_for(kind, rec)
      case kind
      when "user_message"      then truncate(strip_markdown(rec.dig("message", "content").to_s))
      when "assistant_message" then assistant_summary(rec)
      when "thinking"          then thinking_summary(rec)
      when "tool_call"         then tool_call_summary(rec)
      when "tool_result"       then tool_result_summary(rec)
      when "task_notification" then task_notification_summary(rec)
      when "system"            then system_summary(rec)
      when "attachment"        then attachment_summary(rec)
      when "file_snapshot"     then "File history snapshot"
      when "permission_mode"   then "Permission mode: #{rec["permissionMode"]}"
      when "queue_operation"   then queue_summary(rec)
      else                          "#{rec["type"]} record"
      end
    end

    def assistant_summary(rec)
      text = Array(rec.dig("message", "content"))
             .select { |b| b["type"] == "text" }.map { |b| b["text"] }.join(" ").strip
      truncate(strip_markdown(text))
    end

    def thinking_summary(rec)
      text = thinking_text(rec).strip
      text.empty? ? "(reasoning — not captured)" : truncate(strip_markdown(text))
    end

    def tool_call_summary(rec)
      tu = tool_use_block(rec)
      return "Tool call" unless tu

      arg = primary_arg(tu["name"], tu["input"] || {})
      truncate(arg ? "#{tu["name"]} #{arg}" : tu["name"].to_s)
    end

    def tool_result_summary(rec)
      text = extract_text(rec.dig("message", "content"))
      text.empty? ? "Tool result" : truncate(text)
    end

    # the <summary> field inside the <task-notification> blob is the whole
    # point of the notification; showing the raw XML as the summary (the old
    # generic behavior) buried it.
    def task_notification_summary(rec)
      content = rec.dig("message", "content").to_s
      inner = content[%r{<summary>(.*?)</summary>}m, 1]
      truncate(inner || content)
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
    # Known kinds get named `detail`/`tool` fields (the renderer reads the
    # schema, never the log). Only `unknown` keeps `detail.raw` verbatim.

    def add_detail(event, kind, rec)
      case kind
      when "user_message"
        event["detail"] = { "text" => rec.dig("message", "content").to_s }
      when "assistant_message"
        text = Array(rec.dig("message", "content"))
               .select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n\n")
        event["detail"] = { "text" => text } unless text.strip.empty?
      when "thinking"
        text = thinking_text(rec)
        event["detail"] = { "text" => text } unless text.strip.empty?
      when "tool_call"
        add_tool_call_fields(event, rec)
      when "tool_result"
        text = extract_text(rec.dig("message", "content"))
        event["detail"] = { "text" => text } unless text.empty?
        add_tool_result_fields(event, rec)
      when "task_notification"
        content = rec.dig("message", "content").to_s
        event["detail"] = { "text" => content } unless content.strip.empty?
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

    def thinking_text(rec)
      Array(rec.dig("message", "content"))
        .select { |b| b["type"] == "thinking" }.map { |b| b["thinking"] }.join("\n\n")
    end

    def tool_use_block(rec)
      Array(rec.dig("message", "content")).find { |b| b["type"] == "tool_use" }
    end

    def add_tool_call_fields(event, rec)
      tu = tool_use_block(rec)
      return unless tu

      input = tu["input"] || {}
      event["tool"] = { "name" => tu["name"], "use_id" => tu["id"], "input" => input }
      arg = primary_arg(tu["name"], input)
      event["tool"]["primary_arg"] = arg if arg
    end

    def primary_arg(name, input)
      key = PRIMARY_ARG_KEY[name]
      return truncate(input[key].to_s, 90) if key && input[key]
      return input["subagent_type"] || input["description"] if name == "Agent"

      nil
    end

    # (b) named tool-result fields from the record's own content block and its
    # sibling `toolUseResult` (durationMs, stdout/stderr, structured_patch…).
    def add_tool_result_fields(event, rec)
      block = Array(rec.dig("message", "content")).first || {}
      tool = { "use_id" => block["tool_use_id"], "is_error" => block.fetch("is_error", false) }

      tur = rec["toolUseResult"]
      if tur.is_a?(Hash)
        tool["duration_ms"] = tur["durationMs"] || tur["totalDurationMs"]
        result = {}
        result["stdout"]           = tur["stdout"] if tur.key?("stdout")
        result["stderr"]           = tur["stderr"] if tur.key?("stderr")
        result["interrupted"]      = tur["interrupted"] if tur.key?("interrupted")
        result["num_files"]        = tur["numFiles"] if tur.key?("numFiles")
        result["structured_patch"] = tur["structuredPatch"] if tur["structuredPatch"]
        tool["result"] = result unless result.empty?

        if tur["totalTokens"]
          tool["subagent_tokens"] = {
            "total_tokens"          => tur["totalTokens"],
            "total_tool_use_count"  => tur["totalToolUseCount"],
          }
        end
      end
      event["tool"] = tool
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

    # ---- cross-event linking (item 3/10: light up the causal chain together) -
    #
    # Two independent pairings, both keyed by an id already carried in the log:
    #   tool_call <-> tool_result, by the tool_use_id both sides share.
    #   queue enqueue <-> dequeue/remove <-> the delivered task_notification,
    #   by task-id (from the <task-notification> XML) — dequeue/remove carry no
    #   id of their own, so pairing with their enqueue is positional (FIFO,
    #   which is exactly what a queue is).
    # A shared link_ids token on both events is all the renderer/JS need to
    # highlight the whole chain together; the original background tool_call
    # joins the chain too, via the tool-use-id embedded in the notification.
    def link_related_events!(events)
      calls_by_use_id = events.select { |e| e["kind"] == "tool_call" }
                               .to_h { |e| [e.dig("tool", "use_id"), e] }

      events.each do |e|
        next unless e["kind"] == "tool_result"

        use_id = e.dig("tool", "use_id")
        call = calls_by_use_id[use_id]
        next unless call

        link!(call, e, "tool:#{use_id}")
        name = call.dig("tool", "name")
        e["tool"]["name"] = name
        resummarize_tool_result!(e, name)
      end

      link_queue_lifecycle!(events, calls_by_use_id)
    end

    def resummarize_tool_result!(event, name)
      return unless name

      text = event.dig("detail", "text").to_s
      event["summary"] = truncate(text.empty? ? "#{name} — no output" : "#{name}: #{text}")
    end

    def link_queue_lifecycle!(events, calls_by_use_id)
      pending = []
      events.each do |e|
        case e["kind"]
        when "queue_operation" then link_queue_operation!(e, pending, calls_by_use_id)
        when "task_notification" then link_task_notification!(e, calls_by_use_id)
        end
      end
    end

    def link_queue_operation!(event, pending, calls_by_use_id)
      if event["operation"] == "enqueue"
        task_id, tool_use_id = task_notification_ids(event.dig("detail", "text"))
        pending << { event: event, task_id: task_id, tool_use_id: tool_use_id }
        return
      end

      enqueued = pending.shift
      return unless enqueued

      token = "queue:#{enqueued[:task_id] || "line-#{enqueued[:event].dig("source", "line")}"}"
      link!(enqueued[:event], event, token)
      link_to_originating_tool!(enqueued[:tool_use_id], calls_by_use_id, enqueued[:event], event)
    end

    def link_task_notification!(event, calls_by_use_id)
      task_id, tool_use_id = task_notification_ids(event.dig("detail", "text"))
      link_token!(event, "queue:#{task_id}") if task_id
      link_to_originating_tool!(tool_use_id, calls_by_use_id, event)
    end

    def link_to_originating_tool!(tool_use_id, calls_by_use_id, *events)
      return unless tool_use_id

      token = "tool:#{tool_use_id}"
      events.each { |e| link_token!(e, token) }
      call = calls_by_use_id[tool_use_id]
      link_token!(call, token) if call
    end

    def task_notification_ids(text)
      return [nil, nil] unless text

      [text[%r{<task-id>(.*?)</task-id>}m, 1], text[%r{<tool-use-id>(.*?)</tool-use-id>}m, 1]]
    end

    def link!(a, b, token)
      link_token!(a, token)
      link_token!(b, token)
    end

    def link_token!(event, token)
      return unless event

      ids = (event["link_ids"] ||= [])
      ids << token unless ids.include?(token)
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

    # Cosmetic-only cleanup for one-line plain-text summaries: strip the markdown
    # markup itself (not just leave it as literal asterisks/backticks), so a
    # truncated summary never shows a stray unmatched `**` or backtick. The full
    # text still gets real markdown rendering in the detail view (see
    # ConversationStory::Markdown) — this is only for the compact summary line.
    def strip_markdown(text)
      text.to_s
          .gsub(/^\#{1,6}\s+/, "")
          .gsub(/^[-*]\s+/, "")
          .gsub(/^\d+\.\s+/, "")
          .gsub(/```[^\n]*\n?/, "")
          .gsub(/(\*\*|__)(.+?)\1/, '\2')
          .gsub(/(?<![\w*])[*_]([^*_\n]+)[*_](?!\w)/, '\1')
          .gsub(/`([^`]+)`/, '\1')
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
