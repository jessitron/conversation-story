# Spec: `conversation-importer`

Status: ready-for-agent

Source: `notes/2026-08-18-session-25-conversation-importer-design.md` (fourteen
decisions, settled with Jess by grilling; nothing was built).
Backlog item: `conversation-importer` in `TODO.md`.

## Problem Statement

Jess has ~416 Claude session logs (~621 MB) spread across two config
directories — `~/.claude-work/projects` (25 projects) and
`~/.claude-personal/projects` (5 projects). When she wants a new **golden
fixture** in `examples/`, she has no way to see what those sessions *are*. The
only door is `bin/grab-example`, and:

- It reads `~/.claude/projects`, which is **empty on this machine**, so it dies
  with "no session logs for this repo" — it is broken today.
- It only ever looks at *this* repo's project directory, so a session from
  another project (like `mtg-tabletop-plan`) has to be copied in by hand.
- `--list` shows a session id, size, date, and the first prompt. That is not
  enough to judge whether a conversation is worth turning into a story: it
  doesn't show the AI-generated title, the recap, how many turns, whether
  subagents ran, or how big the context ever got.
- Nothing prompts for a *name*, so a fixture can land as a raw session id.
  `examples/4b0be952-d0bd-49ed-b97a-357b9149bf31.jsonl` is exactly that failure
  already sitting in the repo.

So choosing a fixture means grepping JSONL by hand, and importing one means
remembering an undocumented multi-step dance.

## Solution

A **local-only browser app**, `bin/importer`, that lists Jess's recent Claude
sessions from both config directories, grouped by project, each as a card
showing enough to recognise and judge it — title, first prompt, the full recap,
turn count, subagent count, max context, size, date. Each card has a name field
pre-filled from the session's AI title and an **Import** button. Pressing it
copies the log plus any subagent sidecars into `examples/<name>.jsonl`, builds
just that one story, and links to it on the authoring server.

Sessions already in `examples/` are recognised by `sessionId` and offer
**Re-snapshot** instead, under the name they already have.

It is a fourth program next to `bin/parse` / `bin/render` / `bin/site-index` —
an authoring tool that never ships to GitHub Pages.

## User Stories

1. As Jess, I want to run one command and get a browser page of my recent
   conversations, so that I can pick a fixture without grepping JSONL by hand.
2. As Jess, I want the importer to read **both** `~/.claude-work/projects` and
   `~/.claude-personal/projects`, so that every session I've had is a candidate.
3. As Jess, I want sessions from **all** projects, not just this repo, so that
   bringing in something like `mtg-tabletop-plan` isn't a manual copy.
4. As Jess, I want roughly the **50 most recent** sessions, so the page is
   scannable rather than a wall of 416 rows.
5. As Jess, I want those 50 taken globally by recency and **then grouped by
   project**, with projects ordered by their newest session, so the freshest
   work is at the top and each session's origin is visible.
6. As Jess, I want each session's **AI-generated title** on its card, so I can
   recognise a conversation at a glance.
7. As Jess, I want the **last** `ai-title` record used, not the first, because
   the harness regenerates the title as the session goes and the last one is the
   most informed.
8. As Jess, I want the **first plain-string user prompt** shown, so I see what I
   actually asked for, not a harness XML blob.
9. As Jess, I want the session's **recap in full**, not truncated, because the
   recap is the thing I actually read to decide whether a session is a story.
10. As Jess, I want the recap's trailing `"(disable recaps in /config)"` tail
    stripped, so the card body is prose and not harness chrome.
11. As Jess, I want a card to render fine when a session has **no recap**, since
    not every session does.
12. As Jess, I want a **turn count** measured as distinct `message.id` values,
    so it reflects API responses rather than the ~3× inflated assistant-record
    count.
13. As Jess, I want a **subagent count**, so I can tell whether a session has
    the nested-document story shape that shows off the renderer.
14. As Jess, I want the session's **max context** over all assistant records, so
    I know how heavy the conversation got.
15. As Jess, I want **file size** and **last-write date** on the card, so I know
    what I'm about to commit and how fresh it is.
16. As Jess, I want the scan to be **fast on a repeat visit**, so reloading the
    page doesn't reread 621 MB.
17. As Jess, I want per-session stats **cached by path + mtime + size**, so an
    unchanged log is never reopened but an appended one is rescanned.
18. As Jess, I want the scanner to **not exhaust memory** on a log holding a
    multi-megabyte tool result on a single line.
19. As Jess, I want each session's scan **written to the cache as it finishes**,
    so a crash partway through a cold scan doesn't throw away the work already
    done.
20. As Jess, I want an editable **name field** on each card, pre-filled with a
    slug derived from the AI title, so the good default is one keystroke away
    and a better name is always possible.
