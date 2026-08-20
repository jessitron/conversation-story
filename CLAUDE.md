# Conversation Story

Turn a Claude agent conversation log into an explorable, pretty static web page,
so Jess can narrate "how a conversation went" while the page shows it accurately.

## Seamap

This repo's seamap — the North Star, Mountains, and where work is recorded —
lives in `SEAMAP.md`. Orient, capture, and log proactively; use `drop-buoy` to
capture work without derailing.

Read `README.md` for the architecture (constraints, limitations, how to run
things) and `notes/plan.md` for the current design — especially the settled
**Decisions**.
The **intermediate schema** (the `story.yaml` contract) has its own file,
`notes/intermediate-schema.md`. For the **page look & feel**, see
`assets/design-prototype.html` (a static art-deco mockup with sample cards) plus
`notes/2026-07-20-session-2-design-prototype.md` and
`notes/2026-07-20-session-5-prototype-cleanup.md`.

The prototype's CSS/JS now live in **`assets/story.css` + `assets/story.js`** (the
prototype links them, so it can't drift from what ships). So "reproduce the design"
is mostly: **reuse `assets/` as-is and generate only the per-event card HTML** —
each card is `<a class="card k-KIND" id="<ref>" href="#<ref>">` carrying a
`<template class="detail">`; the URL fragment drives selection (deep-linkable).

## Event references

Jess refers to individual events as `<example-name>:<line>`, e.g.
`episode-8-before:104` — the example's directory/file name, a colon, and the
1-indexed line number in that example's main `.jsonl` log (matches `source.line`
in the generated `story.yaml`). To look one up: find the `story.yaml` entry
whose `ref:` matches, or `sed -n '<line>p' examples/<example-name>.jsonl`.

**A ref is also the card's HTML id and URL fragment**, so linking Jess to an
event is pure string concatenation — no lookup, no counting:

    http://localhost:8080/<example-name>/#<example-name>:<line>

(Session 10 change. Cards used to be numbered `#event-N` over the *visible*
events, which drifted from log line numbers — `episode-8-before:174` was
`#event-89` — and made "link me to that" a scripting job. Anchors built before
this change are dead links; nothing aliases them.) Two things follow:

- **Hidden events have no card**, so their refs aren't linkable — the fragment
  won't resolve and `story.js` falls back to the default card. That's by design.
- **The colon is a CSS pseudo-class introducer.** Resolve fragments with
  `getElementById`, never `querySelector('#' + id)`, and don't add id-based CSS
  selectors. `bin/check-anchors [example] [line]` drives a real headless browser
  to assert a ref fragment still selects its own card (and reports how much of
  the causal chain lit up); run it after touching selection code. `bin/check-modes`
  is the same headless-Chrome pattern applied to modes and keyboard navigation —
  run it too after touching `story.js`'s selection, mode, or narrate logic.

## Conventions

- **Ruby 4**, managed via **asdf**, pinned in `.tool-versions` (asdf's native
  file — there is no `.ruby-version` here, and rbenv isn't in play). Without
  that file asdf falls back to `~/.tool-versions`, which differs per machine.
  CI pins the same major in `.github/workflows/pages.yml` — bump both together.
- **Stdlib-first, with a `Gemfile` for the one exception.** `json`/`yaml`/`erb`
  are real default gems; `bin/parse`, `bin/render` and `bin/site-index` need
  nothing else. But Ruby 4.0 **unbundled webrick**, which `rake serve` requires,
  so it's declared — along with `rake` and `minitest`, which ship with Ruby only
  as *bundled* gems (the category webrick just fell out of). `Gemfile.lock` is
  committed and CI runs `bundle exec` with `bundler-cache: true`, so CI and
  Jess's machines resolve identically. No Rails.
  **"Stdlib-first" is about which programs stay dependency-free, not a ban on
  gems.** The property worth protecting is that `bin/parse`, `bin/render` and
  `bin/site-index` need nothing but default gems — that's what lets CI skip
  `bundle install` for a build. Outside those three, a gem that earns its place
  is welcome; reach for one when it's the better tool (session 12 added
  `ferrum` for exactly that reason). Don't harden this bullet into "add no
  gems" — that reading has already been wrong once, and Jess's answer was
  "there's nothing wrong with gems."
  `notes/2026-07-27-session-12-ruby-4-and-gemfile.md` has
  the default-vs-bundled-vs-dropped gem taxonomy, why `.gitignore` carries a
  `!.tool-versions` negation, and how to tell a hand-installed gem from one that
  shipped with Ruby. The Gemfile's `:test` group exists because of **`ferrum`**
  (Mount Interactive): `bin/check-modes` drives real Chrome over the DevTools
  Protocol to test keyboard/mode behavior no Ruby-side test can see, and pure
  Ruby with no Node/Selenium/driver binary is exactly the "stay boring" shape
  this project wants for a test dependency.
