# frozen_string_literal: true

require "erb"
require "cgi"
require "json"
require "time"

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
      "user_message"     => "user",
      "assistant_message"=> "assistant",
      "thinking"         => "thinking",
      "tool_call"        => "tool_call",
      "tool_result"      => "tool_result",
      "subagent"         => "subagent",
      "system"           => "system",
      "attachment"       => "system",
      "file_snapshot"    => "system",
      "permission_mode"  => "system",
      "queue_operation"  => "system",
      "unknown"          => "unknown",
    ).freeze

    KIND_LABEL = {
      "user_message"      => "User",
      "assistant_message" => "Assistant",
      "thinking"          => "Thinking",
      "tool_call"         => "Tool Call",
      "tool_result"       => "Tool Result",
      "subagent"          => "Subagent",
      "system"            => "System",
      "attachment"        => "Attachment",
      "file_snapshot"     => "Snapshot",
      "permission_mode"   => "Permission",
      "queue_operation"   => "Queue",
      "unknown"           => "Unknown",
    }.freeze

    # the actor shown in the card gutter (by kind, not role: a tool_result is a
    # user-role record but comes from the system, not the human).
    WHO = Hash.new("system").merge(
      "user_message"      => "Jess",
      "assistant_message" => "Claude",
      "thinking"          => "Claude",
    ).freeze

    DETAIL_HEADING = Hash.new("Detail").merge(
      "user_message"      => "Message",
      "assistant_message" => "Message",
      "thinking"          => "Reasoning",
      "tool_result"       => "Tool result",
      "system"            => "System event",
    ).freeze

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
             summary_html: h(event["summary"]),
             detail_html:  detail_html(event))
    end

    # ---- detail (drill-in) markup -------------------------------------------

    def detail_html(event)
      sections = []
      heading = DETAIL_HEADING[event["kind"]]
      text = event.dig("detail", "text") || event["summary"]
      sections << section(heading, %(<div class="d-text">#{h text}</div>))

      if (raw = event.dig("detail", "raw"))
        sections << section("Raw record",
                            %(<pre class="code">#{h JSON.pretty_generate(raw)}</pre>))
      end

      sections << section("Provenance", provenance_dl(event))
      # The copyable event id goes last and understated — it's a debugging aid.
      sections << event_id_footer(event) if event["ref"]
      sections.join("\n")
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
      <<~HTML.strip
        <dl class="kv">
          <dt>source.file</dt><dd><code>#{h src["file"]}</code></dd>
          <dt>source.line</dt><dd><code>#{h src["line"]}</code></dd>
          <dt>agent</dt><dd><code>#{h event["agent"]}</code></dd>
        </dl>
      HTML
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
