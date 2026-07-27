# TODO

The mountains are named in `README.md`. This is the working list, grouped by
which mountain each item climbs.

## Mount Complete

- **Subagents** inline a spawned Agent's own story instead
  of only listing it in `meta.agents`. The subagent logs are already on disk
  (`examples/<name>/subagents/agent-*.jsonl` + `.meta.json`) and the schema
  already reserves an `agent:` id on every event. Subagent tool calls should be expandable into the whole story of the subagent.
- **Retune `Parser::CHARS_PER_TOKEN`** (3.5) if a better measurement turns up.
  Today's tool-result estimate is calibrated against inter-turn context deltas,
  which overstate the result's share because harness records share the gap. A
  real tokenizer, or a log where a result sits alone in its gap, would settle
  it. Not urgent — the page labels the number an estimate.
- The `<ol>`/`<ul>` merge in `Markdown` only re-glues _adjacent_ same-type
  blocks; a loose list interrupted by an aside paragraph would still split.
  Fine for what's in the example logs; revisit if a real log hits it.


## Mount Beautiful

- Self-host the fonts (Tenor Sans / Sen / Cascadia Code) into `assets/fonts/`
  with `@font-face` in `story.css`, replacing the CDN `<link>`.
- A subagent whose job is to guard the CSS and keep it consistent. Two things it
  would have caught in session 9: a `var()` on a token that no longer exists
  (fails silently), and a rule whose `opacity` override lost to a
  same-specificity rule later in the file.
- the list of related events in the detail view, I want it to look different. More like the other details, less imitation of the card.

## Mount Malleable

_A local web app for shaping the story — edit on the page, not in YAML._

- **Title is editable**

## Mount Interactive

_Three modes, a keyboard map, and narrate. Both items below are known,
deliberately deferred rough edges from the final review — neither is a
correctness bug that needs fixing right now._

- A degraded or bogus `?mode=` value stays in the URL while the body is
  `mode-explore`, and pressing `x` won't clear it — `setMode` early-returns on
  a same-mode call. Cosmetic, but it's the one place the URL and the body
  class disagree.
- Clicking a related-event link in the detail pane during narrate fires
  `hashchange`, and `syncFromHash` selects a card that's still hidden and
  outside the revealed prefix. No error, and it self-heals on the next beat,
  but mid-talk it's a spoiler.

## Maybe later

- **Hooks.** The logs carry a lot of hook detail we currently leave as
  summary-only: `system` events (`stop_hook_summary`, `turn_duration`,
  `hookInfos`, `hookErrors`) and the ~157 `attachment` records that are really
  hook-execution records (`hookName`, `hookEvent`, `command`, `stdout`/`stderr`/
  `exitCode`/`durationMs`). Interesting, not urgent — if we do it, they get
  named schema fields like everything else.
