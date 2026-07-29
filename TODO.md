# TODO

The mountains are named in `README.md`. This is the working list, grouped by
which mountain each item climbs.

## Metawork

(work about the work)

- **design feature owner** I really need a feature owner for the CSS, a designer who is invoked any time the UI is updated.

## Mount Complete

- **model name** put the model name in every LLM-call-representing card.
- **notice title generation** The ai_title events are kinda neat, and it would be cool if they showed up. And as we scrolled past them, the title at the top changed!
- **attachments that carry real content** (session 19) — `hook_additional_context`
  is the good one: its `content` array holds the text a hook actually injected
  (`mode-switches:5` = 3,276 chars of the SessionStart superpowers block), and it
  already renders. Show it off — it's the _only_ place the log reveals
  instructions the agent was operating under; the system prompt and CLAUDE.md are
  never logged at all. See
  `notes/2026-07-28-session-19-what-the-log-cannot-tell-you.md`.
  While in there, the sibling subtypes are broken: `attachment_detail_text` reads
  only `prompt` and `content`, so every other visible subtype renders a **raw
  subtype string as its summary over an empty detail pane** — 8 such cards on
  `mode-switches` alone (`agent_listing_delta` → payload is in `addedLines`;
  `edited_text_file` ×4 → `filename` + `snippet`; `plan_mode_exit` ×2 and
  `plan_mode` → `planFilePath`, `reminderType`; plus `command_permissions` →
  `allowedTools` in `mtg-tabletop-plan`). Each needs either a real summary +
  detail or a place in `HIDDEN_ATTACHMENT_TYPES`. Two notes on deciding:
  - `edited_text_file` is worth _keeping_ — it fires when Jess edits a file
    mid-session (4× in `mode-switches`, once in session 19 when Jess edited
    `CLAUDE.md` mid-turn). "Jess changed the instructions underneath me" is a
    story beat, and today it's a blank card.
  - the hidden list is **inverted** on one pair: `skill_listing` is hidden
    despite carrying 8,185 chars of content, while `agent_listing_delta` is
    visible with nothing to show. Decide those two together.
- **mode changes in the stream** Each prompt now carries the mode it was sent in (a `Mode` row in its detail pane). It may be possible to notice permission mode changes and mark it in the conversation stream.

### Subagents

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
  its card's Fields. The Tokens stat in the page header SHOULD include the subagent tokens.

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

In a subagent card (or subagent results, whenever this is available):

```
Tokens
------
Model: sonnet-4.5

Input tokens: 1,024,342
      cached:   998,345 (98%)

Output tokens:    4,233
```

## Mount Beautiful

Done in session 17: the ✎ edited marker moved into the gutter beside the actor;
an enqueue's summary is the payload alone with the operation as a badge, plus an
Error badge driven by a new `status` field (read from the notification's
`<status>` tag, not a regex on its wording); `[REMOVED FROM QUEUE]` shortened to
`[FROM QUEUE]`.

- **subagent detail tweaks** Move the 'log' field to 'Provenenance'. Give it a button near the top to expand/collapse its cards in the conversation.
- Self-host the fonts (Tenor Sans / Sen / Cascadia Code) into `assets/fonts/`
  with `@font-face` in `story.css`, replacing the CDN `<link>`.
- **less redundancy on tool call cards** I don't want a bash tool call to display **Bash** in the summary, nor a read tool to display **Read** because there's a tag on the card that says this already.
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
- **`bin/check-edit-api` fights a real sidecar.** It starts `bin/serve` against an
  EMPTY temp edits dir, so every rebuild it triggers strips that story's real
  hand-written summaries out of `out/<name>/` — and its "an empty summary reverts
  to the generated one" check FAILS whenever the event it picked already has one
  of Jess's summaries (it captures that line as "generated", then compares it to
  the parser's). Surfaced the moment `episode-8-after:4` got a hand-written
  summary. Both symptoms have one cause: the temp dir doesn't mirror the real one.
  The fix is probably to seed the temp dir with a copy of `edits/<name>.yaml` —
  but then "the emptied sidecar file is gone" has to become "my ref is gone from
  it", since the file legitimately still holds Jess's other entries. Until it's
  fixed, `rake build` after running the checker restores `out/`.

## Mount Interactive

_Three modes, a keyboard map, and narrate. Both items below are known,
deliberately deferred rough edges from the final review — neither is a
correctness bug that needs fixing right now._

- **change narrate shortcut** I want 'n/p' to work for "move to the next/prev assistant/user message" in any mode, and let's make the "narrate mode" shortcut something else. Maybe 's' for story?
- A degraded or bogus `?mode=` value stays in the URL while the body is
  `mode-explore`, and pressing `x` won't clear it — `setMode` early-returns on
  a same-mode call. Cosmetic, but it's the one place the URL and the body
  class disagree.
- Clicking a related-event link in the detail pane during narrate fires
  `hashchange`, and `syncFromHash` selects a card that's still hidden and
  outside the revealed prefix. No error, and it self-heals on the next beat,
  but mid-talk it's a spoiler.

- **collapsing sections** It would be nice to collapse by beat as well as by subagents. I also want hotkeys for this, including collapse/expand all and collapse/expand selected.

- **show live conversations** figure out what it would take, and how it would look, to show conversations that are active, like based on the growing files in .claude. Then I could read what's happening in a format that doesn't hurt my eyes.

- **summarize a section** It would be helpful to be able to select a
