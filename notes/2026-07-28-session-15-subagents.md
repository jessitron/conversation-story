# Session 15: subagents, for real (Mount Complete)

Session 14 settled the *look* of a subagent's story in the board
(`notes/2026-07-28-subagent-subactions-design.md`, static mock only). This
session wired it to real data: parser, renderer, JS, and the write path.

## Where it landed

- **The hinge is `toolUseResult.agentId`, not the tool's name.** The Agent
  tool_result is the one record that says *which* subagent ran, and that field
  names the sibling `subagents/agent-<id>.jsonl`. The tool NAME has changed
  across Claude versions (`Task`, now `Agent`); `agentId` hasn't, and it only
  ever appears on a real subagent result. So the parser matches on it and the
  reclassification falls out: the `tool_call` becomes `subagent`, its
  `tool_result` becomes `subagent_result`.
- **The subagent's log is parsed by the same `Parser`, recursively**, and hangs
  off the call as `subagent.meta` + `subagent.events`. That one line is what
  makes everything else free: nested refs (`agent-ae2065…:2`) come from that
  file's own name and line numbers, and the nested story gets its own turn
  election, its own token running total, and its own tool_call↔tool_result
  links — none of it derived from the parent, so none of it can collide with or
  leak into the parent's.
- **Nested events do NOT join the flat `events` list.** That list is
  one-event-per-line of the main log (`event_count == line count`, a golden
  test). Nesting keeps that true and matches how the cards nest.
- **Expanded by default**, as session 14 decided. I shipped it collapsed first,
  reasoning from size (70 and 55 subactions inside a 109-card story) — wrong
  reason. Jess: *"I want to see the work that's being done. In particular, in
  narrate mode, I want it to be evident that the agent is doing a bunch of
  things."* Volume isn't clutter here; it's the content. The caret is for
  quieting a subagent down, not for hiding it until asked.
- **A beat never stops inside a subagent.** `isMessage` — which drives both
  narrate beats and shift+arrow — now means "a message in the conversation with
  Jess", so it excludes cards inside `.subactions`. A subagent's own assistant
  messages are that agent talking to itself; stopping on them split one beat of
  Jess's conversation into sixteen. Now the whole subagent story rides inside the
  beat that spawned it and reveals as the flurry it was, which is exactly the
  "the agent is doing a bunch of things" moment. (Note: 70 cards at `BEAT_MS`
  = 80ms is a ~6-second beat. It reads as a real flurry; if it ever feels long,
  that's the knob.)
- The subagent's first log record is **the prompt it was handed** — the same
  string the parent's Agent call already shows on the card and in its Prompt
  section — so it's `hidden: true`.
- The `subagent_result`'s Answer is rendered as **markdown prose**, the one
  deliberate exception to session 9's "tool results are machine voice". It isn't
  program output; it's one agent's written report to another.

- The subagent card's summary is **`--fs-small` like every other action card**
  (tool calls, results, reasoning, system). It had been inheriting the body size,
  which read as a conversation message. It keeps its paper background and full
  opacity, though — a spawned agent is a louder event than a Grep, just not a
  louder *voice*.
- Both halves of the pair carry an **`[AGENT]` badge** — a `tool_result` badges
  its tool, so the answer coming back should badge its agent. Jess asked for it
  on the result card and guessed it might also fix the summary sitting oddly low
  there; it didn't (that was the baseline bug below), but both are fixed.

## Gotchas

- **`inline-block` on `.gutter .kind` broke baseline alignment for the one label
  that wraps.** The card grid is `align-items: baseline`, and an inline-block
  reports its **last** line's baseline — so "Subagent Result" wrapping to two
  lines dragged the row's first baseline down to its second line, and that card's
  summary sat 18px lower than every other card's. `display: block` fixes it (the
  caret is an inline child, so it still sits beside the label). Measured, not
  eyeballed: forcing `inline-block` back in a live page moves the skew 0 → 18 on
  `subagent_result` and leaves every single-line label at 0.

  Jess then took the fix a level deeper: **the card grid is `align-items: start`
  now**, with `k-user`/`k-assistant` opting back into `baseline`. That's the right
  split, not a compromise — an action card's label and summary are both
  `--fs-small`, so top and baseline land in the same place *and* top can't be
  moved by a wrapping label; the two conversation kinds are the only ones whose
  summary is a different size (`--fs-summary`), where a shared baseline is what
  makes "ASSISTANT" sit level with the words it labels, and their labels are one
  word so they can't wrap. Measured: skew is now a uniform −2 on every action
  card and −6 on the two message kinds.
- **Anything that counts or finds cards has to walk the tree now.** Four places
  did it over the flat list and every one of them was wrong the moment the first
  subagent inlined: `Renderer#link_index`/`#turn_index` (so a causal chain can
  reach into a subaction), `Edits#apply` and `bin/serve`'s `event_for` (or
  editing a subaction's summary answers "unknown event" from a card Jess is
  looking at), and the tests' card counts (`test/story_events.rb` exists for
  exactly this, deliberately NOT calling into the renderer — a test that reuses
  the code under test can only confirm it agrees with itself).
- **The header's Events stat deliberately did NOT change.** It's the size of the
  conversation being told (109), not the number of cards drawn (179) — and
  `bin/site-index` counts the same way, so the landing page can't drift.
- **"Too much on the page" was my instinct, not Jess's requirement.** The first
  cut hid 70 real events behind a caret to protect the main narrative — from a
  page whose entire purpose is showing what happened. When the honest answer to
  "should this be visible?" is "it's a lot", that's a reason to look at the
  reveal PACING, not to hide the content.
- **`bin/check-modes` now has two index spaces**, and mixing them silently
  breaks: `card_ids` is what Jess can step through (mirrors story.js's `NAV()`),
  `all_card_ids` is every `.card` in the DOM. `click()` indexes the DOM; a
  navigation *expectation* must come from `card_ids`. Both existing failures when
  subagents first rendered were this, not page bugs — "right arrow did not land
  on agent-…:2" was the checker expecting a card nobody can see.
- **A subagent's log is a parse input**, so the Rakefile lists
  `examples/<name>/subagents/*.jsonl` as prerequisites of `story.yaml`. Without
  that, editing a subagent log leaves the built story stale.
- **Two different "total tokens" for one subagent**, ~17× apart, and both are
  right: `subagent.meta.total_tokens` is 2.05M (every turn of its conversation
  counted once — token *use*, same measure as the header stat) while
  `tool.subagent_tokens.total_tokens` is 124k (what the harness reports for the
  run). The page labels them "own token use" and "total_tokens" respectively, on
  different cards.
- The caret is **the only click inside a card that doesn't select the card**, so
  the delegated handler has to check for it before doing anything else. There's a
  `bin/check-modes` scenario asserting exactly that (expand, selection unmoved,
  collapse again).
