# Session 22 — attributing context growth to individual cards

2026-08-11, continuing session 21's research
(`notes/2026-08-11-session-21-token-accounting-research.md`). That session
confirmed the API facts; this one turns them into an actual per-card
attribution algorithm in `lib/conversation_story/parser.rb`, plus a first
(unstyled) render of it. **Display is deliberately not done** — that's the
next agent's job, working from this note plus `notes/intermediate-schema.md`.

## The identity that makes this checkable, not just plausible

Every turn's real `usage` splits into three buckets that are mutually
exclusive: `cache_read` (served from a valid cache entry), `cache_creation`
(written to cache this call), `input` (the uncached tail after the last
`cache_control` breakpoint — typically 1–3 tokens; if caching isn't happening
at all, everything lands here instead and the other two are 0).
`context = input + cache_creation + cache_read` always, `added = input +
cache_creation`, both already existed. New this session:

```
rewrite_overhead = max(0, previous_turn.context - this_turn.cache_read)
context_so_far   = this_turn.cache_read + rewrite_overhead
new_content      = this_turn.cache_creation - rewrite_overhead
```

`rewrite_overhead` isolates cache-creation that's re-paying OLD content
(the previous turn's context didn't come back whole as `cache_read` — a TTL
lapse, or the breakpoint walked outside the 20-block lookback per session
21's prompt-caching findings) from genuinely NEW content. This makes
`context_so_far + new_content + input == context` true by construction
(substitute and the `rewrite_overhead` terms cancel) — a real identity, not
an estimate. Stronger: `context_so_far` should equal `previous_turn.context`
**exactly**, whenever `cache_read ≤ previous_turn.context` (the normal case).
Checked against `episode-8-before`: turns 2–4's `context_so_far` matched
turns 1–3's `context` exactly (24456→24456, 26189→26189, 26516→26516), with
`rewrite_overhead` sitting at 0–3 tokens (noise from the uncached tail, not a
real cache event). If `context_so_far` is ever NOT equal to the previous
turn's context, that's a real anomaly (compaction, a bug, something odd) —
not a rounding difference to shrug off.

Implemented in `Parser#mark_turns!`; printed on every turn-leader card's
Tokens section by `Renderer#tokens_section` (rows: Context so far, New
content, Re-cached (overhead) — only when >0, Context, Added, Cache write,
Output, Total input).

## Turn 1: system prompt + tools, named but not measured

Turn 1's `added` bills the system prompt, the tool schemas, and the first
user message together as one cache write — prompt caching hashes the whole
`tools -> system -> messages` prefix (session 21), so there's no line-item
for the system/tools portion. The first user message's own size IS
independently estimable (chars, same estimator as everything else — see
below), so `Parser#mark_first_turn_breakdown!` computes:

```
system_prompt_estimate = max(0, turn_1.added - first_message.estimated_input)
```

and stores it on the first `user_message` event. `Renderer#first_message_tokens_section`
shows both numbers under "Turn 1 breakdown" instead of the normal Tokens
section (`Renderer#tokens_section` dispatches to it when
`tokens.system_prompt_estimate` is present).

## The chars-based estimate is no longer tool_result-only

`Parser#add_result_token_estimate` (chars / `CHARS_PER_TOKEN`, labelled with
a `≈` and a caveat note — never presented as a measurement) used to run only
for `tool_result`. It's now called for every kind in `ESTIMATE_KINDS`:
`user_message`, `coordinator_message`, `tool_result`, `task_notification`,
`queue_operation`. These are the kinds whose logged text genuinely IS what
gets sent to the model — `attachment` is deliberately excluded, because
`queued_command`'s content re-arrives as its own estimable event once
delivered (the existing queue-detour design), and the Underspecified
attachment types' content (below) isn't what's actually billed at all.
Every mid-conversation user message, task notification, and queued payload
now shows a `≈` estimate the same way a tool_result always has — this was a
straightforward generalization, not new machinery.

(Correction from earlier in this session: an estimate needs a `~`/`≈` and a
caveat note, not omission — "an estimate that reads like a measurement is
worse than no number" was too strong a rule and got softened in
`renderer.rb`'s comments. Jess's call.)

## Dark matter and Underspecified Events

For turn 2 onward, a turn's `new_content` (above) SHOULD be fully explained
by two known things: the previous turn's own real `output` (thinking/text/
tool_use it generated, now being resent as history for the first time — a
real number, not an estimate) plus every intervening event's `estimated_input`
(tool_results, a user message, notifications — anything between the two
turns that isn't part of either turn's own assistant blocks). Whatever's left
over after subtracting both is real, billed context with **no card whose
content explains it** — named "dark matter" rather than silently dropped.

`Parser#mark_dark_matter!` walks the event list once, accumulating a
`window` of non-assistant events since the last turn leader, and at each new
turn leader computes:

```
explained   = window.sum(estimated_input)
dark_matter = this_turn.new_content - previous_turn.output - explained
```

If `dark_matter > 0`, it's attributed to any **Underspecified** attachment
event in that same window — `deferred_tools_delta`, `mcp_instructions_delta`,
`skill_listing` (`Parser::UNDERSPECIFIED_ATTACHMENT_TYPES`). These three
record that the system/tools portion of context changed mid-conversation
(new tools deferred in, MCP instructions updated, a skill listed) — real
cost, but their own logged content is a name list or delta reference, not
the actual schema/instruction text that's billed, so a chars estimate of the
record itself would be misleadingly small. They're the mid-conversation
recurrence of turn 1's "system prompt" bucket: named as mysterious rather
than measured, sharing `dark_matter_estimate` evenly when more than one is in
the window. **Un-hidden this session** (`HIDDEN_ATTACHMENT_TYPES` no longer
includes them) so there's a card to carry the number — currently a bare
`ATTACHMENT / deferred_tools_delta`-labelled card with no styling of its own.
**Unobtrusive display of these, and of a `dark_matter_estimate` share
generally, is the open work for the next agent.**

