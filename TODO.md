# TODO

The mountains are named in `README.md`. This is the working list, grouped by
which mountain each item climbs. Order within a group is roughly "what I'd pick
up next" — nothing here is scheduled.

## Mount Interactive

- **Step-through navigation.** The North Star says "I can step through it," and
  right now the only way forward is clicking the next card and scrolling.
  Wanted: keyboard next/prev over the visible cards, and a way to reveal events
  in progression while narrating (a presenter mode) rather than showing the
  whole timeline at once. Selection is fragment-driven, so "next" is
  "`getElementById` the next `.card` and set the hash."
- **Edit is a mode** in interactive, step-through mode, that's different from edit mode where I can change the summaries. The summaries still display in every mode, and there is a subtle indication of whether they have been edited.
- There is a mode switch in the header. explore/edit/narrate or hotkeys x/e/N
- The cards are selectable; clicking them opens the detail. Clicking the card again should close the detail
- Escape should close the detail sidebar
- don't show 'DETAILS' as the closed sidebar. It can be invisible. That keeps it clean for narration.
- right arrow should go to the next card (and left previous)
- shift+right arrow should go to the next assistant/user card. It should scroll to it as well.
- **Narration mode** is an interactive, step-through mode. It starts with no cards displayed. Right-arrow or 'n' causes the first message to appear, a user message. 'n' again causes subsequent cards to appear one at a time until the next assistant/user message appears, then pauses. This scrolls down as necessary so the appearing card is on the screen. It also selects that assistant/user message. Escape exits narration mode; 'N' enters it. If you enter narration mode with a card selected, then narration starts from there.

## Mount Complete

- **Say when an assistant turn includes tool calls.** On the Assistant messages, in the detail, let's also show all the tool calls that came back with that message.
- **Subagents** inline a spawned Agent's own story instead
  of only listing it in `meta.agents`. The subagent logs are already on disk
  (`examples/<name>/subagents/agent-*.jsonl` + `.meta.json`) and the schema
  already reserves an `agent:` id on every event. Subagent tool calls should be expandable into the whole story of the subagent.
- The `<ol>`/`<ul>` merge in `Markdown` only re-glues _adjacent_ same-type
  blocks; a loose list interrupted by an aside paragraph would still split.
  Fine for what's in the example logs; revisit if a real log hits it.
- **Token stats** In the card detail, show: the current context length (input tokens), along with how many were cached (if available); the amount added to the context (output tokens); and a running total of all input tokens since the beginning
- In the summary, show the total context length (like, I think that's input + output tokens for the last interaction)

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

## Maybe later

- **Hooks.** The logs carry a lot of hook detail we currently leave as
  summary-only: `system` events (`stop_hook_summary`, `turn_duration`,
  `hookInfos`, `hookErrors`) and the ~157 `attachment` records that are really
  hook-execution records (`hookName`, `hookEvent`, `command`, `stdout`/`stderr`/
  `exitCode`/`durationMs`). Interesting, not urgent — if we do it, they get
  named schema fields like everything else.
