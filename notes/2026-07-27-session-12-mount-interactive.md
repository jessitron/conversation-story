# Session 12 — Mount Interactive: modes, keyboard, narrate

Four commits, planned as four independently-usable steps in
`notes/2026-07-27-mount-interactive-design.md` and
`notes/2026-07-27-mount-interactive-plan.md`:

1. **Sidebar behavior** — sticky open/collapsed state, click-to-toggle.
2. **Mode scaffold** — the `explore`/`edit`/`narrate` switch, `?mode=` in the
   URL, edit gated on the `/api/health` probe, focus mode deleted.
3. **Keyboard navigation** — arrows/shift-arrows over explore and edit.
4. **Narrate** — reveal the conversation a beat at a time (this session's
   piece, and the mountain's last item — see the new "Modes and keyboard"
   section in `README.md`).

Mount Interactive is climbed. `TODO.md`'s whole section for it is gone —
everything in it got built, in roughly the shape it described, plus a couple
of deliberate refinements the design doc calls out explicitly (case-folded
`n`/`N`, arrows scroll in both directions not just shift-arrows).

## Why the sidebar became sticky state

Before this work, selecting a card and opening/closing the sidebar were
tangled: `selectCard` itself forced the sidebar open, so there was no way to
browse cards with the stage clear, and the old "Details" reopen tab existed
only because the sidebar could get into a state Jess didn't ask for.

The fix was to stop treating open/collapsed as a side effect of selection at
all — it's Jess's own state, changed only by an explicit action: clicking a
card she didn't already have open, clicking the active card again, Escape, or
(new this session) advancing a narration beat. `selectCard` no longer touches
`sidebar-collapsed`; the one line that used to live there moved out to the
click handler, which is the only place an *open* is actually intended. That
one move is what makes "arrow through the cards with the pane shut" a reachable
state, and it's what makes the reopen tab unnecessary — click any card and the
sidebar comes back, so there's nothing left for a dedicated tab to do.

Narrate leans on exactly this: every `revealTo` call starts with
`collapseSidebar()`, so drilling into a card mid-narration (click to open) is
self-clearing — the next beat press closes it again without Jess having to
remember to.

## What the ferrum harness taught us

`bin/check-modes` (new in Task 1, extended by every task since, six more
scenarios added here) drives a real, built page with real DevTools-Protocol
keystrokes and clicks in headless Chrome — the same pattern `bin/check-anchors`
already used for fragment resolution. Four traps bit along the way, all now
called out at the top of the script itself so nobody re-discovers them the
hard way:

- **Card ids contain a colon**, and CSS reads a colon as a pseudo-class
  introducer. `at_css("#" + id)` doesn't just fail to match — it **throws**.
  Every scenario reaches a card either by index into `card_ids` or by
  `getElementById` inside `evaluate`, never by building a `#id` selector.
- **A real click on a card far down the page silently misses** unless the
  card is scrolled to `{block: 'center'}` first — real mouse events, unlike
  a synthetic `.click()`, only land on what's actually under the cursor.
  `Story#click` does the scroll for you so no scenario has to remember.
- **`[:Shift, 'n']` is not `"N"`.** Ferrum's `keyboard.type([:Shift, 'n'])`
  delivers a keydown with `e.key === 'n'` and `shiftKey: true` — not the `'N'`
  a real keyboard sends for shift+n. This is exactly why the handler
  case-folds `e.key` rather than trying to distinguish `'n'` from `'N'`: code
  that only worked against `"N"` typed directly would have looked fine by hand
  and then failed under CDP-synthesized input. One of the "check-modes"
  scenarios exists specifically to pin this down (`s.key("N")` vs. typing the
  shift chord) and comments the distinction inline.
- **The page always loads with a card already selected** — `DEFAULT_CARD`,
  so the sidebar is never truly empty on first paint. "Nothing is active" is
  never the start state in explore/edit. This one bit a Task 3 scenario
  directly: an earlier version hard-coded a starting card index, and it
  happened to collide with whatever the default selection was, so the
  scenario's "click a different card" step silently clicked the *same* card
  and asserted nothing. The fix, followed by every scenario since, is
  `ids.find { |id| id != s.active_id }` — never assume index 0 (or any fixed
  index) is unselected.