21. As Jess, I want the resulting **`examples/<slug>.jsonl` path shown live**
    under the name field as I type, so I see exactly what file will appear.
22. As Jess, I want the name slugified on the way to the filename and **refused**
    if it isn't a clean `[a-z0-9-]` slug, matching what `grab-example` already
    enforces.
23. As Jess, I want an import that would **overwrite an unrelated existing
    example refused**, not silently clobbered.
24. As Jess, I want Import to copy the main log **and** any `subagents/`
    sidecars, so the nested-document story survives the trip.
25. As Jess, I want Import to then build **just that one example**, so adding a
    fixture doesn't re-render five unrelated stories.
26. As Jess, I want that build to happen by the importer **shelling out to
    `bin/parse` and `bin/render`**, so a fixture built through the browser is
    byte-identical to one built by `rake build`.
27. As Jess, I want a **link to the finished story** after an import, so I can
    look at it immediately.
28. As Jess, I want that link to point at **`bin/serve`** (`localhost:8080`), not
    `file://`, because `file://` silently loses edit mode.
29. As Jess, I want the importer to **health-probe** `bin/serve` and, when it
    isn't running, tell me to start `rake serve` instead of handing me a dead
    link.
30. As Jess, I want the importer to **not serve `out/` itself**, so it stays one
    program and doesn't grow into a second `bin/serve`.
31. As Jess, I want the importer on **8081** with `bin/serve` left on 8080, so
    both can run at once.
32. As Jess, I want both ports **`PORT=`-overridable**, matching the rest of the
    repo's programs.
33. As Jess, I want a session **already in `examples/`** to be recognised, so I
    don't import the same conversation twice under two names.
34. As Jess, I want that recognition done from the fixture's own first-line
    `sessionId`, so no manifest file has to be maintained or can go stale.
35. As Jess, I want an already-imported card to **show the example name** it went
    in as, so I can find it.
36. As Jess, I want its button to read **Re-snapshot** and overwrite in place
    under the existing name, matching the behaviour `grab-example` documents.
37. As Jess, I want Re-snapshot to **merge sidecars** rather than no-op on a size
    match, because a subagent that finished after the first snapshot is a new
    file that a size comparison won't notice.
38. As Jess, I want a log written to in the **last couple of minutes flagged
    "live"** on its card, because that fixture is guaranteed to be incomplete.
39. As Jess, I want the importer's generated HTML and its cache to live in a
    **gitignored directory**, so private conversation data never lands in a
    public repo.
40. As Jess, I want the page to look like this project — cards built on
    `story.css`'s tokens — so the importer doesn't feel like a different app.
41. As Jess, I want rows as **cards with the recap as the body**, closer to the
    landing page's story cards than to a dense table, because the recap is
    prose and wants room.
42. As Jess, I want **`bin/grab-example` fixed and kept**, so the CLI door still
    works — it's scriptable, needs no browser, and CLAUDE.md documents it.
43. As Jess, I want `grab-example` to take a session **path** and search **both**
    config dirs across **all** projects, so its two bugs are gone and `--list`
    inherits the fix.
44. As Jess, I want the copy logic **shared** between `grab-example` and
    `bin/importer`, so the two doors can't drift.
45. As Jess, I want **no publishing warning** on the page. Work sessions do
    appear in a list whose Import button leads to a public repo; my work
    conversations are almost never about proprietary code, and grouping by
    project already puts the origin on screen as plain information.
46. As Jess, I want `SessionScan` covered by **minitest against the golden
    `examples/` fixtures**, so the scanner gets the same golden-suite treatment
    the parser gets.
47. As Jess, I want a **`bin/check-importer`** that drives a real import over
    plain HTTP and asserts the fixture and the built page appeared, in the same
    mould as `bin/check-edit-api`.
48. As Jess, I want that check to run against a **temp examples dir and temp
    cache**, so it never touches my real fixtures and the shelled-out
    parse/render stays fast enough to loop on.
49. As Jess, I want the new `lib/` files added to the **`Rakefile`'s `*_SRC`
    lists**, because those are explicit lists and not globs, so `rake build`
    would otherwise not notice they changed.
50. As Jess, I want **CLAUDE.md's `grab-example` paragraph rewritten** to name
    the importer as the primary door and `grab-example` as the CLI one, so the
    next session's agent doesn't reach for the wrong tool.

## Implementation Decisions

### New and modified modules

- **`bin/importer`** — a new, fourth program. Local-only authoring tool; a
  WEBrick server on **8081** (`PORT=`-overridable) that generates the listing
  page and accepts the import request. Deliberately **not** a route on
  `bin/serve`: the served site is the published artifact (GitHub Pages) and the
  importer must never ship.
