# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require "fileutils"
require "conversation_story/session_scan"
require "conversation_story/parser"

# Golden-fixture tests for the session scanner: run it against every real
# example log and assert the numbers a listing card would show, the same
# treatment the parser gets in parser_test.rb.
#
# What's asserted is the scan's OUTPUT — the contract. Its streaming shape isn't
# (beyond the two performance rules, which are design constraints, not
# assertions); the cache tests below do pin down "a hit doesn't reopen the log",
# because that's observable behaviour Jess depends on.
class SessionScanTest < Minitest::Test
  EXAMPLES = Dir.glob(File.expand_path("../examples/*.jsonl", __dir__)).sort

  def test_examples_exist
    refute_empty EXAMPLES, "no example logs found under examples/*.jsonl"
  end

  # Independently recomputed facts, the slow and obvious way, so the assertions
  # below don't just restate the scanner's own logic.
  def self.by_hand(log)
    facts = { ids: {}, assistant_records: 0, max_context: 0, session_id: nil,
              titles: [], recaps: [] }
    File.foreach(log) do |line|
      rec = JSON.parse(line) rescue next
      facts[:session_id] ||= rec["sessionId"]
      case rec["type"]
      when "assistant"
        facts[:assistant_records] += 1
        facts[:ids][rec.dig("message", "id")] = true if rec.dig("message", "id")
        u = rec.dig("message", "usage") || {}
        ctx = u["input_tokens"].to_i + u["cache_creation_input_tokens"].to_i +
              u["cache_read_input_tokens"].to_i
        facts[:max_context] = ctx if ctx > facts[:max_context]
      when "ai-title" then facts[:titles] << rec["aiTitle"]
      when "system" then facts[:recaps] << rec["content"] if rec["subtype"] == "away_summary"
      end
    end
    facts
  end

  EXAMPLES.each do |log|
    name = File.basename(log, ".jsonl")
    hand = by_hand(log)

    define_method("test_#{name}_identifies_the_session") do
      scan = ConversationStory::SessionScan.scan(log)

      assert_equal hand[:session_id], scan["session_id"]
      assert_equal File.expand_path(log), scan["path"]
      assert_equal File.size(log), scan["size"]
      assert_in_delta File.mtime(log).to_f, scan["mtime"], 0.001
      refute_empty scan["project"].to_s, "every session should land in some project"
    end

    define_method("test_#{name}_counts_turns_not_assistant_records") do
      scan = ConversationStory::SessionScan.scan(log)

      assert_equal hand[:ids].size, scan["turns"]
      # The whole reason turns are counted by distinct message.id: one API
      # response is split across several records (thinking / text / one per
      # tool_use), each repeating the same id, so records inflate it ~3x.
      assert_operator scan["turns"], :<, hand[:assistant_records],
                      "every fixture should show the inflation, or the two " \
                      "measures aren't distinguishable here"
    end

    define_method("test_#{name}_reports_the_true_max_context") do
      scan = ConversationStory::SessionScan.scan(log)

      assert_equal hand[:max_context], scan["max_context"]
    end

    define_method("test_#{name}_counts_subagent_logs_not_sidecar_files") do
      scan = ConversationStory::SessionScan.scan(log)
      dir = File.join(File.dirname(log), name, "subagents")

      assert_equal Dir.glob(File.join(dir, "*.jsonl")).size, scan["subagents"]
    end

    define_method("test_#{name}_takes_the_last_title") do
      scan = ConversationStory::SessionScan.scan(log)

      # The harness regenerates the title as the session runs, so the last is
      # the best informed one.
      expected = hand[:titles].compact.last
      if expected.nil?
        assert_nil scan["title"]
      else
        assert_equal expected, scan["title"]
      end
    end

    define_method("test_#{name}_recap_is_prose_with_no_harness_tail") do
      scan = ConversationStory::SessionScan.scan(log)

      if hand[:recaps].empty?
        assert_nil scan["recap"], "no away_summary record, so no recap"
      else
        refute_nil scan["recap"]
        refute_includes scan["recap"],
                        ConversationStory::SessionScan::RECAP_TAIL,
                        "the harness tail should be stripped"
      end
    end

    define_method("test_#{name}_first_prompt_is_something_jess_typed") do
      scan = ConversationStory::SessionScan.scan(log)

      refute_nil scan["first_prompt"], "every fixture starts with a human prompt"
      refute scan["first_prompt"].start_with?("<"),
             "a `<`-leading string is a harness blob, not a prompt"
      refute_empty scan["first_prompt"].strip
    end
  end

  # --- the specific cases the ticket calls out -----------------------------

  def test_a_session_with_no_recap_scans_fine
    log = example("episode-8-after")
    scan = ConversationStory::SessionScan.scan(log)

    assert_nil scan["recap"], "episode-8-after has no away_summary record"
    assert_nil scan["title"], "and no ai-title record either"
    assert_operator scan["turns"], :>, 0, "the rest of the scan still works"
  end

  def test_the_recap_tail_is_present_in_the_log_and_gone_from_the_scan
    log = example("4b0be952-d0bd-49ed-b97a-357b9149bf31")
    tail = ConversationStory::SessionScan::RECAP_TAIL

    assert_includes File.read(log), tail, "fixture no longer carries the tail"
    refute_includes ConversationStory::SessionScan.scan(log)["recap"], tail
  end

  # Each subagent leaves TWO sidecar files, a .jsonl and a .meta.json, so
  # counting files instead of logs would double the number on this fixture.
  def test_subagents_counts_logs_not_sidecar_files
    log = example("episode-8-before")
    dir = File.expand_path("../examples/episode-8-before/subagents", __dir__)

    assert_equal 2, Dir.glob(File.join(dir, "*")).size
    assert_equal 1, ConversationStory::SessionScan.scan(log)["subagents"]
  end

  # The scanner and the parser disagree about nothing they share. Parser elects
  # one `turn_leader` per turn from the same message.id grouping; CLAUDE.md
  # records 33 turns for this log.
  def test_turns_agree_with_the_parsers_turn_leaders
    log = example("episode-8-before")
    doc = ConversationStory::Parser.new(log).to_document
    leaders = doc["events"].count { |e| e["turn_leader"] }

    assert_equal 33, leaders
    assert_equal leaders, ConversationStory::SessionScan.scan(log)["turns"]
  end

  # --- the cache ----------------------------------------------------------

  def test_cache_misses_then_hits
    in_temp_cache do |cache, log|
      first = ConversationStory::SessionScan.fetch(log, cache: cache)

      assert_equal 1, cache.misses
      assert_equal 0, cache.hits

      second = ConversationStory::SessionScan.fetch(log, cache: cache)

      assert_equal 1, cache.hits
      assert_equal first, second, "a hit returns the same hash a miss produced"
    end
  end

  def test_each_result_is_written_as_it_completes
    in_temp_cache do |cache, log|
      assert_empty Dir.glob(File.join(cache.dir, "*.json"))

      ConversationStory::SessionScan.fetch(log, cache: cache)

      # On disk already, not batched for the end of a run: a crash partway
      # through a cold scan of 416 logs must keep what's done.
      assert_equal 1, Dir.glob(File.join(cache.dir, "*.json")).size
    end
  end

  # The load-bearing claim is "an unchanged log is never reopened". Proven by
  # changing the log's CONTENT while keeping its size and mtime: a scanner that
  # reopened the file would see the new title.
  def test_a_hit_does_not_reopen_the_log
    in_temp_cache do |cache, log|
      before = ConversationStory::SessionScan.fetch(log, cache: cache)
      rewrite_title(log, "CHANGE")

      assert_equal before["title"], ConversationStory::SessionScan.fetch(log, cache: cache)["title"]
      assert_equal 1, cache.hits
      assert_equal "CHANGE", ConversationStory::SessionScan.scan(log)["title"],
                   "sanity: the file really did change"
    end
  end

  def test_an_appended_log_misses
    in_temp_cache do |cache, log|
      ConversationStory::SessionScan.fetch(log, cache: cache)
      File.open(log, "a") { |f| f.puts(JSON.generate("type" => "ai-title", "aiTitle" => "later")) }

      scan = ConversationStory::SessionScan.fetch(log, cache: cache)

      assert_equal 2, cache.misses
      assert_equal "later", scan["title"]
      assert_equal File.size(log), scan["size"]
    end
  end

  def test_a_touched_log_misses
    in_temp_cache do |cache, log|
      ConversationStory::SessionScan.fetch(log, cache: cache)
      future = Time.now + 60
      File.utime(future, future, log)

      ConversationStory::SessionScan.fetch(log, cache: cache)

      assert_equal 2, cache.misses, "a new mtime alone invalidates the entry"
    end
  end

  def test_a_corrupt_cache_file_reads_as_a_miss
    in_temp_cache do |cache, log|
      ConversationStory::SessionScan.fetch(log, cache: cache)
      Dir.glob(File.join(cache.dir, "*.json")).each { |f| File.write(f, "{not json") }

      assert ConversationStory::SessionScan.fetch(log, cache: cache)["session_id"]
      assert_equal 2, cache.misses
    end
  end

  # A session that never got a reply out of the model has no `user` and no
  # `assistant` record — only bookkeeping — and 4 of the 50 most recent logs on
  # this machine are exactly that. `cwd` still rides on several of those record
  # types, so the project group is still the real one and not the lossy
  # directory-name fallback. (Found while building the importer's listing page:
  # one project showed up TWICE, once as `code/jessitron/x` and once as
  # `code-jessitron-x`.)
  def test_cwd_is_read_from_bookkeeping_records_too
    Dir.mktmpdir("session-scan-cwd") do |dir|
      log = File.join(dir, "stub.jsonl")
      File.write(log, [
        JSON.generate("type" => "mode", "sessionId" => "s-2"),
        JSON.generate("type" => "system", "subtype" => "hook", "cwd" => "#{Dir.home}/code/thing"),
      ].join("\n") + "\n")

      assert_equal "code/thing", ConversationStory::SessionScan.scan(log)["project"]
    end
  end

  # With nothing carrying a `cwd` anywhere, the label falls back to decoding the
  # project directory's name — best-effort, and visibly dashed.
  def test_project_falls_back_to_the_directory_name
    Dir.mktmpdir("session-scan-nocwd") do |dir|
      project_dir = File.join(dir, "#{Dir.home.tr("/", "-")}-code-thing")
      FileUtils.mkdir_p(project_dir)
      log = File.join(project_dir, "stub.jsonl")
      File.write(log, JSON.generate("type" => "ai-title", "aiTitle" => "Stub") + "\n")

      assert_equal "code-thing", ConversationStory::SessionScan.scan(log)["project"]
    end
  end

  # The cache key is path + mtime + size — none of which change when the SCANNER
  # changes. So the stored SHAPE is versioned too, and a bumped version reads as
  # a miss. (Ticket 03 hit this: a new field on the scan left every cached entry
  # without it and the listing page kept drawing the old shape.)
  def test_a_stale_scan_version_is_a_miss
    in_temp_cache do |cache, log|
      ConversationStory::SessionScan.fetch(log, cache: cache)
      assert_equal 1, cache.misses

      Dir.glob(File.join(cache.dir, "*.json")).each do |file|
        entry = JSON.parse(File.read(file))
        entry["version"] = ConversationStory::SessionScan::SCAN_VERSION - 1
        File.write(file, JSON.generate(entry))
      end

      ConversationStory::SessionScan.fetch(log, cache: cache)
      assert_equal 2, cache.misses
      assert_equal 0, cache.hits
    end
  end

  private

  def example(name) = File.expand_path("../examples/#{name}.jsonl", __dir__)

  # A tiny synthetic log in a temp dir, so cache tests can mutate it freely
  # without touching the golden fixtures.
  def in_temp_cache
    Dir.mktmpdir("session-scan") do |dir|
      log = File.join(dir, "s.jsonl")
      File.write(log, [
        JSON.generate("type" => "mode", "sessionId" => "s-1"),
        JSON.generate("type" => "user", "cwd" => dir,
                      "message" => { "role" => "user", "content" => "hello there" }),
        JSON.generate("type" => "assistant", "message" => {
                        "id" => "msg_1", "role" => "assistant",
                        "usage" => { "input_tokens" => 1, "cache_creation_input_tokens" => 2,
                                     "cache_read_input_tokens" => 3 }
                      }),
        JSON.generate("type" => "ai-title", "aiTitle" => "BEFORE"),
      ].join("\n") + "\n")

      yield ConversationStory::SessionScan::Cache.new(File.join(dir, "cache")), log
    end
  end

  # Same byte length ("BEFORE" and "CHANGE" are both 6 chars), different
  # content — the only way to prove the file wasn't reopened, since
  # path + mtime + size is the whole cache key.
  def rewrite_title(log, title)
    body = File.read(log).sub('"BEFORE"', JSON.generate(title))
    mtime = File.mtime(log)
    File.write(log, body)
    File.utime(mtime, mtime, log)
  end
end
