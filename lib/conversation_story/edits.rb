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
  #     episode-8-after:42: Jess asks for the timeline back
  #     episode-8-after:97: The moment it clicks
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
      # Hand-written event summaries — Jess's words, not the parser's.
      # Keyed by event ref (<example>:<line>); bin/parse overlays these onto the
      # freshly parsed story.yaml. Edit here or on the page (rake serve).
    YAML

    attr_reader :path

    # @param name [String] story name, e.g. "episode-8-after"
    def self.for_story(name, dir: DEFAULT_DIR)
      new(File.join(dir, "#{name}.yaml"))
    end

    def initialize(path)
      @path = path
      @summaries = load_file
    end

    def empty?  = @summaries.empty?
    def refs    = @summaries.keys
    def [](ref) = @summaries[ref]

    # Blank text means "no override" — the same call both sets and clears, so
    # the page's Save and Revert are one code path.
    def set(ref, text)
      text = text.to_s.strip
      text.empty? ? @summaries.delete(ref) : @summaries[ref] = text
      self
    end

    # Overlay onto a freshly parsed document, in place.
    # @return [Array<String>] refs that matched no event (stale — the log moved).
    def apply(document)
      by_ref = events_by_ref(document["events"])
      @summaries.filter_map do |ref, text|
        event = by_ref[ref]
        next ref unless event

        event["summary"] = text
        event["summary_edited"] = true
        nil
      end
    end

    # Writing an empty set removes the file, so "reverted everything" leaves no
    # confusing husk behind in git.
    def save
      if @summaries.empty?
        File.delete(@path) if File.exist?(@path)
        return self
      end

      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, HEADER + YAML.dump(sorted).delete_prefix("---\n"))
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

    # Grouped by log, then by line number, so the file reads in story order
    # rather than edit order (and a subagent's edits stay together).
    def sorted
      @summaries.sort_by { |ref, _| [ref.to_s.sub(/:\d+\z/, ""), ref.to_s[/:(\d+)\z/, 1].to_i] }.to_h
    end

    def load_file
      return {} unless File.exist?(@path)

      loaded = YAML.safe_load_file(@path)
      return {} unless loaded.is_a?(Hash)

      loaded.transform_keys(&:to_s).transform_values(&:to_s)
    end
  end
end
