# frozen_string_literal: true

require "cgi"
require "fileutils"

require_relative "import"
require_relative "markdown"
require_relative "session_scan"

module ConversationStory
  # The importer's listing page: Jess's recent Claude sessions, each one a card
  # she can recognise, so picking a golden fixture stops being a JSONL grep.
  #
  # This class is the PAGE, not the server. `bin/importer` is a WEBrick shell
  # around it (session 25, decision 1: a fourth program, never shipped to
  # GitHub Pages). Keeping the HTML here means the grouping and the markup are
  # testable without a socket — the same split that lets `bin/site-index`'s
  # labels come off `Renderer`.
  #
  # THE 50 ARE TAKEN GLOBALLY, THEN GROUPED. Order matters and is easy to get
  # backwards: take the newest 50 sessions across *both* config dirs and *all*
  # projects, and only then group them by project. Grouping first and taking 50
  # per project would bury this week's work under an old project's backlog.
  # Because `Import.sessions` is already newest-first and `group_by` keeps
  # insertion order, "projects ordered by their newest session" needs no extra
  # sort — the first project to appear is the one that owns the newest session.
  #
  # THE RECAP IS THE BODY, IN FULL. It is the thing Jess actually reads to judge
  # whether a session is a story (decision 5), so it is never truncated and it
  # gets the card's widest column. That's also why a card and not a table row.
  #
  # NO PUBLISHING WARNING, deliberately (decision 10). Work sessions do appear
  # in a list whose Import button will lead to a public repo; Jess's call is that
  # her work conversations are almost never about proprietary code, and grouping
  # by project already puts each session's origin on screen as plain
  # information. Don't reintroduce one.
  class ImporterPage
    # "~50 most recent" (user story 4): enough to find last week's work,
    # few enough that the page is scannable instead of 426 rows.
    LIMIT = 50

    # The importer's workspace — gitignored, and shared with SessionScan's cache
    # (decision 7: the cache already puts derived private data on disk under a
    # gitignore entry, so the HTML adds no exposure). Nothing here is ever
    # committed and everything here is rebuildable from the logs.
    OUT_DIR   = File.expand_path("../../.importer", __dir__)
    PAGE_PATH = File.join(OUT_DIR, "index.html")

    # Scan the `limit` most recent sessions and build the page for them.
    #
    # One scan at a time, and `SessionScan::Cache` writes each result the moment
    # it completes — so a cold pass that dies halfway keeps what it did, and the
    # next load pays only for logs that changed.
    def self.for_recent_sessions(limit: LIMIT, cache: SessionScan::Cache.new,
                                 sessions: Import.sessions)
      recent = sessions.first(limit)
      scans  = recent.map { |session| SessionScan.fetch(session.path, cache: cache) }
      new(scans, total_sessions: sessions.size, cache: cache)
    end

    # @param scans [Array<Hash>] SessionScan results, newest first
    # @param total_sessions [Integer, nil] how many exist in all, for the footer
    def initialize(scans, total_sessions: nil, cache: nil, generated_at: Time.now)
      @scans = scans
      @total_sessions = total_sessions || scans.size
      @cache = cache
      @generated_at = generated_at
    end

    attr_reader :total_sessions

    # The scans as the page uses them: with every project label RECONCILED (see
    # `reconcile`), so one project appears once no matter how its sessions
    # recorded which project they were in.
    def scans = @reconciled ||= reconcile(@scans)

    # How much of this page came off the cache — the numbers that make "a second
    # load is fast" observable instead of a feeling. Zero when no cache was used.
    def cache_hits   = @cache ? @cache.hits : 0
    def cache_misses = @cache ? @cache.misses : 0

    # [[project, [scan, ...]], ...] — projects in newest-session order, and each
    # project's sessions newest first, both inherited from the input order.
    def groups
      scans.group_by { |scan| scan["project"].to_s }.to_a
    end

    def write(path = PAGE_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, html)
      path
    end

    def html
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Import a Conversation</title>
        <!-- Fonts via CDN, same as the story pages (self-hosting is a TODO). -->
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Cascadia+Code:wght@400;600&family=Tenor+Sans&family=Sen:wght@400;500;700&display=swap" rel="stylesheet">
        <link rel="stylesheet" href="assets/story.css">
        <link rel="stylesheet" href="assets/importer.css">
        </head>
        <body>

        #{header_html}

        <main class="importer">
        #{indent(groups_html, 2)}
        #{indent(footer_html, 2)}
        </main>

        </body>
        </html>
      HTML
    end

    private

    # ONE PROJECT, ONE GROUP. A session that never got a reply out of the model
    # carries no `cwd` anywhere in its log, so its project label is DECODED from
    # the harness's dash-encoded directory name — and the real corpus promptly
    # showed the same project twice, as `code/jessitron/mtg-deck-shuffler` and as
    # `code-jessitron-mtg-deck-shuffler`.
    #
    # The decode is lossy; the ENCODE is not. For any session whose label came
    # from a `cwd`, `label.tr("/", "-")` reproduces the directory-name form
    # character for character. So don't decode — MATCH, in the lossless
    # direction, against the labels this page already scanned. An exact hit
    # proves the two sessions sat in the same directory, and the guessed one
    # adopts the `cwd` spelling.
    #
    # A PAGE-level fix on purpose: SessionScan sees one log at a time and caches
    # per log, so no single scan can know what the other 49 said.
    #
    # A guessed label matching nothing keeps its own group and its "guessed from
    # directory name" note. So does an ambiguous one — two different `cwd` labels
    # can encode to the same string (`a/b-c` and `a-b/c`), and picking either
    # would be a coin flip.
    def reconcile(scans)
      known = {}
      scans.each do |scan|
        next unless scan["project_source"] == "cwd"

        key = encoded(scan["project"])
        known[key] = known.key?(key) && known[key] != scan["project"] ? :ambiguous : scan["project"]
      end

      scans.map do |scan|
        next scan unless scan["project_source"] == "directory"

        match = known[encoded(scan["project"])]
        next scan unless match.is_a?(String)

        # A third `project_source` value, so the group note can tell "this label
        # IS a cwd label" from "this label is still a guess".
        scan.merge("project" => match, "project_source" => "cwd_match")
      end
    end

    # The comparison form. Slashes become dashes because that is exactly what the
    # harness does to a path to name a project directory. Dots go the same way
    # because a git worktree's `/.claude/` segment lands in the directory name as
    # a DOUBLED dash, so an encoded `cwd` (`…-.claude-…`) has to meet it there.
    def encoded(label) = label.to_s.tr("/.", "--")

    def header_html
      <<~HTML.rstrip
        <header class="site">
          <img class="logo" src="images/logo.png" alt="Graceful Developer logo">
          <div class="titles">
            <h1 class="deco">Import a Conversation</h1>
            <span class="subtitle">recent sessions on this machine</span>
          </div>
          <div class="meta">
            #{stat("Sessions", scans.size)}
            #{stat("Projects", groups.size)}
            #{stat("Updated", @generated_at.strftime("%H:%M"))}
          </div>
        </header>
      HTML
    end

    def stat(key, value)
      %(<span class="stat"><span class="k">#{h key}</span><span class="v">#{h value}</span></span>)
    end

    def groups_html
      return %(<p class="empty">No session logs found under #{h Import::CONFIG_DIRS.join(" or ")}.</p>) if scans.empty?

      groups.map { |project, scans| group_html(project, scans) }.join("\n")
    end

    # A group whose label was DECODED from the directory name says so. Otherwise
    # one project can appear twice — its real `cwd` label plus the dashed decode
    # of a stub session that never got far enough to record a `cwd` — and read as
    # two unrelated projects.
    def group_html(project, scans)
      guessed = scans.all? { |scan| scan["project_source"] == "directory" }
      note = guessed ? %(<span class="project-note">guessed from directory name</span>) : ""
      <<~HTML.rstrip
        <section class="project">
          <h2 class="project-name deco">#{h project}#{note}<span class="project-count">#{h scans.size}</span></h2>
        #{indent(scans.map { |scan| card_html(scan) }.join("\n"), 2)}
        </section>
      HTML
    end

    # One session. The recap is the body; everything else frames it.
    #
    # Ticket 03 is READ-ONLY: no name field, no Import button, nothing wired.
    # `.session-actions` is the empty shelf those belong on (tickets 04/05), so
    # adding them is a fill-in rather than a re-layout.
    def card_html(scan)
      <<~HTML.rstrip
        <article class="session-card">
          <div class="session-head">
            <h3 class="session-title">#{h title_of(scan)}</h3>
            <div class="session-stats">
        #{indent(stats_html(scan), 6)}
            </div>
          </div>
          <p class="session-prompt">#{prompt_html(scan)}</p>
          #{recap_html(scan)}
          <div class="session-actions">
            <code class="session-id">#{h scan["session_id"]}</code>
          </div>
        </article>
      HTML
    end

    # A session that never got far enough for the harness to name it still has
    # to render as a card — same reason a missing recap does (user story 11).
    def title_of(scan)
      title = scan["title"].to_s.strip
      title.empty? ? "(untitled session)" : title
    end

    def stats_html(scan)
      [stat("Turns", scan["turns"]),
       stat("Subagents", scan["subagents"].to_i.positive? ? scan["subagents"] : "—"),
       stat("Max context", format_tokens(scan["max_context"])),
       stat("Size", format_size(scan["size"])),
       stat("Written", format_time(scan["mtime"]))].join("\n")
    end

    def prompt_html(scan)
      prompt = scan["first_prompt"].to_s.strip
      return %(<span class="none">no plain-text prompt in this log</span>) if prompt.empty?

      h(prompt)
    end

    # PROSE, through the same safe markdown subset the detail pane uses — recaps
    # are written in markdown, and Markdown.to_html escapes before it substitutes
    # so nothing in a conversation can inject a tag.
    #
    # No recap is the common case for a short session, so it says so rather than
    # leaving a hole where the body should be.
    def recap_html(scan)
      recap = scan["recap"].to_s.strip
      return %(<p class="session-recap none">no recap — this session was never left and resumed</p>) if recap.empty?

      %(<div class="session-recap d-markdown">#{Markdown.to_html(recap)}</div>)
    end

    def footer_html
      lines = []
      rest = @total_sessions - scans.size
      if rest.positive?
        lines << "#{scans.size} most recent of #{@total_sessions} sessions " \
                 "(#{rest} older not shown)"
      end
      lines << "#{@cache.hits} cached, #{@cache.misses} scanned" if @cache
      return "" if lines.empty?

      %(<p class="importer-footer">#{h lines.join(" · ")}</p>)
    end

    # ---- formatting -----------------------------------------------------

    def format_tokens(tokens)
      tokens = tokens.to_i
      return tokens.to_s if tokens < 1000

      "#{(tokens / 1000.0).round(tokens < 10_000 ? 1 : 0)}k"
    end

    def format_size(bytes)
      bytes = bytes.to_i
      # Bare bytes below a kilobyte: the stub sessions (a couple of bookkeeping
      # lines, no conversation) are a few hundred bytes, and "0 KB" read as a
      # broken card rather than as a tiny one.
      return "#{bytes} B" if bytes < 1024
      return "#{(bytes / 1024.0).round} KB" if bytes < 1024 * 1024

      "#{(bytes / 1024.0 / 1024).round(1)} MB"
    end

    # `mtime` comes back from the scan as a Float epoch, not a Time — the cache
    # stores JSON-native types only, so a hit and a miss look identical.
    def format_time(mtime)
      Time.at(mtime.to_f).strftime("%b %-d, %H:%M")
    end

    def h(value) = CGI.escapeHTML(value.to_s)

    def indent(text, spaces)
      pad = " " * spaces
      text.split("\n").map { |line| line.empty? ? line : pad + line }.join("\n")
    end
  end
end
