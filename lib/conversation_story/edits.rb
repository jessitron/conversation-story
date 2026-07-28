# frozen_string_literal: true

require "yaml"
require "fileutils"

module ConversationStory
  # Hand-written summaries, kept OUTSIDE the generated story.
  #
  # Mount Malleable: Jess can rewrite a card's one-line summary on the page, so
  # the timeline reads the way she'd narrate it rather than the way the parser
  # guessed. The edit has to survive `rake parse` re-running — but `out/` is
  # purely derived, and we want to keep it that way (a parser improvement should
  # still reach every card Jess hasn't touched).
  #
  # So an edit lives in a sidecar file, `edits/<story-name>.yaml`, a plain map of
  # event ref -> summary:
  #
  #     summaries:
  #       episode-8-after:42: Jess asks for the timeline back
  #     beats:
  #       episode-8-after:97: false
  #
  # Two kinds of hand edit, two named sections. `beats` overrides where
  # narration stops (n / p / shift+arrow): false exempts a message the parser
  # defaulted to a beat, true adds a stop the parser wouldn't guess — a tool
  # call, or an event inside a subagent. There is no `beat_edited` stamp:
  # unlike a summary it has no composed card face to beat and nothing to mark.
  #
  # `bin/parse` builds the document from the log as always and then calls
  # #apply, which overwrites those events' `summary` and stamps
  # `summary_edited: true` so the renderer knows the text is Jess's, not the
  # parser's. story.yaml stays 100% generated — from the log AND this file.
  #
  # Keyed by `ref` (`<example>:<line>`) because that's the coordinate Jess
  # already speaks in and the card's own HTML id. It's tied to a line number, so
  # editing the log invalidates the edit — #apply returns the refs that matched
  # nothing so the caller can say so out loud instead of silently dropping them.
  class Edits
    DEFAULT_DIR = File.expand_path("../../edits", __dir__)

    HEADER = <<~YAML
      # Hand edits — Jess's, not the parser's. Keyed by event ref (<example>:<line>).
      # bin/parse overlays these onto the freshly parsed story.yaml.
      #   summaries: the one-line card face, rewritten
      #   beats:     where narration stops (n / p / shift+arrow); true or false
      # Edit here or on the page (rake serve).
    YAML

    attr_reader :path

    # @param name [String] story name, e.g. "episode-8-after"
    def self.for_story(name, dir: DEFAULT_DIR)
      new(File.join(dir, "#{name}.yaml"))
    end

    def initialize(path)
      @path = path
      loaded = load_file
      @summaries = loaded["summaries"]
      @beats     = loaded["beats"]
    end

    def empty?  = @summaries.empty? && @beats.empty?
    def refs    = (@summaries.keys + @beats.keys).uniq
    def [](ref) = @summaries[ref]

    # nil means "no override" — the parser's default stands.
    def beat(ref) = @beats[ref]

    # Blank text means "no override" — the same call both sets and clears, so
    # the page's Save and Revert are one code path.
    def set(ref, text)
      text = text.to_s.strip
      text.empty? ? @summaries.delete(ref) : @summaries[ref] = text
      self
    end

    # nil clears the override; anything else is coerced to a real boolean, so a
    # JSON "false" string can't sneak in as truthy.
    def set_beat(ref, value)
      value.nil? ? @beats.delete(ref) : @beats[ref] = !!value
      self
    end

    # Overlay onto a freshly parsed document, in place.
    # @return [Array<String>] refs that matched no event (stale — the log moved).
    def apply(document)
      by_ref = events_by_ref(document["events"])
      stale = []

      @summaries.each do |ref, text|
        event = by_ref[ref]
        next stale << ref unless event

        event["summary"] = text
        event["summary_edited"] = true
      end

      @beats.each do |ref, on|
        event = by_ref[ref]
        next stale << ref unless event

        # `false` DELETES the key rather than storing false: "not a beat" is the
        # absent-key shape the parser emits, and story.js reads
        # dataset.beat === 'true'. One shape, one truth.
        on ? event["beat"] = true : event.delete("beat")
      end

      stale.uniq
    end

    # Writing an empty set removes the file, so "reverted everything" leaves no
    # confusing husk behind in git. An empty section is omitted for the same
    # reason.
    def save
      if empty?
        File.delete(@path) if File.exist?(@path)
        return self
      end

      sections = {}
      sections["summaries"] = sorted(@summaries) unless @summaries.empty?
      sections["beats"]     = sorted(@beats)     unless @beats.empty?

      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, HEADER + YAML.dump(sections).delete_prefix("---\n"))
      self
    end

    private

    # Every event that can carry a hand-written summary, keyed by ref — the
    # subagents' nested stories included, since their events get cards on the
    # page too and the editor is offered on any card Jess selects. Their refs are
    # namespaced by their own log's name (`agent-ae2065…:3`), so they can't
    # collide with the main log's.
    def events_by_ref(events, into = {})
      Array(events).each do |event|
        into[event["ref"]] = event
        events_by_ref(event.dig("subagent", "events"), into)
      end
      into
    end

    # Grouped by log, then by line number, so a section reads in story order
    # rather than edit order (and a subagent's edits stay together).
    def sorted(map)
      map.sort_by { |ref, _| [ref.to_s.sub(/:\d+\z/, ""), ref.to_s[/:(\d+)\z/, 1].to_i] }.to_h
    end

    # Two sections, both optional. Only this shape is read: the sidecars live in
    # this repo and nothing else has ever consumed one, so a flat-file
    # compatibility branch would be dead code the day it shipped.
    def load_file
      empty = { "summaries" => {}, "beats" => {} }
      return empty unless File.exist?(@path)

      loaded = YAML.safe_load_file(@path)
      return empty unless loaded.is_a?(Hash)

      {
        "summaries" => string_map(loaded["summaries"]) { |v| v.to_s },
        "beats"     => string_map(loaded["beats"])     { |v| !!v },
      }
    end

    def string_map(raw, &coerce)
      return {} unless raw.is_a?(Hash)

      raw.transform_keys(&:to_s).transform_values(&coerce)
    end
  end
end