- **`ConversationStory::SessionScan`** — new. A streaming, O(1)-memory pass over
  one session log, producing that session's card stats. It does **not** reuse
  `Parser`: `Parser` accumulates a full event array and recursively parses every
  subagent sidecar, so 50 runs over 621 MB would take minutes and gigabytes to
  compute five numbers.
- **`ConversationStory::Import`** — new. Owns the copy: given a session log
  **path** and a target name, writes `examples/<name>.jsonl` plus
  `examples/<name>/subagents/`. Also owns **discovery** — enumerating session
  logs across both config dirs and all projects. Called by both `bin/importer`
  and `bin/grab-example`.
- **`bin/grab-example`** — modified. Keeps its CLI interface; delegates
  discovery and copying to `ConversationStory::Import`, which fixes both its
  bugs (wrong config dir, this-repo-only) and fixes `--list` with it.
- **`assets/importer.css`** — new, built on `story.css`'s tokens and loaded
  after it, the pattern `assets/index.css` already demonstrates.
- **`Rakefile`** — the explicit `PARSE_SRC` / `RENDER_SRC` / `SITE_SRC` lists
  need the new `lib/` files, or `rake build` won't notice they changed.
- **`.gitignore`** — needs the importer's output/cache directory.
- **`CLAUDE.md`** — the "`bin/grab-example` brings a new one in" paragraph
  rewritten around the importer.

### What a scan produces

Per session, from a single streaming pass:

- `session_id` — first line's `sessionId`.
- `title` — the **last** `type: "ai-title"` record's `aiTitle`. There are
  several per session; the harness regenerates it.
- `first_prompt` — the first `type: "user"` record whose `message.content` is a
  plain String and doesn't start with `<` (harness blob).
- `recap` — the `content` of the `type: "system"`, `subtype: "away_summary"`
  record, with the trailing `"(disable recaps in /config)"` stripped. May be
  absent.
- `turns` — count of **distinct `message.id`** values across assistant records.
  Assistant-record count inflates this ~3× (one record per thinking / text /
  tool_use block of the same API response — the same fact `Parser`'s turn-leader
  logic exists for).
- `subagents` — number of files in the session's `subagents/` sidecar directory.
  A directory listing, so free.
- `max_context` — the **true max** over all assistant records. The earlier plan
  was "just the last assistant record, accepting missed pre-compaction peaks";
  measurement changed it: the scan reads the whole file anyway (for turns, title
  and recap), so the max costs nothing; **zero** `isCompactSummary` records
  exist across all 416 logs; and on the sample log the last record's total
  (76,597) was exactly the max.
- `size`, `mtime`, `path`, `project`.

### Scan performance rules (both from a memory-blowup warning)

- **Pre-filter before `JSON.parse`** with a cheap `line.include?` check. The
  hazard is a *single line* — one tool result can be megabytes — and the filter
  means such lines are read as a String and discarded, never turned into Ruby
  objects.
- **Never hold 50 scans in memory.** Write each result to the cache the moment
  it completes, so a crash mid-scan keeps what's already done.

### Caching

Keyed by **path + mtime + size**. An unchanged log is never reopened; an
appended-to log is rescanned. The cache lives in a **gitignored directory**
together with the generated HTML — Jess overruled a serve-from-memory proposal
on the grounds that the cache already puts private derived data on disk under a
gitignore entry, so writing the HTML beside it adds no exposure.

### Listing

The ~50 most recent sessions are taken **globally by mtime**, then grouped by
project; projects are ordered by their newest session.

### Import contract

1. Validate the name against the same `[a-z0-9]+(-[a-z0-9]+)*` slug rule
   `grab-example` enforces; refuse anything else and refuse to overwrite an
   unrelated existing example.
2. Copy `examples/<name>.jsonl` and any `examples/<name>/subagents/*`.
3. Shell out to **`bin/parse`** then **`bin/render`** scoped to that one name —
   following `bin/serve`'s precedent that a write invokes the real programs
   rather than patching files in place. Not a full `rake build`.
4. Respond with the built story's URL on `bin/serve`
   (`http://localhost:8080/<name>/`), gated on a `GET /api/health` probe of that
   server — the same trick `story.js` uses to decide whether to show the editor.
   When the probe fails, render "start `rake serve` to view" instead of a dead
   link. The importer never serves `out/` itself; that's the leak that drags it
   back into being two programs.

### Already-imported / Re-snapshot

