# Session 14: subagent subactions, in the design prototype

Design-only session (no parser/renderer work) — settled the look of a
spawned subagent's own story showing up inline in the board, in
`assets/design-prototype.html` + `assets/story.css`. The corresponding
implementation task is still open: see Mount Complete's "Subagents inline a
spawned Agent's own story" in `TODO.md`. Full rationale is in
`notes/2026-07-28-subagent-subactions-design.md`; this note is the
session-shaped version — what we tried, what broke, what Jess corrected.

## Where it landed

- A Subagent card (`k-subagent`, red) expands **inline in the board** —
  not detail-pane-only, not a drill-down — into the events the subagent
  itself produced.
- Subaction cards are **full-size `.card` elements** with their own real
  `k-*` kind class (`k-assistant`, `k-tool_call`, `k-tool_result`) — same
  size, same `<template class="detail">`, same click-to-select behavior as
  a top-level event. Indentation + a connecting rail (`.subactions`
  wrapper) are the *only* difference from a top-level card.
- Expanded by default; a caret in the gutter (after the "Subagent" label,
  not before — see gotcha below) is the collapse affordance. Both states
  (expanded "Explore" example, collapsed "general-purpose" example) are
  built into the prototype so the pair is visible side by side.
- The subagent card itself carries an **Agent badge** (mirrors how a
  `tool_call` card badges its tool name) and no token/tool-count badges —
  those are detail, already in the Fields section of the detail pane, not
  a card-face headline.
- The subagent's return value gets its **own top-level, non-indented card**
  — a new kind, `k-subagent_result` (same red family as `k-subagent`, same
  quiet/background treatment as `k-tool_result`). This represents the real
  `Task` tool_result the main log records when the subagent's work is
  delivered back to its caller — distinct from both a nested subaction and
  a plain `k-tool_result`.

## Gotchas (for the real implementation, and for future CSS work here)

- **Indentation must not double-count `--gutter-w`.** First pass indented
  the `.subactions` wrapper by `var(--gutter-w)` on top of subaction cards
  that are themselves full `.card`s — each already reserves its own
  `--gutter-w` column internally. Stacking both pushed everything a full
  extra column too far right. Landed on: no wrapper margin at all, just
  the rail's own `padding-left: 20px`.
- **`.gutter` inherits `white-space: nowrap`**, fine for every existing
  one/two-word kind label but it clips a longer one — "Subagent Result"
  ran straight into the body column with no gap. Fixed by scoping
  `white-space: normal` onto `.gutter .kind` specifically, so it wraps
  within the fixed gutter column instead.
- **A "condensed miniature card" for subactions was the wrong instinct.**
  First pass shrank subactions into a smaller flattened `.subaction` div to
  read as "quieter than a real event" — this silently dropped the
  click-to-detail behavior every other card has (no `<template>`, not a
  real `<a class="card">`), and Jess caught it by noticing the detail pane
  never rendered. Corrected to full-size real cards; smaller/different was
  never actually wanted, only the indent + rail.
- When checking behavior instead of just looks, a plain screenshot isn't
  enough — used `ferrum` (already a project dependency for
  `bin/check-modes`) to actually click a card in headless Chrome and read
  back the detail pane's contents. First attempt at that check used too
  small a default window and silently clicked the wrong element, which
  looked like a real bug until re-tested at a large-enough window size.
