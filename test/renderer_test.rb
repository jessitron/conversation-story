# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "conversation_story/renderer"

# Whole-page properties of the rendered output, checked against every built
# story. These are the cheap invariants that catch a template mistake before it
# reaches a page Jess is presenting from.
class RendererTest < Minitest::Test
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
  end
end
