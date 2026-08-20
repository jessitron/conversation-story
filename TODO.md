# TODO

The inbox: raw captures, pre-decision. The chart (North Star, Mountains) is in
`SEAMAP.md`. Nothing here has a tracker to promote to yet — this file is the
whole system for now.

## In progress

## Next

- `context-map-sidebar` **v1 shipped** (session 23): a "where are we" map on
  the left, a non-scrolling full-height bar with three segments — prior
  context, the selected card's own contribution, and everything still ahead —
  sized via flex-grow from each card's `data-ctx-before`/`data-ctx-mine`
  (`Renderer#context_contribution`/`#build_context_axis!`, a running total
  over fields session 22 already computed — no new estimation). Jumps
  instantly on selection; main conversation only. Remaining from the original
  spec, still open:
  - Usually the map jumps instantly on selection (no transition) — done. In
    narrate mode, pressing n/arrow should animate it smoothly, showing context
    growing as the conversation lengthens — not done yet.

  **Subagent bars: done for the directly-enclosing subagent** (session 24).
  Selecting a subagent card (or any event inside it) makes the main bar show
  context as of the subagent's result card (not the call — the main
  conversation hasn't resumed until then), and a second bar appears next to
  it for the subagent's own context: before the subagent started, context
  added before the current card, the current card's contribution, future
  context, and unused extra space. Same scale as the main conversation
  unless the subagent's own peak context is larger, in which case it scales
  to its own full height instead. Its "context added before" segment starts
  at the height of the subagent invocation on the main bar, clamped so it
  never pushes its own value label off the bottom of the page.
  `Renderer#build_subagent_axis!`/`#sub_ctx_attr` do the per-subagent running
  total (keyed by the subagent card's ref); `story.js`'s `updateSubagentMap`
  does the positioning math in pixels, not flex-grow, because "same scale"
  means literally the same px-per-token across two independent flex
  containers, which flex-grow (relative within one container) can't express.
  Still open:
  - A header option to show all subagent context bars at once, lined up in
    parallel after the main one — to see where the tokens are going. Right
    now only the ONE subagent directly enclosing the current selection gets
    a bar.
  - In narrate mode, pressing n/arrow should animate the bar(s) smoothly,
    showing context growing as the conversation lengthens — not done yet.

  Later: an agent at import-time could classify parts of the conversation —
  overhead of dealing with worktrees, dealing with errors, consulting
  capability owners, testing.
  ← priority: high; mountain: mount-struggle

## Backlog


- `design-feature-owner` A feature owner for the CSS — a designer invoked any
  time the UI is updated ← mountain: metawork

- `model-name` Put the model name in every LLM-call-representing card ← mountain: mount-complete
- `notice-title-generation` Show `ai_title` events, and change the page title
  as we scroll past them ← mountain: mount-complete
- `attachment-content-types` Attachment subtypes carry real content
  (session 19) — `hook_additional_context`'s `content` array already renders,
  and it's the _only_ place the log reveals instructions the agent was
  operating under (system prompt and CLAUDE.md are never logged). See
  `notes/2026-07-28-session-19-what-the-log-cannot-tell-you.md`. Sibling
  subtypes are broken: `attachment_detail_text` only reads `prompt` and
  `content`, so 8 other visible subtypes on `mode-switches` alone render a raw
  subtype string over an empty detail pane (`agent_listing_delta` → payload in
  `addedLines`; `edited_text_file` ×4 → `filename` + `snippet`;
  `plan_mode_exit` ×2 and `plan_mode` → `planFilePath`, `reminderType`;
  `command_permissions` → `allowedTools` in `mtg-tabletop-plan`). Each needs a
  real summary + detail, or a place in `HIDDEN_ATTACHMENT_TYPES`.
  - `edited_text_file` is worth keeping — it fires when Jess edits a file
    mid-session (4× in `mode-switches`, once in session 19 editing `CLAUDE.md`
    mid-turn). "Jess changed the instructions underneath me" is a story beat,
    today it's a blank card.
  - The hidden list is inverted on one pair: `skill_listing` is hidden despite
    8,185 chars of content, while `agent_listing_delta` is visible with
    nothing to show. Decide those two together.
    ← mountain: mount-complete
- `mode-changes-stream` Notice permission-mode changes and mark them in the
  conversation stream (each prompt already carries the mode it was sent in, a
  `Mode` row in its detail pane) ← mountain: mount-complete

- `subagent-collapse-memory` Remember which subagents are closed — they ship
  expanded and the caret is session-only state; a reload reopens everything
  ← mountain: mount-complete
- `subagent-flurry-pacing` Pace a long subagent's reveal — one beat now
  reveals a subagent's whole story, 70 cards at `BEAT_MS` (80ms) ≈ 6 seconds.
  Deliberate (the "look how much work" moment), but if it drags mid-talk, cap
  the beat's total duration or ease the interval down as the run gets longer
  — not hiding cards ← mountain: mount-complete
- `subagent-tokens-header` A subagent's own tokens have nowhere to live in the
  header — the page's Tokens stat is the parent's; a subagent's 2.05M shows
  only in its card's Fields. The header stat SHOULD include subagent tokens
  ← mountain: mount-complete

- `token-count-rearrange` Rearrange the token count sections:
  - In an assistant card:

    ```
    Tokens
    ------
    Model: sonnet-4.5

      Input tokens: 24,342
            cached: 22,345 (98%)
    added to cache:  1,998

      Output tokens:   233
    ```

  - In a tool result card, one line at the top instead of a whole section:
    ```
    Tool Result -- [tool]
    ------
    Result size:  4.5 KB ~= 1,308 tokens
    ```
  - In a subagent card (or subagent results, whenever available):

    ```
    Tokens
    ------
    Model: sonnet-4.5

    Input tokens: 1,024,342
          cached:   998,345 (98%)

    Output tokens:    4,233
    ```

    ← mountain: mount-complete

- `underspecified-events-display` Session 22 added per-card context
  attribution (`context_so_far`/`new_content`/`rewrite_overhead` on every
  turn, a turn-1 system-prompt estimate, and a "dark matter" pass that
  attributes unexplained context to Underspecified attachment events —
  `deferred_tools_delta`/`mcp_instructions_delta`/`skill_listing`, newly
  un-hidden). Right now those three render as bare `ATTACHMENT /
deferred_tools_delta`-labelled cards with no styling and, only when dark
  matter landed on one, a plain "Dark matter share" line. Design an
  unobtrusive treatment that reads as "mysterious, not measured" — distinct
  from a real `estimated_input` ≈ number — and figure out how it should
  relate to `token-count-rearrange` just below and to `context-map-sidebar`
  (Next, above) using the same numbers. See
  `notes/2026-08-11-session-22-dark-matter-and-underspecified-events.md`.
  ← mountain: mount-complete

- `subagent-detail-tweaks` Move the 'log' field to 'Provenance'; give it a
  button near the top to expand/collapse its cards in the conversation
  ← mountain: mount-beautiful
- `self-host-fonts` Self-host the fonts (Tenor Sans / Sen / Cascadia Code)
  into `assets/fonts/` with `@font-face` in `story.css`, replacing the CDN
  `<link>` ← mountain: mount-beautiful
- `tool-call-summary-redundancy` Don't repeat the tool name in a tool call's
  summary (e.g. a Bash card saying "Bash") — the kind tag already says it
  ← mountain: mount-beautiful
- `css-capability-owner` A capability owner to guard the CSS and keep it
  consistent. Two things it would have caught in session 9: a `var()` on a
  token that no longer exists (fails silently), and a rule whose `opacity`
  override lost to a same-specificity rule later in the file
  ← mountain: mount-beautiful
- `related-events-detail-style` Restyle the list of related events in the
  detail view — more like the other details, less imitation of the card
  ← mountain: mount-beautiful

- `malleable-title-editable` Make the page title editable ← mountain: mount-malleable
- `check-edit-api-sidecar-bug` `bin/check-edit-api` fights a real sidecar. It
  starts `bin/serve` against an EMPTY temp edits dir, so every rebuild it
  triggers strips that story's real hand-written summaries out of
  `out/<name>/` — and its "an empty summary reverts to the generated one"
  check FAILS whenever the event it picked already has one of Jess's
  summaries (it captures that line as "generated", then compares it to the
  parser's). Surfaced the moment `episode-8-after:4` got a hand-written
  summary. Both symptoms have one cause: the temp dir doesn't mirror the real
  one. Fix is probably to seed the temp dir with a copy of
  `edits/<name>.yaml` — but then "the emptied sidecar file is gone" has to
  become "my ref is gone from it", since the file legitimately still holds
  Jess's other entries. Until fixed, `rake build` after running the checker
  restores `out/`. ← mountain: mount-malleable

- `narrate-shortcut-change` Make `n`/`p` work for "move to the next/prev
  assistant/user message" in any mode, and pick a different key for entering
  narrate mode — maybe `s` for story ← mountain: mount-interactive
- `mode-url-mismatch` A degraded or bogus `?mode=` value stays in the URL
  while the body is `mode-explore`, and pressing `x` won't clear it —
  `setMode` early-returns on a same-mode call. Cosmetic, but the one place
  the URL and body class disagree ← mountain: mount-interactive
- `narrate-hashchange-spoiler` Clicking a related-event link in the detail
  pane during narrate fires `hashchange`, and `syncFromHash` selects a card
  that's still hidden and outside the revealed prefix. No error, self-heals
  on the next beat, but mid-talk it's a spoiler ← mountain: mount-interactive
- `collapsing-sections` Collapse by beat as well as by subagent, with
  hotkeys — including collapse/expand all and collapse/expand selected
  ← mountain: mount-interactive
- `show-live-conversations` Figure out what it would take, and how it would
  look, to show conversations that are still active — based on the growing
  files in `.claude` — readable in a format that doesn't hurt the eyes
  ← mountain: mount-interactive
- `summarize-a-section` It would be helpful to be able to select a
  [note: capture cuts off here in the original file — pick this back up with
  Jess before acting on it] ← mountain: mount-interactive

## Done

- `conversation-importer` A local-only app (`bin/importer`, port 8081) lists
  recent conversations across both config dirs, grouped by project, each card
  carrying the title, first prompt, recap in full, and stats. Pressing Import
  (or Re-snapshot, for a session already in `examples/`) copies the log via
  `ConversationStory::Import` and builds that one example's story. Design in
  `notes/2026-08-18-session-25-conversation-importer-design.md`; tickets in
  `.scratch/conversation-importer/issues/`; `bin/check-importer` guards the
  write path. See CLAUDE.md's "two doors in" paragraph and README.md's
  "Bringing in a new example" section.
