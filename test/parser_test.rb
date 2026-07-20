# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "conversation_story/parser"
require "conversation_story/renderer"

# Golden-fixture tests: run the parser against every real example log and assert
# the Mountain 1 contract holds — no data lost, required fields present, YAML
# round-trips, and the renderer emits exactly one card per event.
class ParserTest < Minitest::Test
  EXAMPLES = Dir.glob(File.expand_path("../examples/*.jsonl", __dir__)).sort

  # `last-prompt` is the one record type we knowingly route to the `unknown`
  # fallback for now (it proves the fallback path renders real data). Any OTHER
  # type showing up as unknown is a regression the test should catch.
  EXPECTED_UNKNOWN_TYPES = ["last-prompt"].freeze

  def test_examples_exist
    refute_empty EXAMPLES, "no example logs found under examples/*.jsonl"
  end

  EXAMPLES.each do |log|
    name = File.basename(log, ".jsonl")

    define_method("test_#{name}_one_event_per_line") do
      doc = ConversationStory::Parser.new(log).to_document
      line_count = File.readlines(log).count { |l| !l.strip.empty? }

      assert_equal line_count, doc["events"].size,
                   "expected one event per non-blank line"
      assert_equal line_count, doc["meta"]["event_count"],
                   "meta.event_count should match"
    end

    define_method("test_#{name}_every_event_has_provenance_and_agent") do
      doc = ConversationStory::Parser.new(log).to_document
      doc["events"].each do |e|
        refute_nil e["agent"], "event #{e["id"]} missing agent"
        assert e.dig("source", "file"), "event #{e["id"]} missing source.file"
        assert_kind_of Integer, e.dig("source", "line"),
                       "event #{e["id"]} missing integer source.line"
        assert_operator e.dig("source", "line"), :>, 0
      end
    end

    define_method("test_#{name}_every_event_has_a_ref_handle") do
      doc = ConversationStory::Parser.new(log).to_document
      doc["events"].each do |e|
        assert_equal "#{name}:#{e.dig("source", "line")}", e["ref"],
                     "event #{e["id"]} ref should be <name>:<line>"
      end
      # refs are unique (one event per line), so they're safe to cite
      refs = doc["events"].map { |e| e["ref"] }
      assert_equal refs.uniq.size, refs.size, "event refs must be unique"
    end

    define_method("test_#{name}_renders_copyable_event_id") do
      doc  = ConversationStory::Parser.new(log).to_document
      html = ConversationStory::Renderer.new(doc).to_html
      assert_equal doc["events"].size, html.scan(/class="copy-ref"/).size,
                   "expected one copy-ref chip per event"
      assert_includes html, %(data-copy="#{name}:1")
    end

    define_method("test_#{name}_assistant_turns_carry_named_tokens") do
      doc = ConversationStory::Parser.new(log).to_document
      assistants = doc["events"].select { |e| e["kind"] == "assistant_message" }
      refute_empty assistants, "expected some assistant_message events"
      assistants.each do |e|
        assert e["tokens"], "assistant event #{e["id"]} missing tokens"
        assert_kind_of Integer, e.dig("tokens", "input")
        assert_kind_of Integer, e.dig("tokens", "output")
      end
    end

    define_method("test_#{name}_only_expected_unknowns") do
      doc = ConversationStory::Parser.new(log).to_document
      unknown_types = doc["events"]
                      .select { |e| e["kind"] == "unknown" }
                      .map { |e| e.dig("detail", "raw", "type") }
                      .uniq.sort
      assert_equal EXPECTED_UNKNOWN_TYPES.sort, unknown_types,
                   "unexpected record types fell back to `unknown`"
    end

    define_method("test_#{name}_meta_is_populated") do
      meta = ConversationStory::Parser.new(log).to_document["meta"]
      %w[source name session_id git_branch started_at ended_at].each do |k|
        refute_nil meta[k], "meta.#{k} should be present"
      end
      assert_equal "UTC", meta["timezone"]
      assert_equal "main", meta["agents"].first["id"]
    end

    define_method("test_#{name}_yaml_round_trips_safely") do
      doc = ConversationStory::Parser.new(log).to_document
      reloaded = YAML.safe_load(YAML.dump(doc))
      assert_equal doc, reloaded, "story.yaml must round-trip under safe_load"
    end

    define_method("test_#{name}_renders_one_card_per_event") do
      doc  = ConversationStory::Parser.new(log).to_document
      html = ConversationStory::Renderer.new(doc).to_html

      assert_equal doc["events"].size, html.scan(/class="card /).size,
                   "expected one card per event"
      assert_includes html, "event-#{doc["events"].size}",
                       "expected sequential event anchors"
      # the JS defaults selection to a .k-assistant card; make sure one exists
      assert_includes html, "card k-assistant"
    end
  end
end
