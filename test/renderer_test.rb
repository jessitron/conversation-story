# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "conversation_story/renderer"
require_relative "story_events"

# Whole-page properties of the rendered output, checked against every built
# story. These are the cheap invariants that catch a template mistake before it
# reaches a page Jess is presenting from.
class RendererTest < Minitest::Test
  include StoryEvents

  STORIES = Dir.glob(File.expand_path("../out/*/story.yaml", __dir__)).sort

  def self.each_story
    STORIES.each { |path| yield File.basename(File.dirname(path)), path }
  end

  each_story do |name, path|
    # An ERB delimiter in the output means a template tag didn't close where its
    # author thought it did. That shipped once: a card comment mentioned the
    # closing delimiter inside backticks, which ENDED THE COMMENT, and the rest
    # of the sentence rendered as literal text above every card on the page.
    define_method("test_#{name}_leaks_no_erb_delimiters") do
      html = ConversationStory::Renderer.new(YAML.safe_load_file(path)).to_html

      %w[<%# <%= %> -%>].each do |delimiter|
        refute_includes html, delimiter,
                        "#{name}: ERB delimiter #{delimiter} reached the page — a template tag " \
                        "closed early, or a comment mentions a delimiter in its own text"
      end
    end

    # Cards carry their event ref as the HTML id; the page is useless for deep
    # linking if two share one, and story.js resolves ids with getElementById.
    define_method("test_#{name}_card_ids_are_unique") do
      html = ConversationStory::Renderer.new(YAML.safe_load_file(path)).to_html
      ids = html.scan(/<a class="card [^"]*" id="([^"]*)"/).flatten

      refute_empty ids, "#{name}: rendered no cards at all"
      assert_equal ids.uniq.size, ids.size, "#{name}: duplicate card ids"
    end

    # Every API response's numbers appear on exactly one card. If this drifts
    # above the turn count, the same usage is being printed on the thinking,
    # message and tool-call cards of one turn — which also means a running
    # total is counting it more than once.
    define_method("test_#{name}_prints_tokens_once_per_turn") do
      doc = YAML.safe_load_file(path)
      html = ConversationStory::Renderer.new(doc).to_html

      # Over the cards the page actually draws, subagents' nested turns included
      # — each of those is a real API response with its own numbers to print.
      turns = visible_cards(doc).filter_map { |e| e.dig("links", "message_id") }.uniq.size
      printed = html.scan(%r{<h4 class="deco">Tokens</h4>}).size

      assert_operator turns, :>, 0, "#{name}: no assistant turns found"
      assert_equal turns, printed,
                   "#{name}: expected one Tokens section per turn (#{turns}), got #{printed}"
    end

    # A tool result's token cost is estimated, not reported. The page must say
    # so wherever it shows one — an unlabelled ≈ reads as a measurement.
    define_method("test_#{name}_labels_every_token_estimate_as_estimated") do
      doc = YAML.safe_load_file(path)
      html = ConversationStory::Renderer.new(doc).to_html

      estimates = visible_cards(doc).count { |e| e.dig("tokens", "estimated_input") }
      notes = html.scan(%r{<p class="d-note">Estimated from}).size

      assert_operator estimates, :>, 0, "#{name}: no tool-result estimates found"
      assert_equal estimates, notes,
                   "#{name}: every estimate needs its caveat (#{estimates} estimates, #{notes} notes)"
    end

    # The header stat comes from meta, so it can't drift from the per-turn
    # numbers the way a separately-computed one could. It is whole-conversation
    # token USE, so it runs to millions — hence the M suffix.
    define_method("test_#{name}_header_shows_total_token_use") do
      doc = YAML.safe_load_file(path)
      html = ConversationStory::Renderer.new(doc).to_html
      total = doc["meta"]["total_tokens"]
      expected = total < 1_000_000 ? format("%.1fk", total / 1000.0) : format("%.2fM", total / 1_000_000.0)

      assert_includes html, %(<span class="k">Tokens</span><span class="v">#{expected}</span>),
                      "#{name}: header TOKENS stat missing or not derived from meta.total_tokens"
    end
  end

  # The card carries the beat as an attribute so story.js can read it straight
  # off the DOM (isBeat) instead of re-deriving it from kind and nesting.
  def test_a_beat_card_carries_data_beat_and_others_do_not
    doc = {
      "meta" => { "name" => "demo" },
      "events" => [
        { "ref" => "demo:1", "kind" => "user_message", "summary" => "hi", "beat" => true },
        { "ref" => "demo:2", "kind" => "tool_call", "summary" => "Bash",
          "tool" => { "name" => "Bash", "primary_arg" => "ls" } },
      ],
    }
    html = ConversationStory::Renderer.new(doc).to_html

    assert_includes html, %(id="demo:1")
    assert_match(/id="demo:1"[^>]*data-beat="true"/, html)
    refute_match(/id="demo:2"[^>]*data-beat/, html)
  end
end
