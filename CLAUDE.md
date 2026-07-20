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

Schema designed, **page design prototyped** (`design-prototype.html`), and the
**pipeline is scaffolded**. Parse and render are **two separate programs**
(`bin/parse`, `bin/render`) over stub `lib/` classes; the `Rakefile` is only the
task runner that knows the dependency between them. Next step per
`notes/plan.md`: fill in the parser skeleton + golden-fixture test, building
Mountain 1 (every event as an identical card) end-to-end first.

Run things with `rake parse` / `render` / `build` / `serve` / `test` (all
examples by default; `LOG=`/`PORT=` env vars to scope). See README.md.

Still TODO before/with the renderer: **self-host the fonts** (Tenor Sans / Sen /
Cascadia Code) into `assets/fonts/` with `@font-face` in `story.css`, replacing the
CDN `<link>` the prototype still uses; and `bin/render` must **copy `assets/` →
`out/assets/`** each build. See the session-5 note for the full open-threads list.
