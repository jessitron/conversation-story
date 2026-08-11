# Session 21 — token accounting research

2026-08-11. Not a coding session — Jess asked for primary-source research on how
the Claude API's `usage` object attributes token cost across a multi-turn
conversation, to check the assumptions baked into `parser.rb`'s turn/context
math (see CLAUDE.md's "Tokens belong to a TURN, not a record" section and
`notes/intermediate-schema.md`). No code changed. Sources are all
`platform.claude.com` docs, fetched directly — quotes below are verbatim.

Session numbering: highest existing note was session-20
(`2026-07-28-session-20-beat-flag.md`), so this is 21.

## The repo's five claims, checked

**1. A "turn" = one API call/response, keyed by `message.id`.**
Confirmed as a description of the *Messages API* — "Every response reports
what the request consumed in its `usage` field."
(context-windows.md). One API call → one response → one `usage` object.
`message.id` and the idea of several JSONL records sharing one is a **Claude
Code session-log artifact, not a Messages API concept** — the raw API returns
every content block (thinking, text, `tool_use`) together in one response's
`content` array. Claude Code's transcript format apparently explodes that one
response into several log lines, one per block, and copies the same `usage`
onto each — which is exactly what the repo's own parser comment describes
finding empirically (7 of 33 turns are bare `tool_use` with no
`assistant_message` leader). Nothing in the public docs describes the JSONL
format itself, so this half of the claim is inference from log shape, not a
documented fact — but it's the only inference that fits both the log evidence
and the documented one-response-one-`usage` rule.

**2. `context = input + cache_creation + cache_read`, `added = input + cache_creation`.**
`context` matches the docs exactly:

> "Total input tokens in a request is the summation of `input_tokens`,
> `cache_creation_input_tokens`, and `cache_read_input_tokens`."
> — api/messages reference

> "If you use prompt caching, the input count is split across `input_tokens`,
> `cache_read_input_tokens`, and `cache_creation_input_tokens`, and all three
> count toward the [context] window."
> — context-windows.md

`added` (`input + cache_creation`, i.e. context minus the reused/cached part)
is **not a named API quantity** — it's the repo's own construct, and a
reasonable one, but don't cite the docs for it. Also worth flagging: framing
`cache_read` as "already paid for" undersells `cache_creation` slightly —
a cache *write* is also billed (at a premium — see below), so `cache_creation`
isn't free either; it's just the first-time cost vs. the discounted reuse
cost, not "new" vs. "free."

