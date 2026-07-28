# frozen_string_literal: true

require "json"

module ConversationStory
  # Reads a Claude conversation log (a .jsonl file, one JSON record per line) and
  # produces the intermediate "document": a Ruby hash matching the schema in
  # notes/intermediate-schema.md, ready to serialize as YAML.
  #
  # Granularity: ONE event per record (per line). The golden test
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
    # queue-operation and task_notification stay visible — EXCEPT the bare
    # `dequeue`/`remove` markers, which are hidden: they carry no content of
    # their own, and the event each one delivers gets `dequeued: true` or
    # `removed_from_queue: true` instead (see match_delivery! below), so the
    # "took a detour through the queue" fact still shows, just on the event
    # that actually has something to say.

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

    # A tool result is the thing that actually grows the context, but the log
    # never counts one: `usage` appears on assistant records only. The single
    # measured signal is the context delta at the next turn, and in the example
    # logs that gap ALWAYS also holds harness records — 0 of 32 gaps contain a
    # tool result by itself — so it can't be attributed cleanly. Hence an
    # estimate from length. Calibrating against those deltas put the median near
    # 2.5 chars/token, but the delta overstates the result's own share (it
    # covers the whole gap), and tool output is code and JSON, which tokenizes
    # denser than the prose-tuned 4. 3.5 splits the difference. Retune here if a
    # better measurement turns up; the renderer labels the number an estimate.
    CHARS_PER_TOKEN = 3.5

    ELLIPSIS = "…"
    SUMMARY_LIMIT = 140
    # user/assistant messages are the actual conversation — the headline
    # content of the page — so they get a much longer leash before truncating
    # than the "background machinery" kinds (tool calls, thinking, etc).
    MESSAGE_SUMMARY_LIMIT = 400

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
      mark_turns!(events)
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
      return "thinking" if blocks.any? { |b| %w[thinking redacted_thinking].include?(b["type"]) }

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
      when "user_message"      then truncate(strip_markdown(rec.dig("message", "content").to_s), MESSAGE_SUMMARY_LIMIT)
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
      truncate(strip_markdown(text), MESSAGE_SUMMARY_LIMIT)
    end

    def thinking_summary(rec)
      return "(reasoning — redacted by Anthropic)" if redacted_thinking?(rec)

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
      summary_from_task_notification(rec.dig("message", "content").to_s)
    end

    def summary_from_task_notification(text)
      inner = text[%r{<summary>(.*?)</summary>}m, 1]
      truncate(inner || text)
    end

    def system_summary(rec)
      sub = rec["subtype"] || "system"
      count = rec["hookCount"]
      count ? "#{sub} — #{count} hook#{"s" unless count == 1}" : sub
    end

    # `queued_command` carries the same payload shapes as a top-level
    # `task_notification`/`user_message` (it's the same content, just delivered
    # via the queue-detour envelope instead) — extract its <summary> the same
    # way, so the card doesn't just say the literal type name "queued_command".
    def attachment_summary(rec)
      att = rec["attachment"] || {}
      return queued_command_summary(att) if att["type"] == "queued_command"

      label = [att["type"], att["hookName"] || att["hookEvent"]].compact.join(": ")
      label.empty? ? "Attachment" : label
    end

    def queued_command_summary(att)
      queued_payload_summary(att["prompt"].to_s)
    end

    # An `enqueue` carries the payload it is queueing (a message Jess typed while
    # the agent was busy, or a background <task-notification>) — that payload is
    # the interesting part, so the summary says WHAT got queued, not just that
    # something did. `dequeue`/`remove` are bare markers with nothing to show
    # (and are hidden anyway), so they keep the short verb.
    def queue_summary(rec)
      op = rec["operation"] || "queue"
      payload = queued_payload_summary(rec["content"].to_s)
      payload.empty? ? "Queue #{op}" : truncate("Queue #{op}: #{payload}")
    end

    # The same payload shapes a `queued_command` attachment carries: either a
    # <task-notification> blob (whose <summary> is the point) or plain text.
    def queued_payload_summary(content)
      return "" if content.strip.empty?
      return summary_from_task_notification(content) if content.strip.start_with?(TASK_NOTIFICATION_TAG)

      truncate(strip_markdown(content))
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

    # A `redacted_thinking` block carries only an encrypted `data` blob (no
    # human-readable `thinking` text) — Anthropic redacted the reasoning
    # content itself, not just this parser's view of it.
    def redacted_thinking?(rec)
      Array(rec.dig("message", "content")).any? { |b| b["type"] == "redacted_thinking" }
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
      if key && input[key]
        # Read/Write/Edit take a file_path; the directory is rarely the
        # interesting part of a one-line summary, so show just the filename.
        value = key == "file_path" ? File.basename(input[key].to_s) : input[key].to_s
        return truncate(value, 90)
      end
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
      add_result_token_estimate(event)
    end

    # What this result added to the context — estimated, because nothing counts
    # it (see CHARS_PER_TOKEN). Named `estimated_input` rather than `input` so
    # no consumer can mistake it for a number the API reported; the renderer
    # prints it with a ≈ and says where it came from.
    def add_result_token_estimate(event)
      chars = event.dig("detail", "text").to_s.length
      return if chars.zero?

      event["tokens"] = {
        "result_chars"    => chars,
        "estimated_input" => (chars / CHARS_PER_TOKEN).round,
      }
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

      # `message.id` is what makes a TURN visible in the schema: the thinking
      # record, the text record and each tool_use record of one API response all
      # carry it. mark_turns! groups on it, and the renderer uses it to show an
      # assistant message the tool calls that came back with it.
      event["links"] = { "message_id" => msg["id"] } if msg["id"]

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

    # ---- assistant turns -----------------------------------------------------
    #
    # One API response can span several records — a thinking block, a text
    # block, and one record per tool_use, all sharing `message.id` — and EVERY
    # one of them repeats the whole turn's `usage`. So token counts are a fact
    # about the TURN, not the record: attributing them per record would triple
    # count a running total, and would print the same numbers on three cards.
    #
    # Each turn therefore elects a `turn_leader`, the one record that shows the
    # numbers: the assistant_message record when the turn produced prose, and
    # the turn's first record otherwise. The fallback is not hypothetical — 7 of
    # 33 turns in episode-8-before (11 of 28 in episode-8-after) are bare
    # tool_use with no text block, and without it their tokens, and the jump
    # they cause in the running total, would appear on no card at all.
    def mark_turns!(events)
      running = 0
      turns(events).each_value do |group|
        leader = group.find { |e| e["kind"] == "assistant_message" } || group.first
        leader["turn_leader"] = true

        tokens = leader["tokens"]
        next unless tokens

        # The context actually sent this turn: fresh tokens, tokens written to
        # the cache, and tokens read back from it. The log's bare `input_tokens`
        # is only the uncached remainder — typically 1 or 3, which is why it
        # can't be shown on its own as "the context length".
        tokens["context"] = %w[input cache_creation cache_read].sum { |k| tokens[k].to_i }
        tokens["added"]   = tokens["input"].to_i + tokens["cache_creation"].to_i
        running += tokens["context"]
        tokens["cumulative_context"] = running
      end
    end

    # message_id => that turn's records, in log order. A record with no message
    # id becomes a turn of its own (defensive — none in the example logs).
    def turns(events)
      events.each_with_object({}) do |e, acc|
        next unless e["role"] == "assistant"

        id = e.dig("links", "message_id") || "line-#{e.dig("source", "line")}"
        (acc[id] ||= []) << e
      end
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

    # The card already carries a "Bash"/"Read"/etc. tool badge, so the summary
    # itself doesn't need to repeat the tool name — just the output.
    def resummarize_tool_result!(event, name)
      return unless name

      text = event.dig("detail", "text").to_s
      event["summary"] = truncate(text.empty? ? "No output" : text)
    end

    def link_queue_lifecycle!(events, calls_by_use_id)
      pending = []
      awaiting_delivery = []
      events.each do |e|
        case e["kind"]
        when "queue_operation"
          link_queue_operation!(e, pending, awaiting_delivery, calls_by_use_id)
        when "task_notification", "user_message", "attachment"
          match_delivery!(e, awaiting_delivery)
          link_task_notification!(e, calls_by_use_id) if e["kind"] == "task_notification"
        end
      end
    end

    def link_queue_operation!(event, pending, awaiting_delivery, calls_by_use_id)
      if event["operation"] == "enqueue"
        task_id, tool_use_id = task_notification_ids(event.dig("detail", "text"))
        pending << { event: event, task_id: task_id, tool_use_id: tool_use_id,
                      content: event.dig("detail", "text") }
        return
      end

      enqueued = pending.shift
      return unless enqueued

      token = "queue:#{enqueued[:task_id] || "line-#{enqueued[:event].dig("source", "line")}"}"
      link!(enqueued[:event], event, token)
      link_to_originating_tool!(enqueued[:tool_use_id], calls_by_use_id, enqueued[:event], event)

      # A bare `dequeue`/`remove` marker carries no content of its own — it's
      # redundant once the event it delivers downstream is tagged
      # `dequeued: true` / `removed_from_queue: true` (below), so hide it the
      # same way an empty task_reminder is hidden.
      event["hidden"] = true
      awaiting_delivery << enqueued.merge(token: token, operation: event["operation"])
    end

    # Finds the event that actually delivers a dequeued/removed item's content
    # — a `task_notification` matched by task-id, a `queued_command` attachment
    # (also matched by task-id, since it carries the same <task-notification>
    # payload through the queue-detour envelope), or (for a plain queued Jess
    # message) the next `user_message` with identical text — and tags it
    # `dequeued: true` or `removed_from_queue: true` (depending on which marker
    # took it off the queue) so the renderer can show it took a detour through
    # the queue instead of arriving as this turn's ordinary input.
    def match_delivery!(event, awaiting_delivery)
      text = event.dig("detail", "text")
      task_id = task_notification_ids(text)[0]
      idx = awaiting_delivery.index do |pd|
        (pd[:task_id] && pd[:task_id] == task_id) || (pd[:content] && pd[:content] == text)
      end
      return unless idx

      pending_item = awaiting_delivery.delete_at(idx)
      field = pending_item[:operation] == "remove" ? "removed_from_queue" : "dequeued"
      event[field] = true
      link_token!(event, pending_item[:token])
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
        "total_tokens" => total_tokens(events),
        "agents"      => build_agents,
      }
    end

    # What the whole conversation cost: every turn's full input context plus
    # everything that turn generated. One number for the story — the page
    # header's TOKENS stat. nil when no assistant turn carries usage.
    #
    # Counted once per TURN, which is the only reason this sum means anything:
    # the several records of one response each repeat its usage, so summing
    # records would multiply the total (see mark_turns!). Note this is token
    # USE, not a context size — most of it is the same context re-sent and
    # mostly cache-read each turn, which is why the header calls it Tokens.
    def total_tokens(events)
      leaders = events.select { |e| e["turn_leader"] && e["tokens"] }
      return nil if leaders.empty?

      leaders.sum { |e| e["tokens"]["context"].to_i + e["tokens"]["output"].to_i }
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
