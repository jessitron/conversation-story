# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "conversation_story/importer_page"

# The importer's listing page. Two things worth pinning down, and they're the two
# things the ticket's checkboxes are about:
#
#   ORDER — the 50 are taken globally by mtime and only THEN grouped, with
#           projects ordered by their newest session. Easy to get backwards, and
#           invisible until Jess's freshest work is buried.
#   MISSING FACTS — a session with no recap, no title or no plain-text prompt
#           still has to render as a card, because plenty of real sessions have
#           none of those.
#
# The page is built from scan hashes, so these are synthetic scans: what a card
# does with the facts is this class's job, and finding the facts is
# SessionScan's (covered against the golden fixtures in session_scan_test.rb).
class ImporterPageTest < Minitest::Test
  Page = ConversationStory::ImporterPage

  def scan(project:, mtime:, **overrides)
    { "session_id" => "id-#{mtime}", "title" => "A session", "first_prompt" => "do the thing",
      "recap" => "Did **the thing**.", "turns" => 4, "subagents" => 0,
      "max_context" => 45_000, "size" => 1024 * 1024, "mtime" => mtime.to_f,
      "path" => "/logs/id-#{mtime}.jsonl", "project" => project,
      # The usual case: the label came off the log's own `cwd`. Override with
      # "directory" for a stub session whose label had to be guessed.
      "project_source" => "cwd" }.merge(overrides)
  end

  # Newest first, as Import.sessions hands them over.
  def page_for(*scans, **kwargs) = Page.new(scans, **kwargs)

  def test_groups_by_project
    page = page_for(scan(project: "a", mtime: 30), scan(project: "b", mtime: 20),
                    scan(project: "a", mtime: 10))

    assert_equal [["a", 2], ["b", 1]], page.groups.map { |name, s| [name, s.size] }
  end

  # The whole point of "taken globally, then grouped": project "b" owns the
  # newest session, so "b" comes first even though "a" has more of them.
  def test_projects_are_ordered_by_their_newest_session
    page = page_for(scan(project: "b", mtime: 90), scan(project: "a", mtime: 80),
                    scan(project: "a", mtime: 70), scan(project: "a", mtime: 60))

    assert_equal %w[b a], page.groups.map(&:first)
  end

  # THE CASE THE REAL CORPUS HANDED US. A stub session (no conversation, so no
  # `cwd` anywhere in its log) gets its project label decoded from the harness's
  # dash-encoded directory name, and the page showed the same project twice:
  # `code/jessitron/mtg-deck-shuffler` and `code-jessitron-mtg-deck-shuffler`.
  # The decode is lossy, but the encode isn't — `label.tr("/", "-")` — so a
  # guessed label that matches a scanned `cwd` label joins it.
  def test_a_guessed_label_joins_the_cwd_group_it_encodes_to
    page = page_for(scan(project: "code/jessitron/mtg-deck-shuffler", mtime: 20),
                    scan(project: "code-jessitron-mtg-deck-shuffler", mtime: 10,
                         "project_source" => "directory"))

    assert_equal [["code/jessitron/mtg-deck-shuffler", 2]],
                 page.groups.map { |name, s| [name, s.size] }
    refute_includes page.html, "guessed from directory name"
  end

  # A worktree's `/.claude/` segment lands in the directory name as a doubled
  # dash, so the match has to survive the dot too.
  def test_a_guessed_label_matches_through_a_dotted_path_segment
    page = page_for(scan(project: "code/jessitron/story/.claude/worktrees/w", mtime: 20),
                    scan(project: "code-jessitron-story--claude-worktrees-w", mtime: 10,
                         "project_source" => "directory"))

    assert_equal ["code/jessitron/story/.claude/worktrees/w"], page.groups.map(&:first)
  end

  # Nothing to match against: it keeps its own group and says the label is a guess.
  def test_an_unmatched_guessed_label_keeps_its_own_group_and_says_so
    page = page_for(scan(project: "code/jessitron/one", mtime: 20),
                    scan(project: "code-jessitron-other", mtime: 10,
                         "project_source" => "directory"))

    assert_equal ["code/jessitron/one", "code-jessitron-other"], page.groups.map(&:first)
    assert_includes page.html, "guessed from directory name"
  end

  # Two different real projects CAN encode to the same string (`a/b-c` and
  # `a-b/c`), so adopting either would be a coin flip. Leave the guess alone.
  def test_an_ambiguous_encoding_is_not_adopted
    page = page_for(scan(project: "a/b-c", mtime: 30),
                    scan(project: "a-b/c", mtime: 20),
                    scan(project: "a-b-c", mtime: 10, "project_source" => "directory"))

    assert_equal ["a/b-c", "a-b/c", "a-b-c"], page.groups.map(&:first)
  end

  def test_sessions_within_a_project_stay_newest_first
    page = page_for(scan(project: "a", mtime: 30), scan(project: "a", mtime: 20),
                    scan(project: "a", mtime: 10))

    assert_equal [30.0, 20.0, 10.0], page.groups.first.last.map { |s| s["mtime"] }
  end

  # `for_recent_sessions` is where the limit lives, and it only ever scans the
  # first `limit` sessions — the 376 older logs are never opened. Real fixtures
  # and a throwaway cache dir, so this exercises the actual SessionScan seam.
  def test_scans_only_the_limit_most_recent_sessions
    fixtures = Dir.glob(File.expand_path("../examples/*.jsonl", __dir__)).sort
    skip "needs at least 3 example logs" if fixtures.size < 3

    fake = Struct.new(:path)
    sessions = fixtures.map { |path| fake.new(path) }

    Dir.mktmpdir do |dir|
      cache = ConversationStory::SessionScan::Cache.new(dir)
      page = Page.for_recent_sessions(limit: 2, cache: cache, sessions: sessions)

      assert_equal 2, page.scans.size
      assert_equal fixtures.size, page.total_sessions
      assert_equal 2, cache.misses
      assert_equal 2, Dir.glob(File.join(dir, "*.json")).size,
                   "each scan is cached the moment it finishes"

      # A second build of the same page reads the cache and reopens nothing.
      warm = ConversationStory::SessionScan::Cache.new(dir)
      Page.for_recent_sessions(limit: 2, cache: warm, sessions: sessions)
      assert_equal 2, warm.hits
      assert_equal 0, warm.misses
    end
  end

  def test_recap_is_rendered_as_prose_and_never_truncated
    long = "word " * 400
    html = page_for(scan(project: "a", mtime: 1, "recap" => long)).html

    assert_includes html, %(class="session-recap d-markdown")
    assert_includes html, long.strip
  end

  def test_a_session_with_no_recap_still_renders_a_card
    html = page_for(scan(project: "a", mtime: 1, "recap" => nil)).html

    assert_includes html, "session-card"
    assert_includes html, "no recap"
    refute_includes html, "d-markdown"
  end

  def test_a_session_with_no_title_or_prompt_still_renders_a_card
    html = page_for(scan(project: "a", mtime: 1, "title" => nil, "first_prompt" => nil)).html

    assert_includes html, "(untitled session)"
    assert_includes html, "no plain-text prompt"
  end

  # No user-controlled string reaches the page as markup — the same rule the
  # renderer follows. Markdown.to_html escapes before it substitutes; everything
  # else goes through CGI.escapeHTML.
  def test_conversation_text_cannot_inject_html
    nasty = "<script>alert(1)</script>"
    html = page_for(scan(project: nasty, mtime: 1, "title" => nasty,
                         "first_prompt" => nasty, "recap" => nasty)).html

    refute_includes html, nasty
    assert_includes html, "&lt;script&gt;"
  end

  def test_links_importer_css_after_story_css
    html = page_for(scan(project: "a", mtime: 1)).html

    story = html.index("assets/story.css")
    importer = html.index("assets/importer.css")
    refute_nil story
    refute_nil importer
    assert_operator story, :<, importer, "importer.css must load after story.css"
  end

  # Decision 10, and it's the kind of thing a later well-meaning agent adds back.
  def test_no_publishing_warning
    html = page_for(scan(project: "a", mtime: 1)).html

    %w[warning Warning proprietary public\ repo careful].each do |word|
      refute_includes html, word
    end
  end

  # A stub session — a couple of bookkeeping lines and no conversation — is a few
  # hundred bytes, and "0 KB" read as a broken card rather than a tiny one.
  def test_a_tiny_log_reports_bytes_not_zero_kb
    html = page_for(scan(project: "a", mtime: 1, "size" => 412)).html

    assert_includes html, "412 B"
  end

  def test_empty_listing_says_so_instead_of_rendering_nothing
    html = Page.new([]).html

    assert_includes html, "No session logs found"
  end

  def test_writes_the_page_into_the_given_directory
    Dir.mktmpdir do |dir|
      path = File.join(dir, "nested", "index.html")
      assert_equal path, page_for(scan(project: "a", mtime: 1)).write(path)
      assert_includes File.read(path), "session-card"
    end
  end

  # ---- tickets 04/05: the name field, Import/Re-snapshot, live -----------

  def test_name_field_defaults_to_a_slug_of_the_title
    html = page_for(scan(project: "a", mtime: 1, "title" => "Mode Switches")).html

    assert_includes html, %(value="mode-switches")
    assert_includes html, "examples/mode-switches.jsonl"
    assert_includes html, ">Import<"
  end

  def test_a_session_already_in_examples_shows_its_existing_name_and_re_snapshot
    page = Page.new([scan(project: "a", mtime: 1, "session_id" => "abc-123", "title" => "Anything")],
                    existing: { "mode-switches" => "abc-123" })

    assert_includes page.html, %(value="mode-switches")
    assert_includes page.html, ">Re-snapshot<"
    refute_includes page.html, ">Import<"
  end

  def test_a_recently_written_session_is_flagged_live
    live = page_for(scan(project: "a", mtime: Time.now.to_i)).html
    stale = page_for(scan(project: "a", mtime: Time.now.to_i - 1000)).html

    assert_includes live, "live-badge"
    refute_includes stale, "live-badge"
  end

  # The generated page belongs in the gitignored importer workspace, next to the
  # scan cache — never anywhere git would pick it up (private conversation data
  # in a public repo).
  def test_default_page_path_is_the_gitignored_workspace
    assert_equal ConversationStory::SessionScan::CACHE_DIR,
                 File.join(Page::OUT_DIR, "scans")
    assert_equal File.join(Page::OUT_DIR, "index.html"), Page::PAGE_PATH

    gitignore = File.read(File.expand_path("../.gitignore", __dir__))
    assert_includes gitignore, ".importer/"
  end
end
