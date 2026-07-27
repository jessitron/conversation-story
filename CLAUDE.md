# Conversation Story

Turn a Claude agent conversation log into an explorable, pretty static web page,
so Jess can narrate "how a conversation went" while the page shows it accurately.

Read `README.md` for the architecture and vision (the named "Mountains", constraints, limitations)
and `notes/plan.md` for the current design — especially the settled **Decisions**.
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
  record's blocks (thinking / text / tool_use) into their own cards, and
  inlining subagent stories, are **Mount Complete** work.
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
- **The queue detour shows on the message, not on a marker card.** Only the
  `enqueue` gets a card (it carries the queued payload). The bare
  `dequeue`/`remove` markers are hidden — they have no content of their own — and
  the event each one delivers is stamped `dequeued: true` / `removed_from_queue:
  true` instead, which the renderer draws as a badge. So a queued message is two
  cards, the enqueue and the delivered message, sharing a `queue:` link token.
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
  `meta.final_context` (last turn's context + output) is the header CONTEXT
  stat. Details in `notes/intermediate-schema.md`.
- A background task's result delivered mid-conversation as a `<task-notification>`
  XML blob gets its own kind, `task_notification` (not `user_message` — it's
  not something Jess typed); its summary is the extracted `<summary>` field.
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

- **Hand-written summaries are a sidecar, not an edit to `out/`** (session 11,
  Mount Malleable). `edits/<name>.yaml` maps event `ref` → summary;
  `ConversationStory::Edits` loads it and `bin/parse` overlays it onto the
  freshly parsed document, setting `summary` and stamping `summary_edited:
  true`. **`story.yaml` therefore stays 100% derived** — from the log AND the
  sidecar — so a parser improvement still reaches every un-edited card and no
  file needs a "don't overwrite me" lock. `summary_edited` beats the composed
  card faces (a `tool_call` otherwise ignores `summary`) and adds `data-edited`
  to the card.
- **`rake serve` is now `bin/serve`**, a WEBrick server that serves `out/` AND
  accepts `PUT /api/summary`. A save writes the sidecar and then **shells out to
  `bin/parse` and `bin/render`** — it never patches YAML or HTML in place, so
  the two-separate-programs rule holds and a reload always matches `rake build`.
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
- **Every write goes through one `submit(text)`** inside `showSummaryEditor` —
  Save, Revert and undo are all the same request, differing only in the text.
  `submit` captures the outgoing hand-written line first and, if the response
  shows it was discarded, offers an `undo` in the status area. So undo needs no
  server support and no history: it's just another save of the old text.
- Verify the write path with **`bin/check-edit-api`** (starts `bin/serve` against
  a temp edits dir, saves + reverts, asserts sidecar/story/page all agree, and
  checks the path-traversal and unknown-ref refusals). `bin/screenshot` takes a
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
detail pane and its highlighted causal chain are in the shot (the region above
the target screenshots blank — a headless repaint artifact, not a page bug).
`bin/screenshot .` shoots the landing page (`out/./index.html` resolves).

**`TODO.md` is the open-threads list**, grouped by mountain. The big ones:
step-through navigation and a presenter mode (Mount Interactive); showing that
an assistant turn made tool calls, plus block-splitting and subagent nesting
(Mount Complete); self-hosting the fonts (Mount Beautiful); and editing a card's
summary live on the page (Mount Malleable). The session-7 note has more context
on the linking work.