Detected by reading the first line's `sessionId` out of each `examples/*.jsonl`
— the fixtures answer the question themselves, so no manifest exists to go
stale. Such a card shows its example name and its button becomes
**Re-snapshot**: overwrite in place under the existing name and rebuild, which
is behaviour `grab-example` already documents ("Re-run to re-snapshot").
Re-snapshot **merges sidecars** rather than no-opping on a main-log size match,
because a subagent that finished after the first snapshot is a new file a size
comparison can't see. A log written to within the last couple of minutes is
flagged **live** on the card, since that fixture is guaranteed incomplete.

### Deliberate non-decisions

- **No publishing guardrail.** Discovery across both config dirs means work
  sessions appear in a list whose Import button leads to a public repo. Jess's
  call: "MY work conversations are almost never about proprietary code."
  Grouping by project already puts the origin on screen as plain information.
  Do not reintroduce a warning.
- **Don't invent much new visual language.** Cards on `story.css`'s tokens,
  recap as the body. This is a candidate for the `design-feature-owner` TODO's
  attention later.

## Testing Decisions

A good test here asserts **external behaviour** — the numbers a card shows, the
files an import produced, the page that got built — never how the scan loop or
the HTML template is structured internally. The scan's *output* is contract; its
streaming shape is not, beyond the two performance rules, which are design
constraints rather than assertions.

**The seams, highest first:**

1. **`bin/check-importer` — the primary seam.** Plain HTTP against a real
   `bin/importer` process: fetch the listing, drive a real import, assert the
   fixture file, its sidecars, the `story.yaml` and the built page all appeared;
   then drive a Re-snapshot and assert the merge behaviour. Also assert the
   refusals — a bad slug, and a name that would overwrite an unrelated example.
   Runs against a **temp examples dir and a temp cache**, so it never touches
   the real fixtures; the small temp examples dir is also what makes the
   shelled-out parse/render fast enough to loop on. **No ferrum/Chrome**:
   `bin/check-modes` earns Chrome because keyboard and mode behaviour is
   unobservable from Ruby, but a `<form>` submitting is not.
   Prior art: **`bin/check-edit-api`**, which does exactly this shape for the
   authoring server's write path (temp edits dir, `Net::HTTP` PUTs, asserts
   sidecar + `story.yaml` + rendered page agree, plus the traversal and
   unknown-ref refusals).
2. **`ConversationStory::SessionScan` — minitest against the golden
   `examples/*.jsonl` fixtures**, giving the scanner the same golden-suite
   treatment `Parser` gets. Assert the derived numbers per fixture: turns as
   distinct `message.id`, subagent count, max context, session id, title,
   first prompt, recap-present-and-stripped and recap-absent.
   Prior art: **`test/parser_test.rb`**, which globs `examples/*.jsonl` and
   asserts per-fixture counts.

**`ConversationStory::Import` gets no seam of its own.** It's exercised through
`bin/check-importer` and through `bin/grab-example`, and it has no behaviour the
HTTP path can't observe. Fewer seams is better.

## Out of Scope

- **Serving `out/` from the importer.** It links to `bin/serve` and probes for
  it; it never becomes a second static server.
- **A route on `bin/serve`.** The served site is the published artifact; the
  importer is local authoring and must not ship.
- **Any change to the published site or to GitHub Pages deploy.** Nothing the
  importer writes goes to `out/` except by way of `bin/parse` / `bin/render` on
  a single example, exactly as `rake build` would.
- **A manifest of imported sessions.** The fixtures' own first-line `sessionId`
  answers it.
- **Compaction handling.** No log has ever compacted (zero `isCompactSummary`
  across all 416 logs), so `max_context` needs no special case for it.
- **A publishing/privacy warning on the page.** Explicitly declined.
- **Deleting or renaming existing examples**, including the unnamed
  `examples/4b0be952-…jsonl`. The importer prevents new instances of that
  failure; cleaning up the old one is separate.
- **New visual language beyond `story.css`'s tokens.** Left for
  `design-feature-owner`.
- **Reusing `Parser` for the scan.** Ruled out on cost.

## Further Notes

- The design note (`notes/2026-08-18-session-25-conversation-importer-design.md`)
  is the authority on the fourteen decisions and carries the measurements behind
  them. Read it before deviating.
- Three follow-through items are easy to forget and are called out in the note:
  the `Rakefile`'s explicit `*_SRC` lists, the CLAUDE.md rewrite, and the
  `.gitignore` entry.
- "Stdlib-first" applies: `bin/parse`, `bin/render` and `bin/site-index` must
  stay on default gems only. `bin/importer` is not one of those three, and it
  needs WEBrick, which is already declared in the `Gemfile` for `bin/serve`.
- `bin/grab-example`'s live-snapshot caveat — it warns when the log it copied
  was written to seconds ago — is the origin of the **live** flag on a card;
  keep the two consistent.
