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
- **Reuse existing kind styling.** Each subaction keeps the real `k-*` class
  (`k-thinking`, `k-tool_call`, `k-tool_result`, `k-assistant_message`) and
  accent color, just smaller/condensed (less padding, shorter summary) —
  same visual language as top-level cards, not a separate flat look.

## Source material

Mocked from the real subagent log `examples/episode-8-before/subagents/agent-ae20659fd0f63295e.jsonl`
(the Explore agent, "Explore timeline/replay features") — user prompt, then
thinking → tool_call:Bash → tool_result → assistant_message, matching the real
event shapes a subagent log actually produces.

## Scope

Static HTML/CSS in `assets/design-prototype.html` only (mirrored into
`assets/story.css` if new rules are needed). No JS collapse/expand behavior,
no parser or renderer wiring — those remain the Mount Complete implementation
task.
