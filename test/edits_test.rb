# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"
require "conversation_story/edits"
require "conversation_story/renderer"

# ConversationStory::Edits is the sidecar of hand-written summaries (Mount
# Malleable). The property that matters: out/ stays fully derived — the log is
# always re-parsed from scratch and these are overlaid on top — so these tests
# pin down the overlay, the round-trip through the file, and the one renderer
# rule that follows (a hand-written line beats every generated card face).
class EditsTest < Minitest::Test
  Edits = ConversationStory::Edits

  def document
    {
      "meta" => { "name" => "demo" },
      "events" => [
        { "ref" => "demo:1", "kind" => "user_message", "summary" => "generated one" },
        { "ref" => "demo:2", "kind" => "tool_call", "summary" => "Bash", "at" => nil,
          "tool" => { "name" => "Bash", "primary_arg" => "ls" } },
        { "ref" => "demo:3", "kind" => "subagent", "summary" => "go look",
          "tool" => { "name" => "Agent", "use_id" => "toolu_1" },
          "subagent" => { "agent_id" => "agent-abc", "agent_type" => "Explore",
                          "events" => [{ "ref" => "agent-abc:2", "kind" => "assistant_message",
                                         "summary" => "generated, nested" }] } },
      ],
    }
  end

  def in_tmp_dir
    Dir.mktmpdir { |dir| yield dir }
  end

  def test_apply_overwrites_summary_and_marks_it_edited
    in_tmp_dir do |dir|
      edits = Edits.for_story("demo", dir: dir).set("demo:1", "Jess asks for the timeline back")
      stale = edits.apply(doc = document)

      assert_empty stale
      assert_equal "Jess asks for the timeline back", doc["events"][0]["summary"]
      assert doc["events"][0]["summary_edited"]
      # untouched events stay exactly as the parser made them
      assert_equal "Bash", doc["events"][1]["summary"]
      refute doc["events"][1]["summary_edited"]
    end
  end

  # A subagent's own events get cards on the page, so the editor is offered on
  # them — which means a ref inside a nested story has to resolve, or a save
  # would come back "matches no event" from a card Jess is looking at.
  def test_apply_reaches_events_inside_a_nested_subagent_story
    in_tmp_dir do |dir|
      edits = Edits.for_story("demo", dir: dir).set("agent-abc:2", "the subagent gets its bearings")
      stale = edits.apply(doc = document)

      assert_empty stale
      nested = doc["events"][2]["subagent"]["events"][0]
      assert_equal "the subagent gets its bearings", nested["summary"]
      assert nested["summary_edited"]
    end
  end

  def test_apply_reports_refs_that_match_no_event
    in_tmp_dir do |dir|
      edits = Edits.for_story("demo", dir: dir).set("demo:999", "orphaned by a changed log")

      assert_equal ["demo:999"], edits.apply(document)
    end
  end

  def test_blank_text_clears_the_override
    in_tmp_dir do |dir|
      edits = Edits.for_story("demo", dir: dir).set("demo:1", "mine").set("demo:1", "  ")

      assert_empty edits.apply(doc = document)
      assert_equal "generated one", doc["events"][0]["summary"]
    end
  end

  def test_round_trips_through_the_file_sorted_by_line
    in_tmp_dir do |dir|
      Edits.for_story("demo", dir: dir).set("demo:20", "later").set("demo:3", "earlier").save

      path = File.join(dir, "demo.yaml")
      assert_match(/^# Hand edits/, File.read(path))
      assert_equal %w[demo:3 demo:20], YAML.safe_load_file(path)["summaries"].keys, "sorted by line number"
      assert_equal "later", Edits.for_story("demo", dir: dir)["demo:20"]
    end
  end

  def test_saving_an_empty_set_removes_the_file
    in_tmp_dir do |dir|
      path = File.join(dir, "demo.yaml")
      Edits.for_story("demo", dir: dir).set("demo:1", "mine").save
      assert_path_exists path

      Edits.for_story("demo", dir: dir).set("demo:1", "").save
      refute File.exist?(path), "an emptied edits file should not linger"
    end
  end

  # A tool_call's card face is composed by the renderer (bold name + <code>
  # argument), ignoring `summary`. A hand-written line has to win anyway.
  def test_renderer_prefers_a_hand_written_summary_over_the_tool_call_face
    in_tmp_dir do |dir|
      Edits.for_story("demo", dir: dir).set("demo:2", "Claude peeks at the directory").apply(doc = document)
      html = ConversationStory::Renderer.new(doc).to_html

      assert_includes html, "Claude peeks at the directory"
      assert_includes html, %(data-edited="true")
      refute_includes html, "<b>Bash</b>"
    end
  end

  def test_apply_turns_a_beat_off_by_removing_the_key
    in_tmp_dir do |dir|
      doc = document
      doc["events"][0]["beat"] = true          # the parser's default
      edits = Edits.for_story("demo", dir: dir).set_beat("demo:1", false)

      assert_empty edits.apply(doc)
      refute doc["events"][0].key?("beat"),
             "beat off means the key is gone, same shape the parser emits"
    end
  end

  def test_apply_turns_a_beat_on_for_a_card_the_parser_would_not_stop_at
    in_tmp_dir do |dir|
      doc = document
      edits = Edits.for_story("demo", dir: dir).set_beat("demo:2", true)

      assert_empty edits.apply(doc)
      assert_equal true, doc["events"][1]["beat"]
    end
  end

  # Beats reach nested subagent events too, so Jess can stop on one deliberately.
  def test_apply_sets_a_beat_inside_a_nested_subagent_story
    in_tmp_dir do |dir|
      doc = document
      edits = Edits.for_story("demo", dir: dir).set_beat("agent-abc:2", true)

      assert_empty edits.apply(doc)
      assert_equal true, doc["events"][2]["subagent"]["events"][0]["beat"]
    end
  end

  def test_a_beat_override_for_a_ref_that_no_longer_exists_is_reported_stale
    in_tmp_dir do |dir|
      edits = Edits.for_story("demo", dir: dir).set_beat("demo:999", false)
      assert_equal ["demo:999"], edits.apply(document)
    end
  end

  def test_round_trip_keeps_summaries_and_beats_in_named_sections
    in_tmp_dir do |dir|
      Edits.for_story("demo", dir: dir)
           .set("demo:1", "Jess's line")
           .set_beat("demo:2", true)
           .set_beat("demo:1", false)
           .save

      raw = YAML.safe_load_file(File.join(dir, "demo.yaml"))
      assert_equal({ "demo:1" => "Jess's line" }, raw["summaries"])
      assert_equal({ "demo:1" => false, "demo:2" => true }, raw["beats"])

      reloaded = Edits.for_story("demo", dir: dir)
      assert_equal "Jess's line", reloaded["demo:1"]
      assert_equal false, reloaded.beat("demo:1")
      assert_equal true,  reloaded.beat("demo:2")
      assert_nil reloaded.beat("demo:3")
    end
  end

  # A hand-edited file has no HTTP-side validation to catch a typo, so the
  # loader itself has to be strict: neither the JSON-flavored string "false"
  # nor the YAML word `no` (which Psych reads as the STRING "no", not a
  # boolean) may coerce to a boolean at all — under `!!`, both are truthy,
  # which would silently turn an intended "off" ON.
  def test_a_non_boolean_beat_value_in_the_file_raises_naming_the_ref
    in_tmp_dir do |dir|
      path = File.join(dir, "demo.yaml")
      File.write(path, "beats:\n  demo:1: 'false'\n")

      error = assert_raises(ArgumentError) { Edits.for_story("demo", dir: dir) }
      assert_includes error.message, "demo:1"
    end
  end

  def test_set_beat_nil_clears_the_override_and_an_empty_file_is_removed
    in_tmp_dir do |dir|
      path = File.join(dir, "demo.yaml")
      Edits.for_story("demo", dir: dir).set_beat("demo:1", false).save
      assert File.exist?(path)

      Edits.for_story("demo", dir: dir).set_beat("demo:1", nil).save
      refute File.exist?(path), "no husk left behind when nothing is overridden"
    end
  end
end
