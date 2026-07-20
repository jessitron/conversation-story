# Conversation Story

Turn a Claude agent conversation log into an explorable, pretty static web page,
so Jess can narrate "how a conversation went" while the page shows it accurately.

Read `README.md` for the architecture and vision (the four "Mountains", constraints, limitations)
and `notes/plan.md` for the current design — especially the settled **Decisions**.
The **intermediate schema** (the `story.yaml` contract) has its own file,
`notes/intermediate-schema.md`. For the **page look & feel**, see
`design-prototype.html` (a static art-deco mockup with sample cards) plus
`notes/2026-07-20-session-2-design-prototype.md` and
`notes/2026-07-20-session-5-prototype-cleanup.md`.

The prototype's CSS/JS now live in **`assets/story.css` + `assets/story.js`** (the
prototype links them, so it can't drift from what ships). So "reproduce the design"
is mostly: **reuse `assets/` as-is and generate only the per-event card HTML** —
each card is `<a class="card k-KIND" id="event-…" href="#event-…">` carrying a
`<template class="detail">`; the URL fragment drives selection (deep-linkable).

## Conventions

- **Ruby**, managed via rbenv/asdf (`.ruby-version`). **Stdlib-first**
  (`json`, `yaml`, `erb`); only dev dep is `minitest`. No Rails.
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

**Mountain 1 is done** (parse → render → serve, end-to-end on the real example
logs). Parse and render are **two separate programs** (`bin/parse`, `bin/render`)
over real `lib/` classes now; the `Rakefile` is the task runner that knows the
dependency between them (and, as of Mountain 1, re-runs a phase when its
program's source changes — not just when `story.yaml` is stale).

- **Granularity: one event per JSONL record** (main log only). The golden test
  asserts `event_count == line count` (224 / 154). Splitting an assistant
  record's blocks (thinking / text / tool_use) into their own cards, and
  inlining subagent stories, are **Mountain 2+**.
- Parser maps each record `type` → a schema `kind`; `user` splits into
  `user_message` vs `tool_result` by content shape; `last-prompt` intentionally
  hits the `unknown` fallback (keeps `detail.raw`). Renderer maps schema `kind` →
  the design's CSS kind class and escapes all content.
- `bin/render` copies `assets/` **and** `images/` next to the pages; pages link
  them with relative `../assets/…` / `../images/…`.

Run things with `rake parse` / `render` / `build` / `serve` / `test` (all
examples by default; `LOG=`/`PORT=` env vars to scope). See README.md.

Still TODO: **self-host the fonts** (Tenor Sans / Sen / Cascadia Code) into
`assets/fonts/` with `@font-face` in `story.css`, replacing the CDN `<link>` the
prototype + generated pages still use; the **deterministic HTML well-formedness
check** (plan.md TODO); then **Mountain 2** (interactivity: block-level cards,
richer per-kind detail, subagent nesting). See the session-5 note for the full
open-threads list.
