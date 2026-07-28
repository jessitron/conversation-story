# TODO

The mountains are named in `README.md`. This is the working list, grouped by
which mountain each item climbs.

## Mount Complete

- **model name** put the model name in every LLM-call-representing card.

Done: **subagents** inline a spawned Agent's own story (session 15) — a
`subagent` card expands into it in place, and the answer comes back as a
top-level `subagent_result`. See `notes/2026-07-28-session-15-subagents.md`.
Open follow-ons from that work:

- **Remember which subagents are closed.** They ship expanded and the caret is
  session-only state — a reload reopens everything.
- **Flurry pacing for a long subagent.** One beat now reveals a subagent's whole
  story, 70 cards at `BEAT_MS` (80ms) = about 6 seconds. Deliberate — that's the
  "look how much work" moment — but if it drags mid-talk, the fix is pacing (cap
  the beat's total duration, or ease the interval down as the run gets longer),
  not hiding cards.
- **A subagent's own tokens have nowhere to live in the header.** The story's
  Tokens stat is the parent's; a subagent's 2.05M of its own use shows only in
  its card's Fields. The 'where are we' map below is where that belongs.

### Token Counts

Rearrange the token count sections.

In an assistant card:

```
Tokens
------
Model: sonnet-4.5

  Input tokens: 24,342
        cached: 22,345 (98%)
added to cache:  1,998

  Output tokens:   233
```

In a tool result card, move it to the top as one line (instead of a whole section)

```
Tool Result -- [tool]
------
Result size:  4.5 KB ~= 1,308 tokens
```

In a subagent card:

```
Tokens
------
Model: sonnet-4.5

Input tokens: 1,024,342
      cached:   998,345 (98%)

Output tokens:    4,233
```

## Mount Beautiful

- **edit mode marker** Currently this shows up appended to the summary. It distracts me there, looks like it's part of the text. Instead, put it in the .who section, to the right of "Claude" or the left of "Jess"
- **enqueue tag** Instead of `Queue enqueue: Background command "Start Vite dev client on port 5175" failed with exit code 1` let's say `Background command "Start Vite dev client on port 5175" failed with exit code 1` and have an `[ENQUEUE]` tag. Also, let's give it an [ERROR] tag when it failed (for instance, it contains "command .\* failed")
- Instead of `[REMOVED FROM QUEUE]` let's shorten to `[FROM QUEUE]`
- **subagent detail tweaks** Move the 'log' field to 'Provenenance'. Give it a button near the top to expand/collapse its cards in the conversation.
- Self-host the fonts (Tenor Sans / Sen / Cascadia Code) into `assets/fonts/`
  with `@font-face` in `story.css`, replacing the CDN `<link>`.
- A capability owner whose job is to guard the CSS and keep it consistent. Two things it
  would have caught in session 9: a `var()` on a token that no longer exists
  (fails silently), and a rule whose `opacity` override lost to a
  same-specificity rule later in the file.
- the list of related events in the detail view, I want it to look different. More like the other details, less imitation of the card.

### 'Where are we' map on the left side

This is a major feature that will add perspective. I want a 'where are we' indicator on the left. It's a vertical bar that takes the height of the page and does not scroll. It represents the conversation as a whole. The vertical axis is _context length_. Three sections in the bar: prior context, context added in the currently highlighted card (this is the token contribution of this card), and context added in all future cards.

When the currently highlighted card is a tool callthat does not add to the context, then there is only a bar (a minimum height) between prior and future context representing the current location. A tool result can show its approximate token contribution. A user input could show its contribution, although probably the minimum bar height will be taller than this.

Usually, this map moves immediately when a new card is selected (no transition). In narrate mode, when I push n or arrow to add to the screen, it animates smoothly, showing the context growing as the conversation lengthens.

Subagents get their own bar to the right of the main bar! When I click on a subagent card or any card representing a subagent's event, then the main bar shows the context added by the subagent as if the subagent's result card was selected. An additional bar appears next to it, representing the subagent context. The subagent's bar has more parts: before the subagent started; context added before the current selected card; current card's token contribution; future context from later cards; extra space that the subagent didn't use. The subagent's context bar should use _the same scale as the main conversation_, unless the subagent's context is larger than the main conversation's, in which case it scales to screen height. The subagent's "context added before" starts at the height of the subagent invocation on the main bar, unless that would make its context summary go off the bottom of the page, in which case it moves up to fit.

## Mount Malleable

_A local web app for shaping the story — edit on the page, not in YAML._

- **Title is editable**

## Mount Interactive

_Three modes, a keyboard map, and narrate. Both items below are known,
deliberately deferred rough edges from the final review — neither is a
correctness bug that needs fixing right now._

- **change narrate shortcut** I want 'n/p' to work for "move to the next/prev assistant/user message" in any mode, and let's make the "narrate mode" shortcut something else. Maybe 's' for story?
- **modify when it stops** Currently 'n' or shift-arrow goes to the next Assistant/User message. I want to exempt some messages from this. Let's introduce concept of Pause-here (or come up with a better name), which defaults to true for Assistant/User messages in the main thread and false everwhere else. Let's make it editable in edit mode.
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
