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
      assert_match(/^# Hand-written event summaries/, File.read(path))
      assert_equal %w[demo:3 demo:20], YAML.safe_load_file(path).keys, "sorted by line number"
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
end
