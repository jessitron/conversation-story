# Session 25 — `conversation-importer` design (grilling, no code yet)

A grilling session over TODO.md's `conversation-importer` item. Twelve decisions,
settled with Jess. **Nothing was built** — this note is the whole output, so the
next session can start from a settled tree instead of re-deriving one.

## Facts established (measured, not assumed)

- **The logs are not in `~/.claude/projects`.** That directory is empty on this
  machine. Sessions live under two config dirs:
  `~/.claude-work/projects` (25 projects, 367 main logs, 573 MB) and
  `~/.claude-personal/projects` (5 projects, 49 logs, 48 MB). Including subagent
  sidecars that's ~1,100 files and 621 MB.
- **`bin/grab-example` is therefore broken today** — it hardcodes
  `~/.claude/projects` and would die with "no session logs for this repo". It
  also only ever looks at *this* repo's project dir, which is why
  `mtg-tabletop-plan` (from another project) had to be brought in by hand.
- **The recap** is a `type: "system"` record with `subtype: "away_summary"`;
  the text is in `content` and ends with a literal
  `"(disable recaps in /config)"` tail worth stripping. Not every session has one.
- **The title** is `type: "ai-title"`, field `aiTitle`. There are several per
  session (it gets regenerated) — take the **last**.
- **Every `examples/*.jsonl` first line carries `sessionId`**, so "already
  imported?" is answerable from the fixtures themselves — no manifest file needed.
- **No log has ever compacted** — zero `isCompactSummary` records across all 416
  logs. On a sample log the last assistant record's context total (76,597) was
  *exactly* the max over all records.
- Record-type census across all logs: assistant, user, attachment, mode,
  last-prompt, permission-mode, ai-title, agent-setting, relocated,
  worktree-state, file-history-delta, system, agent-name, file-history-snapshot,
  queue-operation, plus rarities (`atis-latch`, `frame-link`, `pr-link`).
- `examples/4b0be952-d0bd-49ed-b97a-357b9149bf31.jsonl` is a fixture that was
  imported and never named. That's the failure mode the naming step exists to
  prevent.

## The decisions

1. **A standalone `bin/importer`** — a fourth program, local-only, alongside
   `bin/parse` / `bin/render` / `bin/site-index`. *Not* a route on `bin/serve`:
   the served site is the published artifact (GitHub Pages), the importer is a
   local authoring tool that must never ship.
2. **Lists ~50 most recent sessions** across both config dirs, **grouped by
   project** (50 taken globally by mtime, then grouped; projects ordered by
   their newest session). Per-log stats **cached** by path + mtime + size, so an
   unchanged log is never reopened.
3. **Import copies then builds one example**: writes `examples/<slug>.jsonl` +
   sidecars, then shells out to `bin/parse` and `bin/render` for that name only,
   and links to the result. Follows `bin/serve`'s precedent — a write shells out
   to the real programs rather than patching files in place. Not a full
   `rake build`: adding one example shouldn't re-render five unrelated ones.
4. **The name is an editable text input**, pre-filled with a slug derived from
   the `ai-title`, slugified again on the way to the filename, with the
   resulting `examples/<slug>.jsonl` shown live under the field. Same
   `[a-z0-9-]` slug rule `grab-example` enforces; refuses to silently overwrite.
5. **A row shows**: title, first plain-string user prompt, the recap **in full**
   (it is the thing you actually read to judge a session), turns as **distinct
   `message.id`** (not assistant-record count, which inflates ~3x), subagent
   count (files in `subagents/`, free), max context, file size, date.
6. **Max context**: take the true max over all assistant records. Jess initially
   said "just the last assistant record, I'm ok missing pre-compaction peaks" —
   then the measurement showed the scan reads the whole file anyway (for turns,
   title, recap), so the max is free, no log has ever compacted, and on the
   sample the two numbers were identical.
7. **HTML + cache both go in a gitignored dir.** Jess overruled the
   serve-from-memory proposal: the cache already puts private derived data on
   disk under a gitignore entry, so writing the HTML there adds no exposure.
8. **New `ConversationStory::SessionScan`** — a streaming O(1)-memory pass, one
   session at a time, result cached immediately. Does **not** reuse `Parser`:
   `Parser` accumulates a full event array and recursively parses every subagent
   sidecar, so 50 runs over 621 MB would take minutes and gigabytes to compute
   five numbers. Two specifics, both from Jess's memory warning:
   - **Pre-filter before `JSON.parse`** (cheap `line.include?` check). The real
     hazard is a *single line* — one tool result can be megabytes — and the
     filter means those are read as a string and discarded, never made into
     Ruby objects.
   - **Never hold 50 scans in memory**; write each to cache as it completes, so
     a crash mid-scan doesn't lose the ones already done.
9. **Copy logic extracted and shared** (`ConversationStory::Import`); both
   `bin/grab-example` and `bin/importer` call it. `grab-example` survives — it's
   scriptable, works without a browser, and CLAUDE.md documents it. The shared
   code takes a session **path**, not a derived one, and discovery spans **both
   config dirs and all projects** — which fixes the two `grab-example` bugs
   above, and `--list` inherits the fix.
10. **No publishing guardrail.** Discovery across both dirs means work sessions
    appear in a list whose Import button leads to a public repo. Jess's call:
    "MY work conversations are almost never about proprietary code." Grouping by
    project already puts the origin on screen as plain information. Don't
    reintroduce a warning.
11. **Testing**: minitest for `SessionScan` against the golden `examples/`
    fixtures (giving the scanner the same golden-suite treatment the parser
    gets), plus **`bin/check-importer`** in the `bin/check-edit-api` mould —
    plain HTTP, no Chrome, driving a real import and asserting fixture + built
    page appeared. Runs against a **temp examples dir and temp cache**; a small
    temp examples dir also makes the shelled-out parse/render fast enough to
    loop on. No ferrum: `check-modes` earns Chrome because keyboard/mode
    behavior is unobservable from Ruby; a `<form>` submitting is not.
12. **`assets/importer.css`, built on `story.css`'s tokens** and loaded after
    it — the pattern `assets/index.css` already demonstrates. Rows are cards
    with the recap as the body (closer to the landing page's story cards than to
    a table), not a dense table. Candidate for the `design-feature-owner`
    TODO's attention later; don't invent much new visual language now.
13. **Already-imported** is detected from the first line's `sessionId`. Such a
    row shows its example name and its button becomes **Re-snapshot**:
    overwrite in place under the existing name and rebuild — behaviour
    `grab-example` already documents ("Re-run to re-snapshot"). Re-snapshot
    **merges sidecars** rather than no-opping on a size match: a subagent that
    finished after the first snapshot is a *new* file. A log written to in the
    last couple of minutes is flagged **live** on the row, because that fixture
    is guaranteed incomplete.
14. **Post-import link points at `bin/serve`** (`http://localhost:8080/<name>/`),
    **health-probed** via `GET /api/health` — the same trick `story.js` uses to
    decide whether to show the editor — so the link renders live or as "start
    `rake serve` to view". The importer does **not** serve `out/` itself: that's
    the leak that would drag it back into being two programs. Not `file://`
    either, which silently loses edit mode. Importer on **8081**, `bin/serve`
    stays 8080, both `PORT=`-overridable.

## Follow-through the implementation must not forget

- The `Rakefile`'s `*_SRC` lists are explicit, not globs — `SessionScan` and
  `Import` need adding or `rake build` won't notice they changed.
- CLAUDE.md's "`bin/grab-example` brings a new one in" paragraph needs rewriting
  to name the importer as the primary door, with `grab-example` as the CLI one.
- `.gitignore` needs the cache/HTML dir.