- **The schema is the contract.** Known event kinds store only _named_ fields —
  no raw source-JSON blob, and the renderer reads the schema, never the original
  log. Only the `unknown` fallback kind keeps `raw`, so
  unrecognized record types aren't silently lost (a README constraint).
- **`examples/` are golden fixtures.** Test the parser against every conversation log in there.
  **There are two doors in.** `bin/importer` (`rake importer`, port 8081,
  `PORT=`-overridable) is the BROWSER one and the place to *choose* a fixture: a
  fourth program, local-only, that lists the ~50 most recent sessions from both
  config dirs and all projects — taken globally by mtime, then grouped by
  project, projects ordered by their newest session — as cards carrying the AI
  title, the first plain-string prompt, the recap **in full**, turns, subagents,
  max context, size and date. It serves neither `out/` nor anything published;
  its page and `SessionScan`'s per-session cache live in the gitignored
  `.importer/`, because everything derived from Jess's conversation logs is
  private and this repo is public. Deliberately no publishing warning on the
  page (Jess's call, session 25 decision 10); don't add one.
  **As of tickets 04/05 it is the PRIMARY door**: each card has a name field
  (pre-filled with a slug of the title, `Import.slugify`), a live
  `examples/<name>.jsonl` preview, and pressing **Import** copies the log (plus
  any `subagents/` sidecars) via `ConversationStory::Import.copy` and shells out
  to `bin/parse` + `bin/render` for that ONE name — never a full `rake build`,
  the same restraint `bin/serve`'s hand-edit path uses. A bad slug or an attempt
  to overwrite an *unrelated* existing example under the same name is refused
  (`400`, plain HTML response — the whole thing is one `<form method="post">`,
  so `bin/check-importer` drives it with `net/http` alone, no browser needed).
  A session already in `examples/` is recognized by reading each fixture's own
  first-line `sessionId` (`Import.existing_examples` — no manifest to go stale)
  and its button reads **Re-snapshot**: same name, sidecars MERGED in rather
  than the directory replaced, because a subagent that finished after the first
  snapshot is a new file a size check can't see. A log written to in the last
  couple of minutes (`Import::LIVE_SECONDS`) wears a **live** badge — the
  harness is still appending, so that fixture is guaranteed incomplete.
  `--examples`/`--out`/`--config-dir`/`--serve-port` on `bin/importer` point the
  whole pipeline at temp directories, which is how `bin/check-importer` exercises
  a real import without ever touching Jess's actual fixtures.
  **`bin/grab-example <session-id> <name>`** is the CLI door — scriptable, needs
  no browser, still there for when a terminal is faster than a page
  (`--list` shows the newest 50 sessions across both config dirs with each
  one's first prompt); it copies the main log plus any `subagents/` sidecars.
  Both doors go through `ConversationStory::Import` so they can't drift. Grabbing
  the session you're in copies a *live* file, so the fixture stops mid-session —
  re-run to re-snapshot. Every example is ~1–7 MB and its built page is committed too, so
  they're not free. Tests glob `examples/*.jsonl`, so a new log runs the whole
  golden suite immediately — expect newer logs to carry record types the older
  fixtures never had.
- **`out/` is committed** (not gitignored); examples ship with the repo and can
  be pushed to `gh-pages` when Jess chooses.
- **`notes/`** holds design docs and session notes, tracked in git so they follow
  across Jess's computers. Put plans and learnings here, not in machine memory.

## Status

**Mount Minimal is climbed** (parse → render → serve, end-to-end on the real
example logs). Parse and render are **two separate programs** (`bin/parse`,
`bin/render`) over real `lib/` classes now; the `Rakefile` is the task runner
that knows the dependency between them (and re-runs a phase when its program's
source changes — not just when `story.yaml` is stale). The remaining mountains
are named in README.md and worked from `TODO.md`, which groups every open item
by mountain. Mountains are **named, not numbered** — don't reintroduce numbers.

- **Granularity: one event per JSONL record** (main log only). The golden test
  asserts `event_count == line count` (224 / 154). Splitting an assistant
  record's blocks (thinking / text / tool_use) into their own cards is still
  **Mount Complete** work.
- **Subagents are inlined as a nested document** (session 15). An `Agent`
  tool_call becomes kind `subagent` and its result kind `subagent_result`; the
  subagent's log is parsed by the **same `Parser`, recursively**, and hangs off
  the call as `subagent.meta` + `subagent.events` — NOT spliced into the flat
  `events` list (which stays one-per-line of the main log). The hinge is
  `toolUseResult.agentId`, not the tool's name. The renderer draws the nested
  events as full cards in a `.subactions` block right after the subagent card,
  **expanded by default** — seeing the work an agent did is the point, and
  shipping it collapsed to "protect the main narrative" was corrected;
  the caret is for quieting a subagent down. `story.js`'s caret toggles it,
  `NAV()` is the "cards Jess can step through" list that excludes collapsed ones,
  and a link to a nested ref expands what it needs. **A beat never stops inside a
  subagent**: since session 20 that rule lives in the parser (no `beat` on a
  nested event) rather than in `story.js`'s old `isMessage`, so a subagent's
  whole story still reveals as one flurry within the beat that spawned it. **Anything that counts or looks up cards must walk the
  tree**: `Renderer#all_visible_events`, `test/story_events.rb`, `Edits#apply`,
  `bin/serve`'s `event_for`. `notes/2026-07-28-session-15-subagents.md` and the
  Subagents section of `notes/intermediate-schema.md` have the rest.
- Parser maps each record `type` → a schema `kind`; `user` splits into
  `user_message` vs `tool_result` by content shape; `last-prompt` intentionally
  hits the `unknown` fallback (keeps `detail.raw`). Renderer maps schema `kind` →
  the design's CSS kind class and escapes all content.
- `bin/render` copies `assets/` **and** `images/` next to the pages; pages link
  them with relative `../assets/…` / `../images/…`.
- **Hidden events**: the parser flags harness-bookkeeping records with
  `hidden: true` (still emitted, so `event_count` == line count); the renderer
  skips them and its "events" stat counts only visible ones. episode-8-before:
  224 → 109 visible / 115 hidden; episode-8-after: 154 → 72 visible. Hidden set +
  the deliberately-kept-visible set (`queued_command`, `task_reminder`, and
  `queue_operation` **enqueue**s) live in `parser.rb`'s `HIDDEN_*` constants and
  are explained in `notes/2026-07-20-session-6-hidden-events.md`.
  Two newer record types joined the hidden set: **`agent-name`** maps to the
  existing `ai_title` kind (in the one example that has them, all 5 records
  carry the identical string that session's `aiTitle` does; across 2290 in
  `~/.claude-work/projects` they hold only `type`/`agentName`/`sessionId`, no
  timestamp — it is the sidebar label being rewritten, not a subagent name),
  and **`agent-setting`** gets its own always-hidden `agent_setting` kind (6 in
  that example, 3028 in the corpus, and the value is the literal `"claude"` in
  every one — zero variance, so it records no change at all). Hiding them took
  4b0be952… from 75 visible to 64; `event_count` stays 109.
- **The queue detour shows on the message, not on a marker card.** Only the
  `enqueue` gets a card (it carries the queued payload). The bare
  `dequeue`/`remove` markers are hidden — they have no content of their own — and
  the event each one delivers is stamped `dequeued: true` / `removed_from_queue:
  true` instead, which the renderer draws as a badge. So a queued message is two
  cards, the enqueue and the delivered message, sharing a `queue:` link token.
  An enqueue's **summary is the payload alone** — the operation is a badge
  (`enqueue`) and the gutter already says Queue, so a "Queue enqueue:" prefix
  only pushed the interesting words past the card's two-line clamp.
- **`status`** is how a background job ended, read from `<status>…</status>`
  inside a `<task-notification>` blob (so: a delivered `task_notification`, a
  queue `enqueue` of one, the `queued_command` attachment that redelivers it).
  Read the tag, not the wording of `<summary>` — the tag is the harness's own
  word for it and doesn't vary. `status: failed` renders as the same Error badge
  a failed `tool_result` wears, so "this didn't work" looks the same wherever
  the news arrives.
- **Assistant records are classified by their one content block**, not always
  `assistant_message`: `tool_use` → `tool_call` (with named `tool.name`,
  `tool.use_id`, `tool.input`, `tool.primary_arg`), `thinking` → `thinking`,
  else `assistant_message`. Every assistant record in the example logs carries
  exactly one block — this is still one-event-per-line, not real
  block-splitting. `tool_result` events carry named `tool.{use_id,is_error,
  duration_ms,result}` pulled from the record's content block + `toolUseResult`.
- **Tokens belong to a TURN, not a record** (session 13). One API response is
  split across several records — thinking, text, one per `tool_use` — sharing
  `message.id`, and **each repeats the whole turn's `usage`**. The parser emits
  `links.message_id`, elects one **`turn_leader`** per turn (the
  `assistant_message` record, else the turn's first record — 7 of 33 turns in
  episode-8-before are bare `tool_use`), and puts the derived `context` /
  `added` / `cumulative_context` only there. Attribute per record instead and a
  running total silently triples while the page still looks fine. `message_id`
  is deliberately **not** a `link_ids` token: that drives the board-wide
  highlight, and lighting a whole turn every selection would drown out the
  tool_call↔tool_result chains. A `tool_result` carries
  `tokens.{result_chars,estimated_input}` — an **estimate** (length /
  `Parser::CHARS_PER_TOKEN`, 3.5), because `usage` exists only on assistant
  records and 0 of 32 inter-turn gaps hold a result by itself. It is not named
  `input` on purpose, and the renderer always prints the `≈` and the caveat.
  `meta.total_tokens` — every turn's context + output, each turn counted once —
  is the header **Tokens** stat (1.21M for episode-8-before). It's token *use*,
  not a context size, which is why the stat isn't labelled Context: most of it
  is the same context re-sent and cache-read each turn, and the biggest context
  the conversation ever held was 45k. Details in
  `notes/intermediate-schema.md`.
- **Per-card context attribution, and "dark matter"** (session 22). A turn's
  `cache_creation` isn't all new content — some of it can be OLD content
  getting re-paid because it fell out of cache (TTL lapse, or the breakpoint
  walked past the 20-block lookback, session 21). `rewrite_overhead = max(0,
  previous_turn.context - cache_read)` isolates that; `context_so_far =
  cache_read + rewrite_overhead` should equal the **previous** turn's
  `context` exactly — a real identity, checked against episode-8-before, not
  just an estimate — and `new_content = cache_creation - rewrite_overhead` is
  what's genuinely new. The chars-based `≈` estimate (`Parser::ESTIMATE_KINDS`)
  is no longer tool_result-only — every `user_message`/`coordinator_message`/
  `task_notification`/`queue_operation` gets one too. Turn 1's `added` bills
  the system prompt + tool schemas + first message as one cache write with no
  line-item for the system/tools portion (caching hashes the whole `tools ->
  system -> messages` prefix); `system_prompt_estimate` on the first
  `user_message` names that remainder rather than measuring it. Subtracting
  the previous turn's real `output` plus every intervening event's estimate
  from `new_content` should leave nothing — when it doesn't, that's "dark
  matter": real, billed context with no card whose content explains it.
  Attributed to any Underspecified attachment event in the window
  (`deferred_tools_delta`/`mcp_instructions_delta`/`skill_listing` — un-hidden
  this session, since their own logged content is a name list, not the real
  schema text billed) as `dark_matter_estimate`; if the only candidate is a
  `hook_success`, the parser logs a warning instead of guessing — running it
  against the examples found dark matter on nearly every turn of the two
  `episode-8` logs (up to 2549 tokens), which ran a hook on every tool call,
  and zero in three newer logs that only run a session-start hook. Display of
  Underspecified events and dark-matter shares is still unstyled — see
  `notes/2026-08-11-session-22-dark-matter-and-underspecified-events.md` and
  TODO.md's `underspecified-events-display`.
- A background task's result delivered mid-conversation as a `<task-notification>`
  XML blob gets its own kind, `task_notification` (not `user_message` — it's
  not something Jess typed); its summary is the extracted `<summary>` field.
- A prompt's **mode** is a field the prompt record carries (`permissionMode`,
  next to `promptId`) — read it there, never from the standalone `mode` records,
  which hold the UI state at write time and lose a switch that was undone before
  the turn ended. The comment on `Parser::TYPE_TO_KIND` has the measurement, and
  `notes/2026-07-28-session-16-examples-and-prompt-mode.md` has how we found out
  the hard way (plus two gotchas: self-referential fixtures inflate string greps,
  and `bin/screenshot` shot blank for a card deep in a long page — fixed in
  session 18, see the screenshot paragraph below).
- Inside a **subagent's own log**, a `SendMessage` delivery from the
  orchestrating agent arrives as a plain `role: user` record too — same shape
  as a real prompt, but it isn't Jess. The harness prefixes it with a literal
  `"The coordinator sent a message while you were working:"`, which is the
  only signal distinguishing it; `Parser::COORDINATOR_MESSAGE_PREFIX` matches
  it into its own kind, `coordinator_message`. Styled like the conversation
  kinds (paper background, summary-size text) but in its own gray and
  right-aligned like `k-user` — arriving from outside the subagent's own
  thread — and always attributed to "Claude" via `who_for`'s early return
  (never the subagent's own name). `mtg-tabletop-plan` is the example that has
  these; `notes/2026-07-28-session-17-coordinator-message.md` has the rest,
  including the background/async-subagent (`status: async_launched`) and
  `SendMessage` mechanics that make coordinator messages possible.
- **`beat` says where narration stops** — `n` / `p` / shift+arrow step between
  beats. The parser sets `beat: true` on main-thread `user_message` /
  `assistant_message` (`Parser::BEAT_KINDS`) and **never inside a subagent**:
  the recursive parse is `Parser.new(path, nested: true)`, which suppresses it,
  because a beat never stops inside a subagent. The renderer emits
  `data-beat="true"` and `story.js`'s `isBeat` reads that attribute — it used to
  sniff `k-user`/`k-assistant` plus "not in `.subactions`", the same set with no
  way to override it. Jess overrides per card in edit mode (a checkbox that
  saves on toggle, `PUT /api/beat`), stored in `edits/<name>.yaml`'s `beats:`
  section; `false` **deletes** the key, so "not a beat" has one shape. The
  detail pane shows a 🥁 cue in every mode; the ▸ marker paints only in edit
  mode, on `.card::before` — **not** the gutter (a `.gutter::before` version at
  the design's own negative offset landed exactly on the accent border, same
  pixel and same color, and fired invisibly; see `story.css`'s comment above the
  rule). See `notes/2026-07-28-beat-flag-design.md`.
- **`ConversationStory::Markdown`** (`lib/conversation_story/markdown.rb`) is a
  small, safe markdown-subset renderer used for prose detail text
  (user/assistant messages, reasoning). Escapes raw text before any markdown
  substitution, so no input can inject real HTML.
- **Causal-chain linking**: the parser tags related events (a `tool_call` and
  its `tool_result`; a queue `enqueue` and the message it delivers; the
  `task_notification` it eventually delivers; the originating background
  `tool_call`) with shared
  tokens in `link_ids`. The renderer emits them as a `data-link` attribute;
  `story.js` highlights every card sharing a token with the active one
  (`.card.related`, styled **identically** to `.active` — only the leader line to
  the detail pane is selection-only). See
  `notes/2026-07-20-session-7-tool-calls-and-linking.md`.
- **Two voices in the detail pane** (session 9): PROSE (`.d-text` / `.d-markdown`
  — body font on paper) vs MACHINE (`pre.code` — mono on navy, and it *wraps*).
  Tool INPUT, tool RESULT, notification blobs and raw records all go through
  `Renderer#machine_html` so they look the same. Don't reintroduce a third look.
- **Card alignment, vertically**: the card grid is **`align-items: start`**, and
  `.k-user`/`.k-assistant` are the only kinds that opt back into `baseline` —
  they're the only ones whose summary size differs from the gutter label's, and
  their one-word labels can't wrap. Don't make baseline the general rule again: a
  wrapping label moves the row's baseline (an `inline-block` `.kind` reports its
  *last* line's), which is how "Subagent Result" pushed one card's summary 18px
  down in session 15.
- **Card alignment**: `--card-inset` (`:root`) is the distance from a card's outer
  edge to its content, accent border included; `.card` derives `--card-pad` from
  it and `--card-accent`. A card wanting a heavier accent redefines
  **`--card-accent`** (see `.k-assistant`) — never `--card-pad`.
- **Three modes** (session 12): `body.mode-explore|edit|narrate`, a header
  switch (`#mode-switch`), and `?mode=` in the URL — explore is the default and
  stays out of the URL. Edit un-hides only when the `/api/health` probe answers.
  Focus mode is gone. Keyboard: unshifted arrows move one card, shifted move one
  user/assistant message; `n`/`p` are shift-arrow aliases in narrate; `x`/`e`/`N`
  switch modes; Escape collapses the sidebar first — then, in narrate, exits
  to explore, otherwise clears the selection (narrate never clears it). In
  narrate, `.revealed` is a prefix of the cards and the newest one is the
  selection.
  `bin/check-modes` drives all of it with real keystrokes in headless Chrome —
  **read the trap list at the top of that script before adding a scenario**
  (colon ids make `at_css("#"+id)` throw; a real click on a far-down card
  misses unless you center-scroll first; `[:Shift,'n']` is not `"N"`; the page
  always loads with a card already selected, so never hard-code an index where
  you need an *un*selected card). `notes/2026-07-27-session-12-mount-interactive.md`
  explains each one, why the sidebar became sticky state, and the two
  deliberate deviations from the design note (case-folded `n`/`N`, plain arrows
  scroll too) that are easy to "fix" back by mistake.

Run things with `rake parse` / `render` / `site` / `build` / `serve` / `test`
(all examples by default; `LOG=`/`PORT=` env vars to scope). See README.md.
Note: the Rakefile's `RENDER_SRC`/`PARSE_SRC`/`SITE_SRC` lists source files
explicitly (not a glob) — a new `lib/` file needs adding there or `rake build`
won't notice it changed.
To run a single test file (`rake test` always runs the whole
`test/**/*_test.rb` glob): `ruby -Ilib -Itest test/parser_test.rb`.

- **Hand edits are a sidecar, not an edit to `out/`** (session 11, Mount
  Malleable; session 20 added the second section). `edits/<name>.yaml` holds
  two named sections keyed by event `ref`: `summaries:` (rewritten card text)
  and `beats:` (where narration stops — see the `beat` bullet above).
  `ConversationStory::Edits` loads both and `bin/parse` overlays them onto the
  freshly parsed document — a summary sets `summary` and stamps
  `summary_edited: true`; a beat override sets `event["beat"] = true` or
  **deletes** the key for `false`, converging on the same shape the parser
  emits. **`story.yaml` therefore stays 100% derived** — from the log AND the
  sidecar — so a parser improvement still reaches every un-edited card and no
  file needs a "don't overwrite me" lock. `summary_edited` beats the composed
  card faces (a `tool_call` otherwise ignores `summary`) and adds `data-edited`
  to the card; a beat override gets no such stamp — there's no composed face
  to beat and nothing to mark.
- **`rake serve` is now `bin/serve`**, a WEBrick server that serves `out/` AND
  accepts `PUT /api/summary` and `PUT /api/beat`. A save writes the sidecar and
  then **shells out to `bin/parse` and `bin/render`** — it never patches YAML
  or HTML in place, so the two-separate-programs rule holds and a reload
  always matches `rake build`.
  It binds **`localhost`, not `127.0.0.1`**, on purpose: with the v4 address
  alone, a stray server bound to the wildcard answers `::1` first and the page
  silently talks to it (static files fine, `/api/health` 404, editing
  mysteriously off — this cost real time in session 11).
- **The editor is progressive enhancement.** `assets/story.js` probes
  `GET /api/health` and only builds the Summary box when the local server
  answers *and* the page is in edit mode — `showSummaryEditor` checks both.
  The ✎ edited marker isn't gated on either: it paints in every mode, on the
  published site too, by design ("this line is Jess's, not the parser's" is
  part of the story, not an authoring affordance). The published Pages site
  runs the same JS with nothing to write to. Don't add a build flag.
  It sits in the **gutter beside the actor**, not appended to `.summary` where it
  read as the sentence's last character. Always on the card's inner edge, facing
  the body: `.who::after` normally ("Claude ✎"), `.who::before` for the
  right-aligned kinds `k-user`/`k-coordinator` ("✎ Jess"). A new right-aligned
  kind needs adding to both of those rules.
- **The detail pane always leads with the summary.** `showSummary` (story.js)
  puts the editable box there in edit mode and, in every other mode, the same
  line as plain selectable text plus a copy chip — one or the other, never both.
  The card face shows it too, but a card is an `<a>`, so dragging across it
  starts a link drag instead of a text selection; the detail pane is where Jess
  copies a summary from. `bin/check-modes` asserts the read-only version matches
  the card face.
- **Every write goes through one `submit(text)`** inside `showSummaryEditor` —
  Save, Revert and undo are all the same request, differing only in the text.
  `submit` captures the outgoing hand-written line first and, if the response
  shows it was discarded, offers an `undo` in the status area. So undo needs no
  server support and no history: it's just another save of the old text.
- Verify the write path with **`bin/check-edit-api`** (starts `bin/serve` against
  a temp edits dir, saves + reverts both summaries and beats, asserts
  sidecar/story/page all agree, and checks the path-traversal and unknown-ref
  refusals). `bin/screenshot` takes a
  full `http://…` URL with `?mode=edit` now — the only way to *see* the editor,
  since `file://` can't reach the API and explore mode never builds the box.

- **The site root has a landing page**, `out/index.html`, written by a third
  program: `bin/site-index` (reads every `out/*/story.yaml`, never the logs —
  same contract rule as the renderer). It lists one card per story with the
  same Events / Duration / Model labels the story's own header shows, by
  calling `Renderer#subtitle`/`#duration`/`#model_label` — those three are
  `public` on the renderer precisely so the landing page can't drift from the
  page it links to. Its styles are `assets/index.css`, built from
  `story.css`'s tokens and loaded after it; the story pages don't link it.
  `bin/site-index` also drops a `.nojekyll` in the site root.
- **Deploy: `.github/workflows/pages.yml`** publishes to GitHub Pages on every
  push to `main` — `rake test`, `rake build`, then upload `out/`. The Pages
  source is "GitHub Actions", *not* a branch, because branch-based Pages can
  only serve a repo root or `/docs` and the site root here is `out/` on `main`.
  There is no `gh-pages` branch. Live at
  <https://jessitron.github.io/conversation-story/>.

To *see* a CSS change: `bin/screenshot [example] ['#<ref>'] [out.png]` shoots a
built page with headless Chrome. Passing a fragment selects that card, so its
detail pane and its highlighted causal chain are in the shot.
`bin/screenshot .` shoots the landing page (`out/./index.html` resolves).
Arguments after the first are sorted by shape, not position — a `.png` is the
destination, anything else is the ref — so you can skip the fragment.

**It shoots a viewport-sized clip around the target card, and that is the whole
point of the design** (session 18). It used to be bash around
`chrome --screenshot`, and it returned a blank sheet of paper for any card that
wasn't near the top — which was written off for several sessions as "a headless
repaint artifact above the target". It was not: with a deep fragment the DOM is
perfect (right card `.active`, scrolled to it, card at y=911 in the viewport)
and the capture is still blank, from scrollY=10,000 on. **Headless Chrome only
rasterizes tiles around the current scroll position**, so a viewport capture of
a programmatically scrolled page has nothing in it, and neither
`--headless=new` nor CDP `Page.captureScreenshot` changes that. What works is
an explicit clip rectangle in page coordinates (ferrum's `area:`) — but **the
clip must overlap the current viewport**: clip deep while scrolled to the top
and it's blank again, and that same rule is why the static header vanished from
a shot taken 150px down. Hence: position the page (top of page if the card fits
on the first screen, so the header and its stats stay in frame; otherwise
`scrollIntoView({block:'center'})`), then clip *exactly* the viewport. Don't
"simplify" this back to a plain screenshot call.
A fragment that resolves to no card now **warns on stderr** instead of quietly
shooting the default selection — hidden events have no card by design, and a
ref off by one line looked exactly like a CSS change doing nothing.
**`bin/check-screenshot`** guards all of it (deep card, mid card, no fragment,
landing page, unresolvable ref); it detects blankness by file size, since a
flat-colour PNG is ~9.6 KB where a real shot is 200–450 KB.

**`TODO.md` is the open-threads list**, grouped by mountain. The big ones:
step-through navigation and a presenter mode (Mount Interactive); showing that
an assistant turn made tool calls, plus block-splitting and subagent nesting
(Mount Complete); self-hosting the fonts (Mount Beautiful); and editing a card's
summary live on the page (Mount Malleable). The session-7 note has more context
on the linking work.

## Agent skills

### Issue tracker

Local markdown under `.scratch/<feature>/` — separate from `SEAMAP.md`/`TODO.md`,
which remain this repo's own tracking system. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five: needs-triage, needs-info, ready-for-agent, ready-for-human,
wontfix — plus `done`, which we added because the five canonical roles are all
*open* states and a markdown tracker has no close of its own.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at repo root (don't exist yet —
created lazily by `/domain-modeling`). See `docs/agents/domain.md`.