Narrate added one more wrinkle worth recording: `revealTo` clears any pending
per-card reveal timers and re-syncs the DOM to the *current* `revealed` count
before scheduling new ones. That's what makes a rapid double-press mid-flurry
safe — the second press doesn't race the first's animation, it snaps the DOM
to wherever the count actually is and then continues from there. Verified this
by hand (not just by the scenarios, which press-and-settle) with a throwaway
ferrum script that fired two `n` keydowns back to back with no delay between:
the JS `revealed` variable, the count of `.card.revealed` elements, and the
count of cards with non-`none` computed `display` all agreed afterward.

## Two small deviations, on purpose

Both already called out in the plan's self-review, worth repeating here since
they're easy to "fix" back to the letter of the design by mistake:

- The design's keyboard table is silent about plain arrows scrolling; only
  shift-arrows are specified to scroll. `moveSelection` scrolls on both
  (`block: 'nearest'`), because a selection you can't see is a bug regardless
  of which key produced it, and `nearest` is a no-op when the card's already
  on screen.
- The design distinguishes `n` from `N`. The handler folds case instead, so
  they're the same key everywhere. Costs nothing — lowercase `n` was already
  the forgiving alias for "enter narrate" outside narrate, so the two letters
  only ever differed *inside* narrate, where `N` would have meant "enter the
  mode you're already in." And it buys correctness under caps lock and under
  the CDP-synthesized shift+n described above.

## Also

`CLAUDE.md`'s Ruby/Gemfile bullet now says why the Gemfile has a `:test`
group: `ferrum` is a test-only dependency (`bin/check-modes` needs a real
Chrome, nothing shipped needs it), so it doesn't belong in the default group
alongside `webrick`/`rake`.

## How this session was run, and what that's worth repeating for

Brainstorm → design note → implementation plan → four subagent-implemented
tasks, each with its own review. Three things earned their keep:

**Spike the tooling before writing the plan, not during it.** The original
plan had `bin/check-modes` built as an iframe harness dispatching synthetic
`KeyboardEvent`s, because "headless Chrome can't type" was assumed. Once gems
were on the table, twenty minutes of throwaway ferrum scripts turned all four
traps above from future debugging rounds into *plan constraints written down
before anyone implemented anything*. The plan then said "do not re-derive
these," and nobody did. The general shape: when a plan depends on a fact about
a tool, go find the fact out — Clausewitz's curious mind over the inventive
one, applied to test harnesses.

**Two of the bugs found during execution were in the plan, not the code.**
A Task 3 scenario hard-coded a card index that collided with `DEFAULT_CARD`
(the trap the plan itself had documented — writing a constraint down doesn't
stop you violating it three sections later), and a Task 4 scenario asserted
something that stayed true even with `exitNarrate()` deleted. Both surfaced
only because implementers and reviewers were told explicitly **not to silently
patch a failing test** — the Task 3 implementer diagnosed the collision,
verified the production code was correct, and escalated instead of "fixing"
the assertion. Worth keeping that instruction in future dispatches; a subagent
that quietly makes a test green destroys the signal.

**Ask reviewers what would make a test fail.** "For each scenario, what code
change would make this fail?" caught the vacuous `exitNarrate` assertion that
three earlier passes had waved through. The follow-up — stub the function,
watch the test go red, restore it — is cheap and is the only actual proof a
test is load-bearing.

One process miss worth naming: the "stdlib-first" line in `CLAUDE.md` got read
as "add no gems" and written into the plan as a hard constraint Jess had never
asked for. She corrected it ("there's nothing wrong with gems"), which is what
unlocked ferrum and, with it, a much better harness. That bullet has since been
reworded to say what it actually protects — the three shipping programs staying
dependency-free — rather than sounding like a prohibition. **A constraint
inherited from a context file is not the same as a constraint the human holds;
when one is about to shape a design decision, it's worth surfacing rather than
silently obeying.**
