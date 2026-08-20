# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "conversation_story/import"

# The pieces of Import that tickets 04/05 added on top of the discovery/copy
# door ticket 01 built: a slug default for the name field, and recognizing a
# session already sitting in examples/ by reading the fixtures themselves
# (no manifest — see the module comment on Import.existing_examples).
class ImportTest < Minitest::Test
  Import = ConversationStory::Import

  def test_slugify_lowercases_and_dashes
    assert_equal "mode-switches", Import.slugify("Mode Switches")
    assert_equal "a-b-c", Import.slugify("A!! B__C")
  end

  def test_slugify_falls_back_to_session_for_nothing_sluggable
    assert_equal "session", Import.slugify("")
    assert_equal "session", Import.slugify(nil)
    assert_equal "session", Import.slugify("!!!")
  end

  def write_example(dir, name, session_id)
    File.write(File.join(dir, "#{name}.jsonl"),
               JSON.generate(sessionId: session_id, type: "user") + "\n")
  end

  def test_first_session_id_reads_the_first_line
    Dir.mktmpdir do |dir|
      write_example(dir, "mode-switches", "abc-123")
      assert_equal "abc-123", Import.first_session_id(File.join(dir, "mode-switches.jsonl"))
    end
  end

  def test_first_session_id_is_nil_for_a_missing_or_unparseable_file
    Dir.mktmpdir do |dir|
      assert_nil Import.first_session_id(File.join(dir, "nope.jsonl"))

      File.write(File.join(dir, "broken.jsonl"), "not json\n")
      assert_nil Import.first_session_id(File.join(dir, "broken.jsonl"))
    end
  end

  def test_existing_examples_maps_name_to_session_id
    Dir.mktmpdir do |dir|
      write_example(dir, "one", "id-1")
      write_example(dir, "two", "id-2")

      assert_equal({ "one" => "id-1", "two" => "id-2" }, Import.existing_examples(examples_dir: dir))
    end
  end

  def test_existing_name_for_finds_the_name_a_session_was_imported_under
    Dir.mktmpdir do |dir|
      write_example(dir, "mode-switches", "abc-123")

      assert_equal "mode-switches", Import.existing_name_for("abc-123", examples_dir: dir)
      assert_nil Import.existing_name_for("never-imported", examples_dir: dir)
    end
  end

  def test_copy_re_snapshot_merges_new_sidecars_without_losing_old_ones
    Dir.mktmpdir do |src_dir|
      Dir.mktmpdir do |examples_dir|
        session_id = "abc-123"
        log = File.join(src_dir, "#{session_id}.jsonl")
        File.write(log, JSON.generate(sessionId: session_id) + "\n")

        sidecars = File.join(src_dir, session_id, "subagents")
        FileUtils.mkdir_p(sidecars)
        File.write(File.join(sidecars, "agent-1.jsonl"), "{}\n")

        Import.copy(log, "story", examples_dir: examples_dir)
        assert_equal 1, Dir.glob(File.join(examples_dir, "story", "subagents", "*.jsonl")).size

        # A second subagent finished after the first snapshot.
        File.write(File.join(sidecars, "agent-2.jsonl"), "{}\n")
        Import.copy(log, "story", examples_dir: examples_dir)

        landed = Dir.glob(File.join(examples_dir, "story", "subagents", "*.jsonl")).map { |p| File.basename(p) }
        assert_equal %w[agent-1.jsonl agent-2.jsonl], landed.sort
      end
    end
  end
end
