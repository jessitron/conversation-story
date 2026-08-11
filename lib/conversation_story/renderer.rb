# frozen_string_literal: true

require "erb"
require "cgi"
require "json"
require "time"
require_relative "markdown"

module ConversationStory
  # Turns an intermediate document (the hash loaded from a story.yaml) into a
  # static HTML page via ERB. The renderer reads ONLY the schema — never the
  # original log — and reproduces the look of assets/design-prototype.html by reusing
  # assets/story.css + assets/story.js as-is and generating only the per-event
  # card HTML and the header stats.
  class Renderer
    TEMPLATES = File.join(__dir__, "templates")

    # schema `kind` -> the CSS kind class the design uses (see the kind→color
    # table in assets/story.css). Several "background machinery" record types
    # share the quiet `system` treatment; `unknown` keeps its own class so the
    # fallback is visually spottable.
    CSS_KIND = Hash.new { |_h, k| k }.merge(
      "user_message"      => "user",
      "assistant_message" => "assistant",
      "thinking"          => "thinking",
      "tool_call"         => "tool_call",
      "tool_result"       => "tool_result",
      "subagent"          => "subagent",
      "subagent_result"   => "subagent_result",
      "system"            => "system",
      "attachment"        => "system",
      "file_snapshot"     => "system",
      "permission_mode"   => "system",
      "queue_operation"     => "system",
      "task_notification"   => "system",
      "coordinator_message" => "coordinator",
      "unknown"             => "unknown",
    ).freeze

    KIND_LABEL = {
      "user_message"        => "User",
      "assistant_message"   => "Assistant",
      "thinking"             => "Thinking",
      "tool_call"            => "Tool Call",
      "tool_result"          => "Tool Result",
      "subagent"             => "Subagent",
      "subagent_result"      => "Subagent Result",
      "system"               => "System",
      "attachment"           => "Attachment",
      "file_snapshot"        => "Snapshot",
      "permission_mode"      => "Permission",
      "queue_operation"      => "Queue",
      "task_notification"    => "Notification",
      "coordinator_message"  => "Coordinator",
      "unknown"              => "Unknown",
    }.freeze

    # the actor shown in the card gutter (by kind, not role: a tool_result is a
    # user-role record but comes from the system, not the human — and so is a
    # task_notification, a background result delivered mid-conversation).
    # A subagent's own cards say the AGENT's name here, not "Claude" — inside a
    # .subactions block, "who is acting" is the whole point of the indent (see
    # who_for). These are the kinds that get that substitution.
    WHO = Hash.new("system").merge(
      "user_message"      => "Jess",
      "assistant_message" => "Claude",
      "thinking"          => "Claude",
      "tool_call"         => "Claude",
      "subagent"          => "Claude",
    ).freeze

    DETAIL_HEADING = Hash.new("Detail").merge(
      "user_message"        => "Message",
      "assistant_message"   => "Message",
      "thinking"            => "Reasoning",
      "system"              => "System event",
      "task_notification"   => "Notification",
      "coordinator_message" => "Message",
    ).freeze

    # detail text for these kinds is conversational prose written in markdown;
    # everything else (tool output, XML/system blobs — including
    # task_notification, whose body is the <task-notification> XML, not prose)
    # is shown as literal text.
    MARKDOWN_KINDS = %w[user_message assistant_message thinking coordinator_message].freeze

    # tool_use input keys big enough that they get their own "Input" section
    # instead of a Fields row.
    BLOB_INPUT_KEYS = %w[command content prompt].freeze

    # Kinds whose detail pane ends in an arbitrarily long machine-text section.
    # They position their own Tokens section rather than letting detail_html
    # append it after the blob.
    BLOB_KINDS = %w[tool_call tool_result subagent subagent_result].freeze

    # @param document [Hash] the intermediate document (from YAML).
    def initialize(document)
      @document = document
      @meta   = document["meta"]  || {}
      @events = document["events"] || []
    end

    # @return [String] the complete HTML page.
    def to_html
      render(page_template,
             title:         h(@meta["name"]),
             subtitle:      h(subtitle),
             events_stat:   h(visible_events.size),
             duration_stat: h(duration),
             tokens_stat:   h(token_label(@meta["total_tokens"])),
             model_stat:    h(model_label(@meta["model"])),
             branch_stat:   h(@meta["git_branch"] || "—"),
             cards_html:    cards_html)
    end

    private

    # Events the page actually shows: harness-bookkeeping events are parsed and
    # kept in the document (so nothing is lost and provenance stays exact) but
    # carry `hidden: true`; the story page is the conversation from Jess's
    # perspective, so we drop them here.
    def visible_events
      @visible_events ||= @events.reject { |e| e["hidden"] }
    end

    # Every event that gets a card, subagents' nested stories included, in card
    # order. The lookups that answer "what else on this page relates to this?" —
    # causal chains and turn grouping — work over THIS list, so a subaction can
    # link to a main-log event and back.
    #
    # The header's "Events" stat deliberately stays on visible_events: that's the
    # size of the conversation being told, not the number of cards drawn (and
    # bin/site-index counts the same way, so the landing page can't drift).
    def all_visible_events
      @all_visible_events ||= flatten_visible(visible_events)
    end

    def flatten_visible(events)
      events.flat_map do |event|
        nested = (event.dig("subagent", "events") || []).reject { |e| e["hidden"] }
        [event, *flatten_visible(nested)]
      end
    end

    # A card's anchor IS its `ref` — the `<example>:<line>` string Jess already
    # uses to talk about events ("episode-8-before:174"). Sequential #event-N
    # numbering was a second, page-only coordinate system: it counted VISIBLE
    # events, so it drifted from the log's line numbers (line 174 was card 89)
    # and finding an event's link meant computing that offset. Now a ref pastes
    # straight after the `#`, and the copy-ref chip in the detail pane copies
    # exactly the string the URL wants. Refs are unique per page (one line, one
    # event) and colon-safe: it's a legal HTML id, a legal URL fragment, and
    # story.js resolves it with getElementById, never a `#id` CSS selector.
    def anchor_for(event)
      event["ref"]
    end

    def cards_html
      cards_for(visible_events)
    end

    # A `subagent` card is followed by its own story: the events that subagent
    # produced, as FULL cards (same size, same detail template, same
    # click-to-select) inside a `.subactions` wrapper that supplies the indent
    # and the rail. Recursive, because a subagent can spawn one too.
    def cards_for(events, agent_label = nil)
      events.map do |event|
        card = render_card(event, agent_label)
        event["kind"] == "subagent" ? card + subactions_html(event) : card
      end.join("\n")
    end

    # EXPANDED by default, all 70 subactions of it. The point of the page is to
    # show the work being done, and a subagent doing 27 tool calls in the middle
    # of the conversation IS the work — in narrate especially, where each beat
    # reveals the flurry a card at a time and the agent's busyness is the thing
    # Jess is narrating. The caret is there to quiet a subagent down, not to
    # keep it hidden until asked.
    def subactions_html(event)
      sub = event["subagent"] || {}
      nested = (sub["events"] || []).reject { |e| e["hidden"] }
      return "" if nested.empty?

      %(\n<div class="subactions">\n#{cards_for(nested, sub["agent_type"])}\n</div>)
    end

    def render_card(event, agent_label = nil)
      kind = event["kind"]
      render(card_template,
             anchor:       h(anchor_for(event)),
             css_kind:     CSS_KIND[kind],
             kind_html:    kind_html(event),
             who:          h(who_for(event, agent_label)),
             data_time:    h(time_of_day(event["at"])),
             link_attr:    link_attr(event),
             edited_attr:  event["summary_edited"] ? %( data-edited="true") : "",
             beat_attr:    event["beat"] ? %( data-beat="true") : "",
             summary_html: summary_html(event),
             badges_html:  badges_html(event),
             detail_html:  detail_html(event))
    end

    # The gutter's kind label — plus, on a subagent, the caret that collapses its
    # subactions (assets/story.js toggles `.collapsed` on the card; the CSS hides
    # the adjacent wrapper).
    def kind_html(event)
      label = h(KIND_LABEL.fetch(event["kind"], event["kind"]))
      return label unless event["kind"] == "subagent"

      %(#{label}<span class="caret">▾</span>)
    end

    # Inside a subagent's block, the actor is that agent — "Explore", not
    # "Claude". Only the kinds WHO calls Claude change; a tool_result still comes
    # from the system. A `subagent` card names the agent it spawned, at any depth.
    # A `coordinator_message` is the ORCHESTRATOR speaking into this subagent —
    # always "Claude", never substituted for the subagent's own name (that
    # would credit the subagent with steering itself).
    def who_for(event, agent_label)
      return event.dig("subagent", "agent_type") || "Claude" if event["kind"] == "subagent"
      return "Claude" if event["kind"] == "coordinator_message"

      who = WHO[event["kind"]]
      agent_label && who == "Claude" ? agent_label : who
    end

    # A related-events highlight hook (items 3 & 10): the parser already
    # figured out which events are causally linked (a tool_call and its
    # tool_result; a queue enqueue, its dequeue, and the delivered
    # task_notification; the tool_call that spawned a background task) and
    # gave every event in a chain a shared token in `link_ids`. Cards just
    # carry the tokens as a data attribute; assets/story.js does the matching.
    def link_attr(event)
      ids = event["link_ids"]
      return "" if ids.nil? || ids.empty?

      %( data-link="#{h ids.join(" ")}")
    end

    # link_id token -> [[position, event], ...], built once over the visible
    # sequence so detail sections can turn an event's own link_ids into
    # jump-to-anchor buttons for the rest of its causal chain. The position is
    # only a sort key (chain buttons read in page order); the button's href
    # comes from the event's ref.
    def link_index
      @link_index ||= Hash.new { |h, k| h[k] = [] }.tap do |idx|
        all_visible_events.each_with_index { |e, i| (e["link_ids"] || []).each { |tok| idx[tok] << [i, e] } }
      end
    end

    # Every OTHER visible event that shares a link_id token with this one
    # (deduped, in card order) — the data the "Related events" detail section
    # renders as buttons.
    def related_events(event)
      ids = event["link_ids"]
      return [] if ids.nil? || ids.empty?

      found = {}
      ids.each { |tok| link_index[tok].each { |i, e| found[i] ||= e unless e["ref"] == event["ref"] } }
      found.sort.map(&:last)
    end

    # ---- summary (card face) --------------------------------------------------

    # A hand-written summary (Mount Malleable — see lib/conversation_story/edits.rb)
    # wins over every generated face, including the tool-call one below: if Jess
    # rewrote the line, her line is what shows.
    def summary_html(event)
      return h(event["summary"]) if event["summary_edited"]

      case event["kind"]
      when "tool_call" then tool_call_summary_html(event)
      when "subagent"  then subagent_summary_html(event)
      else h(event["summary"])
      end
    end

    # Same shape as a tool call's face — bold WHO, then WHAT. For a subagent the
    # who is the agent type and the what is the job it was handed.
    def subagent_summary_html(event)
      type = event.dig("subagent", "agent_type")
      name = type ? %(<b>#{h type}</b> ) : ""
      "#{name}#{h event["summary"]}"
    end

    # Matches the prototype's tool-call look: bold tool name, the primary
    # argument as an inline code chip (item 2, 6, 7 — tool calls were showing
    # neither their name distinctly nor their arguments at all).
    def tool_call_summary_html(event)
      tool = event["tool"] || {}
      name = %(<b>#{h tool["name"]}</b>)
      arg  = tool["primary_arg"]
      arg ? %(#{name} <code>#{h arg}</code>) : name
    end

    def badges_html(event)
      badges = case event["kind"]
               when "tool_call"   then tool_call_badges(event)
               when "tool_result" then tool_result_badges(event)
               # An Agent badge, the way a tool_call badges its tool name — on
               # BOTH halves of the pair, since a tool_result badges its tool too
               # and the answer coming back is as much "an agent thing" as the
               # call. No token or tool-count badges: those are detail, and
               # they're in the Fields section already — a card face is a
               # headline.
               when "subagent", "subagent_result"
                 [%(<span class="badge agent">Agent</span>)]
               when "queue_operation" then queue_operation_badges(event)
               else []
               end
      badges << %(<span class="badge queue">Dequeued</span>) if event["dequeued"]
      badges << %(<span class="badge queue">From queue</span>) if event["removed_from_queue"]
      # A background job the harness itself marked failed (parser: status, read
      # off the <task-notification> blob). Same Error badge a failed tool_result
      # wears — one look for "this didn't work", wherever the news arrives.
      badges << %(<span class="badge err">Error</span>) if event["status"] == "failed"
      return "" if badges.empty?

      %(<div class="badges">#{badges.join}</div>)
    end

    # The gutter says "Queue"; the badge says WHICH operation — in practice
    # always `enqueue`, since the bare dequeue/remove markers are hidden and the
    # detour shows up as a badge on the message they deliver instead.
    def queue_operation_badges(event)
      op = event["operation"]
      op ? [%(<span class="badge queue">#{h op}</span>)] : []
    end

    def tool_call_badges(event)
      [%(<span class="badge tool">#{h event.dig("tool", "name")}</span>)]
    end

    def tool_result_badges(event)
      badges = []
      name = event.dig("tool", "name")
      badges << %(<span class="badge tool">#{h name}</span>) if name
      badges << %(<span class="badge err">Error</span>) if event.dig("tool", "is_error")
      badges
    end

    # ---- detail (drill-in) markup -------------------------------------------

    # Where the token numbers sit depends on what else is in the pane. A tool
    # call's Input and a tool result's Result can each run for hundreds of
    # lines, so those kinds place their numbers ABOVE the blob (see
    # tool_call_sections / tool_result_sections) — appended, they'd sit below a
    # full screen of scrolling and nobody would find them. Prose kinds read
    # better the other way round: the message first, then what it cost.
    def detail_html(event)
      sections = kind_sections(event)
      sections << turn_tool_calls_section(event)
      sections << tokens_section(event) unless BLOB_KINDS.include?(event["kind"])
      sections << related_events_section(event)
      sections << section("Provenance", provenance_dl(event))
      # The copyable event id goes last and understated — it's a debugging aid.
      sections << event_id_footer(event) if event["ref"]
      sections.join("\n")
    end

    # Buttons for every other event in this one's causal chain (item: "show
    # linked events on the details tab"). Plain <a href="#<ref>"> anchors —
    # clicking one changes location.hash, and assets/story.js's hashchange
    # listener (already wired for deep links) picks it up and selects that
    # card; no new JS needed.
    def related_events_section(event)
      related = related_events(event)
      return "" if related.empty?

      links = related.map { |e| related_link_html(e) }.join
      section("Related events", %(<div class="related-links">#{links}</div>))
    end

    def related_link_html(event)
      kind = h(KIND_LABEL.fetch(event["kind"], event["kind"]))
      summary = event["kind"] == "tool_call" ? tool_call_summary_html(event) : h(event["summary"])
      %(<a class="related-link" href="##{h anchor_for(event)}">) +
        %(<span class="kind-tag">#{kind}</span><span class="summary">#{summary}</span></a>)
    end

    # "Say when an assistant turn includes tool calls." The tool_use records
    # sharing this message's id came back in the SAME API response — they are
    # literally what the assistant returned alongside its prose, so the message
    # card names them. Reuses the related-link markup (and its CSS): these are
    # the same kind of thing, a jump to another card in this story.
    #
    # Deliberately NOT wired into link_ids: that token drives the board-wide
    # causal highlight, and lighting up a whole turn every time you select any
    # part of it would drown out the tool_call↔tool_result chains it exists for.
    def turn_tool_calls_section(event)
      return "" unless event["kind"] == "assistant_message"

      calls = turn_tool_calls(event)
      return "" if calls.empty?

      links = calls.map { |e| related_link_html(e) }.join
      section("Tool calls in this turn", %(<div class="related-links">#{links}</div>))
    end

    def turn_tool_calls(event)
      id = event.dig("links", "message_id")
      return [] unless id

      turn_index[id].select { |e| e["kind"] == "tool_call" }
    end

    # message_id -> its visible events, in card order.
    def turn_index
      @turn_index ||= Hash.new { |h, k| h[k] = [] }.tap do |idx|
        all_visible_events.each do |e|
          id = e.dig("links", "message_id")
          idx[id] << e if id
        end
      end
    end

    # ---- tokens --------------------------------------------------------------

    # Tokens belong to a turn, not a record (see Parser#mark_turns!), so the
    # real numbers print once per turn, on the record the parser elected.
    # tool_results get result_tokens_section instead: an estimate, labelled.
    def tokens_section(event)
      return first_message_tokens_section(event) if event.dig("tokens", "system_prompt_estimate")
      return "" unless event["turn_leader"]

      tokens = event["tokens"]
      return "" unless tokens

      rows = [
        ["Context so far", comma(tokens["context_so_far"])],
        ["New content",    comma(tokens["new_content"])],
      ]
      rows << ["Re-cached (overhead)", comma(tokens["rewrite_overhead"])] if tokens["rewrite_overhead"].to_i > 0
      rows += [
        ["Context",     "#{comma tokens["context"]}#{cached_note(tokens)}"],
        ["Added",       comma(tokens["added"])],
        ["Cache write", comma(tokens["cache_creation"])],
        ["Output",      comma(tokens["output"])],
        ["Total input", comma(tokens["cumulative_context"])],
      ]
      section("Tokens", kv_dl(rows))
    end

    # Turn 1's real `added` pays for this message AND the system prompt AND the
    # tool schemas, all as one cache write — see Parser#mark_first_turn_breakdown!.
    # This message's own size is the one piece we can estimate independently;
    # the rest is named rather than left as an unexplained gap in turn 1's math.
    def first_message_tokens_section(event)
      tokens = event["tokens"]
      rows = [
        ["Message size (est.)",       "≈#{comma tokens["estimated_input"]}"],
        ["System prompt + tools (est.)", "≈#{comma tokens["system_prompt_estimate"]}"],
      ]
      section("Turn 1 breakdown",
              kv_dl(rows) + %(<p class="d-note">Estimated from the message's length. ) +
              %(The API bills the system prompt, tool schemas, and this message ) +
              %(together as one cache write — this message's share is estimated; ) +
              %(the rest is what's left.</p>))
    end

    def cached_note(tokens)
      read = tokens["cache_read"].to_i
      read.zero? ? "" : " (#{comma read} cached)"
    end

    # The result is what actually lands in the context, but no count of it
    # exists in the log (Parser::CHARS_PER_TOKEN explains why). Mark it as an
    # estimate — the ≈ and the note — rather than pretending it's a measurement.
    def result_tokens_section(event)
      est = event.dig("tokens", "estimated_input")
      dark = event.dig("tokens", "dark_matter_estimate")
      return "" unless est || dark

      rows = []
      rows += [["Result size", byte_label(event.dig("tokens", "result_chars"))],
               ["Est. tokens", "≈#{comma est}"]] if est
      rows << ["Dark matter share", "≈#{comma dark}"] if dark
      note = est ? "Estimated from the result's length. " : ""
      note += "Dark matter: this turn's cache write is bigger than everything visible " \
              "can explain; this is this event's share of what's left over. " if dark
      section("Added to context",
              kv_dl(rows) + %(<p class="d-note">#{note}The log reports token counts ) +
              %(only on assistant turns.</p>))
    end

    def kind_sections(event)
      case event["kind"]
      when "tool_call"        then tool_call_sections(event)
      when "tool_result"      then tool_result_sections(event)
      when "subagent"         then subagent_sections(event)
      when "subagent_result"  then subagent_result_sections(event)
      else generic_sections(event)
      end
    end

    # The pane for a spawned agent: who it was, what it was told, what it cost
    # the PARENT to make the call. What the subagent then did is on the board
    # itself, behind the caret — not duplicated here.
    def subagent_sections(event)
      sub = event["subagent"] || {}
      sections = [section("Subagent — #{sub["agent_type"] || "agent"}", "")]
      sections << section("Fields", kv_dl(subagent_field_rows(event, sub)))
      sections << tokens_section(event)
      prompt = event.dig("tool", "input", "prompt")
      sections << section("Prompt", machine_html(prompt)) if prompt
      sections
    end

    def subagent_field_rows(event, sub)
      meta = sub["meta"] || {}
      rows = [["agent_id", sub["agent_id"]], ["agent_type", sub["agent_type"]]]
      rows << ["description", sub["description"]] if sub["description"]
      rows << ["spawned_by", event.dig("tool", "use_id")]
      # its own story's numbers, from its own log — not the parent's. `subactions`
      # counts the cards behind the caret (so it matches what expanding shows),
      # and `own token use` is the same measure as the header's Tokens stat: every
      # turn of the subagent's own conversation, counted once.
      nested = (sub["events"] || []).reject { |e| e["hidden"] }
      rows << ["subactions", nested.size] unless nested.empty?
      rows << ["own token use", comma(meta["total_tokens"])] if meta["total_tokens"]
      rows << ["log", sub["log"]] if sub["log"]
      rows
    end

    # The answer coming back. Same quiet, machine-voiced shape as a tool result
    # (it IS the Agent tool's result record) — but attributed to the agent, and
    # carrying the totals the harness reports for the whole subagent run.
    def subagent_result_sections(event)
      tool = event["tool"] || {}
      sections = [section("Subagent result — #{tool["agent_type"] || "agent"}", "")]
      sections << section("Fields", subagent_result_fields_dl(tool))
      sections << result_tokens_section(event)
      # PROSE, not machine voice — the one deliberate exception among tool
      # results. This text isn't program output; it's one agent's written report
      # to another, in markdown, and reads as badly in a mono blob as any other
      # message would. Everything else about the card stays quiet.
      text = event.dig("detail", "text")
      sections << section("Answer", %(<div class="d-markdown">#{Markdown.to_html(text)}</div>)) if text && !text.empty?
      sections
    end

    def subagent_result_fields_dl(tool)
      rows = [["For", tool["use_id"]], ["agent_id", tool["agent_id"]]]
      rows << ["status", tool["status"]] if tool["status"]
      rows << ["Error", tool["is_error"]] if tool["is_error"]
      rows << ["Duration", "#{tool["duration_ms"]} ms"] if tool["duration_ms"]
      if (st = tool["subagent_tokens"])
        rows << ["total_tokens", comma(st["total_tokens"])]
        rows << ["tool_uses", st["total_tool_use_count"]]
      end
      kv_dl(rows)
    end

    def generic_sections(event)
      sections = [text_section(event)]
      sections << mode_section(event)
      # The first user_message gets its own "Turn 1 breakdown" from
      # tokens_section instead (see Parser#mark_first_turn_breakdown!) — skip
      # this one there so its estimate doesn't print twice.
      sections << result_tokens_section(event) unless event.dig("tokens", "system_prompt_estimate")
      if (raw = event.dig("detail", "raw"))
        sections << section("Raw record", machine_html(JSON.pretty_generate(raw)))
      end
      sections
    end

    # The mode a prompt was sent in — a field the prompt record carries.
    def mode_section(event)
      return "" unless event["mode"]

      section("Mode", kv_dl([["Mode", event["mode"]]]))
    end

    # Conversational kinds (user/assistant messages, reasoning) render their text
    # as markdown — the prose voice. Everything else is machine text (a
    # <task-notification> blob, a queued payload, an attachment dump), so it gets
    # the same treatment as a tool's Input and Result: `machine_html`.
    def text_section(event)
      heading = DETAIL_HEADING[event["kind"]]
      text = event.dig("detail", "text") || event["summary"]
      if MARKDOWN_KINDS.include?(event["kind"])
        section(heading, %(<div class="d-markdown">#{Markdown.to_html(text)}</div>))
      else
        section(heading, machine_html(text))
      end
    end

    # The one treatment for text a program wrote or read — tool input, tool
    # result, a notification blob, a raw record. Same font, same background
    # everywhere (see the `pre.code` comment in assets/story.css).
    def machine_html(text)
      %(<pre class="code">#{h text}</pre>)
    end

    def tool_call_sections(event)
      tool = event["tool"] || {}
      sections = [section("Tool call — #{tool["name"]}", "")]
      sections << section("Fields", tool_call_fields_dl(tool))
      # A bare tool_use turn has no message card, so this card is the turn
      # leader and carries the turn's numbers — above the Input blob.
      sections << tokens_section(event)
      input_html = tool_call_input_html(tool)
      sections << section("Input", input_html) if input_html
      sections
    end

    def tool_call_fields_dl(tool)
      rows = [["Tool", tool["name"]], ["use_id", tool["use_id"]]]
      (tool["input"] || {}).each do |k, v|
        next if BLOB_INPUT_KEYS.include?(k) || v.is_a?(Hash) || v.is_a?(Array)

        rows << [k, v]
      end
      kv_dl(rows)
    end

    def tool_call_input_html(tool)
      input = tool["input"] || {}
      return nil if input.empty?

      blob = BLOB_INPUT_KEYS.map { |k| input[k] }.compact.first
      body = blob ? blob.to_s : JSON.pretty_generate(input)
      machine_html(body)
    end

    def tool_result_sections(event)
      tool = event["tool"] || {}
      heading = tool["name"] ? "Tool result — #{tool["name"]}" : "Tool result"
      sections = [section(heading, "")]
      sections << section("Fields", tool_result_fields_dl(tool))
      sections << result_tokens_section(event)
      text = event.dig("detail", "text")
      sections << section("Result", machine_html(text)) if text && !text.empty?
      sections
    end

    def tool_result_fields_dl(tool)
      rows = [["For", tool["use_id"]], ["Error", tool["is_error"]]]
      rows << ["Duration", "#{tool["duration_ms"]} ms"] if tool["duration_ms"]

      result = tool["result"] || {}
      rows << ["num_files", result["num_files"]] if result["num_files"]
      rows << ["stderr", result["stderr"]] if result["stderr"] && !result["stderr"].empty?

      if (st = tool["subagent_tokens"])
        rows << ["total_tokens", st["total_tokens"]]
        rows << ["tool_uses", st["total_tool_use_count"]]
      end
      kv_dl(rows)
    end

    def kv_dl(rows)
      %(<dl class="kv">#{rows.map { |k, v| %(<dt>#{h k}</dt><dd><code>#{h v}</code></dd>) }.join}</dl>)
    end

    # A quiet, click-to-copy footer for the event's human-referable id. It's a
    # debugging handle, so it sits last with no section heading and stays faint;
    # the "copy" hint only surfaces on hover. assets/story.js copies data-copy to
    # the clipboard on click (with a file:// fallback) and flashes confirmation.
    def event_id_footer(event)
      ref = h(event["ref"])
      %(<div class="d-footer"><button type="button" class="copy-ref" ) +
        %(data-copy="#{ref}" title="Copy event id to clipboard">) +
        %(<code>#{ref}</code><span class="copy-hint">copy</span></button></div>)
    end

    def provenance_dl(event)
      src = event["source"] || {}
      rows = [
        ["source.file", src["file"]],
        ["source.line", src["line"]],
        ["agent", event["agent"]],
      ]
      links = event["link_ids"]
      rows << ["link_ids", links.join(", ")] if links && !links.empty?
      kv_dl(rows)
    end

    def section(title, inner_html)
      %(<div class="d-section"><h4 class="deco">#{h title}</h4>#{inner_html}</div>)
    end

    # ---- header stats --------------------------------------------------------

    def subtitle
      # "episode-8-before" -> "episode 8 · before"
      name = @meta["name"].to_s
      return name if name.empty?

      name.tr("-", " ").sub(/\A(episode) (\d+) (.+)\z/, '\1 \2 · \3')
    end

    def duration
      started = @meta["started_at"]
      ended   = @meta["ended_at"]
      return "—" unless started && ended

      secs = (Time.iso8601(ended) - Time.iso8601(started)).round
      format_duration(secs)
    rescue ArgumentError
      "—"
    end

    def format_duration(secs)
      return "#{secs}s" if secs < 60

      m, s = secs.divmod(60)
      return "#{m}m #{s}s" if m < 60

      h, m = m.divmod(60)
      "#{h}h #{m}m"
    end

    # 1212680 -> "1.21M", 45195 -> "45.2k". A header stat is for scale; the
    # exact running count is in each turn's Tokens section.
    def token_label(tokens)
      return "—" unless tokens
      return tokens.to_s if tokens < 1000
      return format("%.1fk", tokens / 1000.0) if tokens < 1_000_000

      format("%.2fM", tokens / 1_000_000.0)
    end

    # "claude-opus-4-6" -> "Opus 4.6"; unknown shapes pass through unchanged.
    def model_label(model)
      return "—" if model.to_s.empty?

      if (m = model.match(/\Aclaude-([a-z]+)-([\d-]+)/))
        "#{m[1].capitalize} #{m[2].tr("-", ".")}"
      else
        model
      end
    end

    # "2026-04-14T02:27:16.236Z" -> "02:27:16"; nil/odd shapes -> "".
    def time_of_day(at)
      at.to_s[/T(\d{2}:\d{2}:\d{2})/, 1].to_s
    end

    # ---- plumbing ------------------------------------------------------------

    def h(value)
      CGI.escapeHTML(value.to_s)
    end

    # 1206583 -> "1,206,583". Token counts are read as magnitudes; the .kv cells
    # are already tabular-nums, so grouped digits line up down the column.
    def comma(number)
      number.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    end

    def byte_label(chars)
      chars < 1024 ? "#{chars} B" : format("%.1f KB", chars / 1024.0)
    end

    def render(template, **locals)
      template.result_with_hash(locals)
    end

    def page_template
      @page_template ||= ERB.new(File.read(File.join(TEMPLATES, "page.html.erb")), trim_mode: "-")
    end

    def card_template
      @card_template ||= ERB.new(File.read(File.join(TEMPLATES, "card.html.erb")), trim_mode: "-")
    end

    # These three derive a human label from `meta` alone — they don't touch the
    # events or the page. bin/site-index shows the same labels on the landing
    # page's card for each story, so they're part of the renderer's surface
    # rather than page-internal helpers. One source for "how a story is
    # described", so the landing page can't drift from the page it links to.
    public :subtitle, :duration, :model_label
  end
end