If dark matter shows up with **no** Underspecified candidate in the window,
but there IS a `hook_success` attachment there, `mark_dark_matter!` logs a
warning instead of guessing:

```
conversation-story: N tokens of unexplained context before <ref>, and the
only candidate in that window is hook_success <ref> — maybe hook output
does reach the model after all?
```

## Why hook_success stays hidden, and what running it against real logs showed

None of the four attachment types above carry a `message` field — unlike
every real conversation record (`tool_result`, `user_message`,
`queued_command`, ...), which all do. That's consistent with these being
harness-internal bookkeeping rather than literally sent to the model. Three
of the four (the Underspecified ones) still get a real dark-matter share
when the arithmetic demands one, because SOMETHING changed the system/tools
context and they're the recorded evidence of what. `hook_success` is
different: it carries genuine prose (hook stdout), but there's no comparable
"the system/tools context changed" reasoning to justify attributing cost to
it — so it was left fully hidden, and the warning above exists to test that
assumption empirically rather than argue it from the log shape alone.

Running `mark_dark_matter!` against all five example logs:

| example | `hook_success` count | hook(s) firing | dark-matter-blames-only-hook_success warnings |
|---|---|---|---|
| `episode-8-before` | 82 | `~/bin/claude-hook` on `PreToolUse`/`PostToolUse` for Bash/Read/Grep/Glob/Write/Agent, plus `UserPromptSubmit`/`Stop` | 26, ranging 11–**2549** tokens |
| `episode-8-after` | 58 | same `~/bin/claude-hook` setup | 25, ranging 4–328 tokens |
| `mode-switches` | 1 | `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd session-start`, `SessionStart:startup` only | 0 |
| `inlining-subagents` | 1 | same, `SessionStart:startup` only | 0 |
| `mtg-tabletop-plan` | 0 | none | 0 (its dark matter — 829 tokens, twice — landed on real Underspecified candidates: a `deferred_tools_delta`/`mcp_instructions_delta` pair, not a guess) |

The two `episode-8` examples ran a **custom per-tool-call hook** — old,
apparently from `~/bin/claude-hook` — and show dark matter on nearly every
turn, correlated with a hook_success in the window every single time,
including one 2549-token spike. The three more recent examples run a
**plugin-managed, session-start-only** hook and show zero such warnings.
That's a real before/after, not noise from the estimator: a hook that fires
on every tool call correlates with a consistent per-turn token cost; a hook
that fires once at session start doesn't. Read as a signal that the old
`~/bin/claude-hook` setup's stdout WAS reaching the model's context on every
tool call, and whatever's running now doesn't do that (or does far less of
it) — worth confirming directly (would need to trace an actual live
conversation with today's hooks configured, or check whether they use
`hookSpecificOutput.additionalContext`), but the log evidence alone already
points the same direction Jess's hook change did.

## What's still open (for the display agent, or later)

- **No per-block split of a turn's own output.** `mark_dark_matter!` uses
  the previous turn's `output` as one lump sum; it does NOT divide that
  total across the turn's own thinking/text/tool_use blocks (a "Pass A" that
  was designed in conversation but never implemented — chars-estimate each
  block, scale to sum to the real `output`). Every turn-leader card already
  shows the turn's real `output` as one number; individual non-leader blocks
  of that same turn show nothing.
- **Old-model thinking-strip behavior is unhandled.** Session 21 found that
  whether previous thinking blocks stay in context is model-dependent
  (kept by default on Opus 4.5+/Sonnet 4.6+/Fable 5/Mythos 5; stripped on
  older models at the next real user turn). The plan agreed in conversation
  was "warn on older models, then treat everyone as if they keep thinking" —
  the warning was never implemented. On an old-model log this would show up
  as extra, illegitimate dark matter (the previous turn's `output` included
  thinking that was actually dropped before resend, so subtracting the full
  `output` overshoots and the leftover reads as "dark matter" that isn't).
- **Unobtrusive display.** `deferred_tools_delta`/`mcp_instructions_delta`/
  `skill_listing` currently render as plain attachment cards with a raw
  type-name summary (e.g. "deferred_tools_delta") and, only when dark matter
  landed on them, a "Dark matter share" line via `Renderer#result_tokens_section`.
  Nothing about the display distinguishes "Underspecified" as a category —
  that's this note's main unfinished business.
- **`hook_success` itself** is still hidden; the warning is instrumentation
  for deciding its fate, not a decision.

## Where the code is

- `lib/conversation_story/parser.rb`: `mark_turns!` (context_so_far/
  new_content/rewrite_overhead), `mark_first_turn_breakdown!`,
  `mark_dark_matter!` + `attribute_dark_matter!` + `underspecified_attachment?`,
  `ESTIMATE_KINDS`, `UNDERSPECIFIED_ATTACHMENT_TYPES`, `HIDDEN_ATTACHMENT_TYPES`
  (now just `%w[hook_success]`), `add_result_token_estimate` (generalized).
- `lib/conversation_story/renderer.rb`: `tokens_section` (dispatches to
  `first_message_tokens_section` when applicable), `result_tokens_section`
  (now shows a `dark_matter_estimate` row too), `generic_sections` (calls
  `result_tokens_section` for the newly-estimable kinds).
- `notes/intermediate-schema.md` has the field-level schema documentation,
  updated alongside this note.