**3. Only one record per turn (the turn leader) carries real `usage`.**
Consistent with #1 — since one API response yields one `usage` object, if
Claude Code's log format really does split a response's blocks across several
JSONL lines, only one of them can meaningfully "own" that object; the parser
picking the `assistant_message` record (or the turn's first record) as leader
is a reasonable choice given no doc states which line should own it. This is
squarely in "design choice this tool must make," not confirmable from the API
docs — the API has no concept of a bare-`tool_use`-without-usage record at
all.

**4. `tool_result` token cost is estimated (chars / 3.5), not derived from real `usage`.**
Confirmed: nothing in `usage` corresponds to a `tool_result` at the moment
it's produced. The only place a `tool_result`'s size is billed is as ordinary
input on whatever request carries it:

> "The additional tokens from tool use come from: ... `tool_result` content
> blocks in API requests."
> — agents-and-tools/tool-use/overview.md, "Pricing"

There's no API-reported number to use instead of an estimate for "how big was
this tool result" independent of a specific request's `usage.input_tokens` —
the char/3.5 estimate is filling a real gap, not overriding a value the API
already gives you.

**5. Prompt-caching mechanics** — cache write vs. read, tiers, one-call-both-fields, prefix vs. block granularity:

- **Writes** happen only at a `cache_control` breakpoint, and write a hash of
  the *whole prefix* up to and including that block — not the block alone:
  > "Marking a block with `cache_control` writes exactly one cache entry: a
  > hash of the prefix ending at that block. The system does not write
  > entries for any earlier position."
- **Reads** happen when that prefix hash matches an existing entry, including
  via a 20-block lookback if the exact breakpoint has no entry but an earlier
  one in the same prefix does.
- **A single call can report both** `cache_creation_input_tokens` and
  `cache_read_input_tokens` — documented directly in the multi-turn caching
  table: turn *N*+1 reads everything through turn *N*'s breakpoint from cache
  and writes turn *N*+1's new tail as a fresh entry, in the same response.
- **5m/1h split**: `usage.cache_creation` is `{ephemeral_5m_input_tokens,
  ephemeral_1h_input_tokens}`, and `cache_creation_input_tokens` "equals the
  sum of the values in the `cache_creation` object."
- **Granularity is the prefix, not the individual event.** This is the
  important one for the repo's project: the API's own unit of caching and
  billing is "everything up to a breakpoint," not "this one tool_result" or
  "this one thinking block." **Attributing cost to a single conversation
  event is therefore *always* an apportionment this tool performs on top of
  coarser-grained, prefix-level API accounting** — it is not a finer-grained
  view the API is choosing not to show you. There is no such finer-grained
  view. The per-event `≈` estimate and the `# an estimate` framing in
  CLAUDE.md are the right instinct for exactly this reason.

## The two "tentative mechanics" — now confirmed, not just plausible

**Mechanic 1 — a `tool_result`'s content costs nothing when produced; the
next turn that has to send it as input is what pays.** Confirmed by
construction, not just inference: `tool_result` blocks are literally *input*
content on the request that carries them (see #4's quote), and the API is
stateless per the context-windows doc's turn diagram — "Input phase: contains
all previous conversation history plus the current \[content]." There is no
API concept of a tool result costing anything at the moment the tool runs
(client-side tool execution happens entirely outside the API call). So this
mechanic isn't a hypothesis about how Anthropic bills — it's the *only*
coherent reading of "requests are stateless, tool_result is input content."
**Confirmed, high confidence.**

**Mechanic 2 — a turn's own output isn't counted as input anywhere until a
later turn resends it.** This one is stated explicitly, for thinking tokens,
in the primary source:

> "Billing: Thinking tokens are billed as output tokens once, when they are
> generated. On models that keep previous thinking blocks, the kept blocks
> are then part of later requests' input and are billed as input tokens,
> like the rest of the conversation history."
> — context-windows.md, "The context window with thinking"

That's the general shape of the whole conversation, not just thinking: text
and `tool_use` blocks are billed as output once, on the turn that generates
them, and only re-billed (as `input_tokens` or, once cached, `cache_read`) on
whatever later turn has to resend them as history. **Confirmed, high
confidence, and directly citable** — this is the strongest finding of the
session.

**The corollary — the very last turn's output is never re-billed as input
anywhere** — is not separately documented, but it's a trivial consequence of
"resent as history on a *later* turn": if there is no later turn, nothing
resends it. Call this a logical corollary of the confirmed mechanic, not an
independent doc claim.

## What's confirmed vs. what's still this tool's own design choice

| Claim | Status |
|---|---|
| turn = one API response, one `usage` object | Confirmed (Messages API) |
| `message.id` grouping / turn leader in JSONL | Claude-Code-log inference, not documented API behavior |
| `context` = input+cache_creation+cache_read | Confirmed, exact doc formula |
| `added` = input+cache_creation | Repo's own construct, not a named API quantity |
| tool_result cost = estimate, no real number exists | Confirmed — nothing else to use |
| cache write/read triggers, 5m/1h split, same-call both | Confirmed |
| accounting is prefix-level, not event-level | Confirmed — this is the real reason per-event attribution is an approximation |
| tool_result "costs nothing until resent" | Confirmed by construction (stateless API + tool_result is input content) |
| turn's output "free until resent" | Confirmed explicitly for thinking; generalizes to text/tool_use by the same input/output-phase model |
| last turn's output never resent | Trivial corollary, not independently documented |

## What would need repo-log inspection, not more doc reading

The docs describe the *mechanism* precisely enough that the two tentative
mechanics are now design facts, not guesses. What the docs can't give you is
a way to *verify* it against a specific real conversation without inspecting
that conversation's own turn sequence — e.g. confirming that
`episode-8-before`'s `cache_read_input_tokens` on turn *N*+1 actually equals
(or closely tracks) turn *N*'s `context`, turn over turn. That's an empirical
check against the repo's own example `.jsonl` logs, not something further doc
research would add. Nothing about it is unfalsifiable in principle — it's
just a different kind of check (log arithmetic) than "read more docs."

## Sources (all fetched directly, 2026-08-11)

- `https://platform.claude.com/docs/en/build-with-claude/prompt-caching.md`
- `https://platform.claude.com/docs/en/api/messages` (Messages API reference — `usage` object)
- `https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview.md`
- `https://platform.claude.com/docs/en/build-with-claude/context-windows.md`

One dead end worth recording: an early fetch surfaced a stray line — "Not
counted toward output tokens, and not counted toward input tokens when sent
back in subsequent turns" — that looked at first like it meant `tool_result`.
It's actually about citation `cited_text` blocks, an unrelated feature; the
tool-use overview page's explicit "tool_result content blocks in API
requests" pricing line is the real answer and contradicts that stray
reading. Flagging this because it's exactly the kind of misattribution a
second pass over the same docs could reintroduce.
