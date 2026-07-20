# Session 2026-07-20 (5) — prototype cleanup, deep-linkable cards, asset extraction

## What we did

Cleaned up `design-prototype.html` *before* it becomes the ERB template's source
of truth, so the mess doesn't get baked into the renderer. Four commits:

- `c923e99` — CSS tidy + cards to static HTML
- `8eea58b` — delegated click listener + a well-formedness TODO
- `42e38bc` — deep-linkable `<a>` cards
- `5221f92` — CSS/JS extracted to `assets/`

## Decisions settled

- **CSS tokens = shared concepts only.** Added semantic tokens (`--surface-raised`,
  `--navy-rgb` for alpha shadows, `--gutter-w`, `--olive`, `--code-bg`,
  `--code-ink`) but **deliberately left one-off tuning numbers** (individual font
  sizes, letter-spacings) as literals. Tokenizing those makes the file *harder* to
  nudge, not easier. "Easy to change" = tokenize concepts, leave local tuning local.
- **One kind→color table.** All seven `.card.k-* { --kind: … }` assignments sit
  together, above the per-kind treatment (fixes an old read-before-define). Recolor
  a kind = one line.
- **`.deco` helper** = the "Tenor Sans + uppercase" label voice, shared by the six
  heading-flavored labels; each site keeps its own size/color/letter-spacing.
- **Cards are static HTML now (option b), not JS-injected.** The `#cards` block is
  the future **event-card partial**; each card carries its drill-in markup in a
  `<template class="detail">` = the **detail partial**. `story.js` is
  **interactivity only** and reads everything from the DOM (no event data in JS).
- **Cards are deep-linkable anchors:** `<a class="card …" id="event-N"
  href="#event-N">`.
  - The **URL fragment is the source of truth** for selection → every event is
    shareable/bookmarkable.
  - Click writes the fragment via `history.replaceState` (shareable) **without** the
    native jump-to-anchor scroll — detail shows in the sticky sidebar. Loading or
    hand-editing `#event-N` selects *and* scrolls (center). No/unknown hash →
    default to the assistant card (page never empty).
  - Modified clicks (⌘/ctrl/…) fall through so open-in-new-tab works. `replaceState`
    is in a try/catch because some browsers block history writes on `file://`.
  - **Why `<a>` and not `<button>`:** anchors are natively focusable +
    Enter-activatable (keyboard a11y for free) *and* legally wrap block content
    (transparent content model). A `<button>` may **not** contain `<div>` children —
    invalid HTML — so it was ruled out. Added a `:focus-visible` outline.
  - One delegated click listener on `#cards` (not one per card).
- **Shared assets live in top-level `assets/`** (`story.css`, `story.js`), not
  `lib/`. They're inert static files shared by every page (only card HTML + header
  stats differ per page); the build copies `assets/` → `out/assets/`
  (`FileUtils.cp_r`). ERB templates stay in `lib/.../templates/` because they're
  **code-coupled** (renderer binds vars into them). Pages link with **relative**
  `../assets/…` paths — gh-pages project subpath (`/conversation-story/`) breaks
  `/assets/…` but not `../assets/…`. `design-prototype.html` links the same
  `assets/` files, so mockup and shipped pages **can't drift**.

## Renderer implication (important for the next build)

"Reproduce `design-prototype.html`" is now cheaper than it sounds: the renderer
**reuses `assets/story.css` + `story.js` as-is** and only generates the per-event
card HTML (`<a class="card k-KIND" id="event-…" …>` + its `<template class="detail">`)
plus the header stats. The prototype's `#cards` block is the shape to emit.

## Open threads / TODOs (not done yet)

- **Anchor id needs a unique-per-event value — a bare uuid is NOT unique.** One
  JSONL record fans out into several events (thinking + text + tool_use all share
  the record's uuid), so `id="event-<uuid>"` would collide. This also means the
  schema's `id: # from uuid` (and `parent:`) are under-specified. **Recommendation:**
  have the parser compute a unique `anchor` (or `id`) field once — e.g.
  `event-<uuid>-<block-seq>` — and the renderer just echoes it into both `id` and
  `href` (never reconstruct at render time; nothing to keep in sync). Offered to add
  the field to `intermediate-schema.md`; awaiting go-ahead.
- **HTML well-formedness check** — recorded as a TODO in `plan.md` Verification. A
  missing closing tag silently breaks the rest of the page; must be checked with a
  real parser (grep is fooled by tags inside comments). Options: `tidy -qe`, `vnu`,
  or REXML/XHTML parse in `rake test`.
- **Font self-hosting** → `assets/fonts/` + `@font-face` in `story.css`, replacing
  the CDN `<link>` in the prototype. Deferred.
- **`id` vs `links.uuid` redundancy** in the schema (same value twice) — flagged,
  undecided.
- **Summaries carry HTML** (`<b>`/`<code>` in the summary text) — the renderer needs
  a deliberate rule for intentional markup vs. escaped log content.

## Process learnings

- **Grep can't verify HTML tag balance** — it counts tags mentioned in comments too.
  Use a real parser (stack-based / XHTML). This is exactly why the well-formedness
  check is a TODO, not a one-liner.
- **For broad mechanical HTML surgery, write a tiny deterministic script** instead of
  pasting giant `old_string`s into Edit — avoids transcription risk and fails safe.
  (Used a throwaway Ruby script in the scratchpad to swap the inline blocks for
  `<link>`/`<script src>`; not committed.)

## Next step

Unchanged: parser skeleton + golden fixture test (Mountain 1). When the renderer
comes, reuse `assets/` and generate only the card HTML. Decide the `anchor` field
before wiring deep-link ids into generated pages.
