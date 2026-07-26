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
      "system"            => "system",
      "attachment"        => "system",
      "file_snapshot"     => "system",
      "permission_mode"   => "system",
      "queue_operation"   => "system",
      "task_notification" => "system",
      "unknown"           => "unknown",
    ).freeze

    KIND_LABEL = {
      "user_message"      => "User",
      "assistant_message" => "Assistant",
      "thinking"           => "Thinking",
      "tool_call"          => "Tool Call",
      "tool_result"        => "Tool Result",
      "subagent"           => "Subagent",
      "system"             => "System",
      "attachment"         => "Attachment",
      "file_snapshot"      => "Snapshot",
      "permission_mode"    => "Permission",
      "queue_operation"    => "Queue",
      "task_notification"  => "Notification",
      "unknown"            => "Unknown",
    }.freeze

    # the actor shown in the card gutter (by kind, not role: a tool_result is a
    # user-role record but comes from the system, not the human — and so is a
    # task_notification, a background result delivered mid-conversation).
    WHO = Hash.new("system").merge(
      "user_message"      => "Jess",
      "assistant_message" => "Claude",
      "thinking"          => "Claude",
      "tool_call"         => "Claude",
    ).freeze

    DETAIL_HEADING = Hash.new("Detail").merge(
      "user_message"      => "Message",
      "assistant_message" => "Message",
      "thinking"          => "Reasoning",
      "system"            => "System event",
      "task_notification" => "Notification",
    ).freeze

    # detail text for these kinds is conversational prose written in markdown;
    # everything else (tool output, XML/system blobs — including
    # task_notification, whose body is the <task-notification> XML, not prose)
    # is shown as literal text.
    MARKDOWN_KINDS = %w[user_message assistant_message thinking].freeze

    # tool_use input keys big enough that they get their own "Input" section
    # instead of a Fields row.
    BLOB_INPUT_KEYS = %w[command content prompt].freeze

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
             model_stat:    h(model_label(@meta["model"])),
             branch_stat:   h(@meta["git_branch"] || "—"),
             cards_html:    cards_html)
    end

    private

    # Events the page actually shows: harness-bookkeeping events are parsed and
    # kept in the document (so nothing is lost and provenance stays exact) but
    # carry `hidden: true`; the story page is the conversation from Jess's
    # perspective, so we drop them here. Card numbering runs over the visible
    # sequence, keeping #event-N anchors dense and 1-based.
    def visible_events
      @visible_events ||= @events.reject { |e| e["hidden"] }
    end

    def cards_html
      visible_events.each_with_index.map { |event, i| render_card(event, i + 1) }.join("\n")
    end

    def render_card(event, index)
      kind = event["kind"]
      render(card_template,
             n:            index,
             css_kind:     CSS_KIND[kind],
             kind_label:   h(KIND_LABEL.fetch(kind, kind)),
             who:          h(WHO[kind]),
             data_time:    h(time_of_day(event["at"])),
             link_attr:    link_attr(event),
             summary_html: summary_html(event),
             badges_html:  badges_html(event),
             detail_html:  detail_html(event, index))
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

    # link_id token -> [[card index, event], ...], built once over the visible
    # sequence so detail sections can turn an event's own link_ids into
    # jump-to-anchor buttons for the rest of its causal chain.
    def link_index
      @link_index ||= Hash.new { |h, k| h[k] = [] }.tap do |idx|
        visible_events.each_with_index { |e, i| (e["link_ids"] || []).each { |tok| idx[tok] << [i + 1, e] } }
      end
    end

    # Every OTHER visible event that shares a link_id token with this one
    # (deduped, in card order) — the data the "Related events" detail section
    # renders as buttons.
    def related_events(event, self_n)
      ids = event["link_ids"]
      return [] if ids.nil? || ids.empty?

      found = {}
      ids.each { |tok| link_index[tok].each { |n, e| found[n] ||= e unless n == self_n } }
      found.sort.map { |n, e| [n, e] }
    end

    # ---- summary (card face) --------------------------------------------------

    def summary_html(event)
      return tool_call_summary_html(event) if event["kind"] == "tool_call"

      h(event["summary"])
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
               else []
               end
      badges << %(<span class="badge queue">Dequeued</span>) if event["dequeued"]
      badges << %(<span class="badge queue">Removed from queue</span>) if event["removed_from_queue"]
      return "" if badges.empty?

      %(<div class="badges">#{badges.join}</div>)
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

    def detail_html(event, n)
      sections = kind_sections(event)
      sections << related_events_section(event, n)
      sections << section("Provenance", provenance_dl(event))
      # The copyable event id goes last and understated — it's a debugging aid.
      sections << event_id_footer(event) if event["ref"]
      sections.join("\n")
    end

    # Buttons for every other event in this one's causal chain (item: "show
    # linked events on the details tab"). Plain <a href="#event-N"> anchors —
    # clicking one changes location.hash, and assets/story.js's hashchange
    # listener (already wired for deep links) picks it up and selects that
    # card; no new JS needed.
    def related_events_section(event, n)
      related = related_events(event, n)
      return "" if related.empty?

      links = related.map { |m, e| related_link_html(m, e) }.join
      section("Related events", %(<div class="related-links">#{links}</div>))
    end

    def related_link_html(n, event)
      kind = h(KIND_LABEL.fetch(event["kind"], event["kind"]))
      summary = event["kind"] == "tool_call" ? tool_call_summary_html(event) : h(event["summary"])
      %(<a class="related-link" href="#event-#{n}">) +
        %(<span class="kind-tag">#{kind}</span><span class="summary">#{summary}</span></a>)
    end

    def kind_sections(event)
      case event["kind"]
      when "tool_call"   then tool_call_sections(event)
      when "tool_result" then tool_result_sections(event)
      else generic_sections(event)
      end
    end

    def generic_sections(event)
      sections = [text_section(event)]
      if (raw = event.dig("detail", "raw"))
        sections << section("Raw record", %(<pre class="code">#{h JSON.pretty_generate(raw)}</pre>))
      end
      sections
    end

    # Conversational kinds (user/assistant messages, reasoning, a delivered
    # task notification) render their text as markdown (item 1); everything
    # else (tool dumps, XML/system blobs) stays literal preformatted text so
    # code and structured output aren't reinterpreted as prose.
    def text_section(event)
      heading = DETAIL_HEADING[event["kind"]]
      text = event.dig("detail", "text") || event["summary"]
      if MARKDOWN_KINDS.include?(event["kind"])
        section(heading, %(<div class="d-markdown">#{Markdown.to_html(text)}</div>))
      else
        section(heading, %(<div class="d-text">#{h text}</div>))
      end
    end

    def tool_call_sections(event)
      tool = event["tool"] || {}
      sections = [section("Tool call — #{tool["name"]}", "")]
      sections << section("Fields", tool_call_fields_dl(tool))
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
      %(<pre class="code">#{h body}</pre>)
    end

    def tool_result_sections(event)
      tool = event["tool"] || {}
      heading = tool["name"] ? "Tool result — #{tool["name"]}" : "Tool result"
      sections = [section(heading, "")]
      sections << section("Fields", tool_result_fields_dl(tool))
      text = event.dig("detail", "text")
      sections << section("Result", %(<div class="d-text">#{h text}</div>)) if text && !text.empty?
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

    def render(template, **locals)
      template.result_with_hash(locals)
    end

    def page_template
      @page_template ||= ERB.new(File.read(File.join(TEMPLATES, "page.html.erb")), trim_mode: "-")
    end

    def card_template
      @card_template ||= ERB.new(File.read(File.join(TEMPLATES, "card.html.erb")), trim_mode: "-")
    end
  end
end
