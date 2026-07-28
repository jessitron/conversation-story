# Subagent subactions in the board (design prototype)

Design-only session: mock up how a subagent's own actions ("subactions") show
up inline in the board, in `assets/design-prototype.html`. No parser/renderer
changes — that's the Mount Complete TODO item ("Subagents inline a spawned
Agent's own story"). This is groundwork for that: settling the look before
wiring real data.

## Decisions

- **Inline in the board**, not detail-pane-only and not a drill-down view. The
  subagent's subactions appear as extra cards right in the main event list,
  nested under the Subagent card.
- **Expanded by default**, with a caret in the gutter to collapse. (Doesn't
  matter for a static prototype which state ships as the default markup —
  what matters is both states are designed and the caret affordance exists.)
- **Indented + connecting rail.** Subaction cards sit indented under the
  Subagent card with a vertical rail linking them, ending in a closing marker
  so the rail doesn't dangle into the next top-level card.
- **Full-size cards, not a condensed echo.** First pass shrank subactions into
  a smaller, flattened `.subaction` div — Jess corrected this: a subaction is
  a real `.card` with its own real `k-*` class (`k-assistant`, `k-tool_call`,
  `k-tool_result`), same size, same `<template class="detail">`, same
  click-to-select behavior as a top-level event. Indentation and the rail are
  the *only* difference. `.subactions` supplies the indent/rail wrapper and
  otherwise gets out of the way; it does not restyle its children.
- Confirmed with `ferrum` (already a project dependency for `bin/check-modes`)
  that clicking a nested subaction card selects it and populates the detail
  pane, same as any top-level card — the first attempt at this check used too
  small a headless window and clicked the wrong element, which looked like a
  real bug until re-tested at the right size.

## Source material

Mocked from the real subagent log `examples/episode-8-before/subagents/agent-ae20659fd0f63295e.jsonl`
(the Explore agent, "Explore timeline/replay features") — real content for
each subaction (assistant text, a `Bash` call, a `Grep` call, their results,
final reply), with real `source.line` numbers into that file. Per the parser's
actual kind-mapping rule, a `text` content block is `assistant_message`
regardless of position — so the subagent's opening narration and its closing
summary are both `k-assistant`, not `k-thinking`.

## Scope

Static HTML/CSS in `assets/design-prototype.html` only (mirrored into
`assets/story.css` if new rules are needed). No JS collapse/expand behavior,
no parser or renderer wiring — those remain the Mount Complete implementation
task.
