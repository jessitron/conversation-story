# Conversation Story — Intermediate Schema

This is the **intermediate schema**: the shape of the `story.yaml` "story"
document that `bin/parse` emits and `bin/render` consumes. It is the **contract**
between the two programs — the renderer reads this schema, never the original log.

This is an **informal, working document**, not a formal spec. Refine it as we
learn more about the log format. The settled high-level **Decisions** live in
`plan.md`; this file describes the actual shape.

Design principle: **one ordered list of events**, each with a tiny `summary`
(default view) and a `detail` payload (drill-in). Everything in the log is
representable; unknown things fall back to a generic event so nothing is dropped.

Jess's required fields (learned from a prior attempt) are all folded in below:
token counts, provenance (source file + line), queued status, linking data,
per-event agent identity, and wall-clock time.

```yaml
# conversation document
meta:
  source: episode-8-before.jsonl        # main log file
  session_id: 6c8fe8d4-...
  git_branch: main
  cwd: /Users/jessitron/code/...
  version: "..."                        # claude version from records
  started_at: "2026-04-14T02:27:16.236Z"  # first timestamp (UTC)
  ended_at:   "2026-04-14T02:35:...Z"
  timezone: UTC                         # timestamps are UTC 'Z'
  event_count: 224
  total_tokens: 1212680                 # whole-conversation token USE: every
                                        #   turn's context + output, each turn
                                        #   counted once (NOT a context size)
  agents:                               # every conversation represented
    - id: main                          # the primary conversation
    - id: agent-ae20659fd0f63295e       # a subagent (from subagents/)
      agent_type: Explore
      description: "Explore timeline/replay features"
      spawned_by_tool_use: toolu_01X8...   # the Agent tool_use that started it

events:
  - id: dc51411e-...             # from uuid
    agent: main                  # REQUIRED on every event: which conversation.
                                 #   (c) Use explicit `agentId` when the record
                                 #   has one (subagent records); else 'main'.
    parent: <uuid|null>          # from parentUuid, for threading
    kind: assistant_message      # see kinds below
    role: assistant              # user | assistant | system | null
    model: claude-opus-4-6       # (b) assistant turns: which model produced it
    stop_reason: tool_use        # (b) end_turn | tool_use | max_tokens | ...
    stop_details: null           # (b) verbatim when present
    stop_sequence: null          # (b)
    at: "2026-04-14T02:27:16.236Z"   # timestamp (UTC, may be null)
    queued: false                # whether this was queued (see queue below)
    summary: "..."               # one line; policy TBD, adjustable later
    summary_edited: true         # (omitted unless true) the summary above is
                                 #   Jess's, from edits/<name>.yaml — see below
    detail:                      # kind-specific; free-form under a known shape
      text: "full text..."

    # --- provenance: REQUIRED on every event ---
    source:
      file: episode-8-before.jsonl   # or subagents/agent-....jsonl
      line: 42                       # 1-based line in that jsonl (one rec/line)

    # --- linking data: whatever connects this event to others ---
    links:
      uuid: dc51411e-...
      parent_uuid: <uuid|null>
      message_id: <msg_...|null>     # present on some assistant records
      request_id: <req_...|null>
      prompt_id: <...|null>
      source_tool_assistant_uuid: <uuid|null>  # on tool_result records
      tool_use_id: toolu_01X8...     # on tool_call/tool_result, pairs them

    turn_leader: true            # (omitted unless true) this record shows the
                                 #   turn's token numbers — see "Turns" below

    # --- tokens: all counts, named (NO raw passthrough) ---
    tokens:
      # as reported by the API:
      input: 3
      output: 322
      cache_creation: 10619
      cache_read: 13834
      ephemeral_1h: 10619
      ephemeral_5m: 0
      service_tier: standard
      iterations:                    # per-internal-round-trip breakdown, named
        - { input: 3, output: 322, cache_read: 13834, cache_creation: 10619 }
      # derived, and ONLY on the turn_leader (see "Turns"):
      context: 24456                 # input + cache_creation + cache_read —
                                     #   the whole context actually sent
      added: 10622                   # input + cache_creation — what was new
      cumulative_context: 24456      # running sum of `context` over turns
      # derived (session 22) — splits `added`/`cache_creation` into content
      # that's genuinely new vs. old content re-paid because it fell out of
      # cache (TTL lapse, or the breakpoint walked past the 20-block
      # lookback). context_so_far should equal the PREVIOUS turn's `context`
      # exactly — a sanity check, not just another estimate. See
      # notes/2026-08-11-session-22-dark-matter-and-underspecified-events.md.
      rewrite_overhead: 3            # max(0, previous_turn.context - cache_read)
      context_so_far: 24456          # cache_read + rewrite_overhead
      new_content: 1732              # cache_creation - rewrite_overhead

    # --- tokens on a tool_result, user_message, coordinator_message,
    #     task_notification, or queue_operation `enqueue`: an ESTIMATE, named so
    #     (Parser::ESTIMATE_KINDS; session 22 generalized this beyond tool_result) ---
    tokens:
      result_chars: 4568             # length of the event's own text
      estimated_input: 1305          # result_chars / Parser::CHARS_PER_TOKEN
      # only on an Underspecified attachment event that a dark-matter pass
      # (session 22) had to attribute unexplained context to — see below:
      dark_matter_estimate: 829

    # --- tokens on the FIRST user_message ONLY (session 22) ---
    tokens:
      result_chars: 216
      estimated_input: 62             # this message's own share (chars-based)
      system_prompt_estimate: 10560   # turn_1.added minus this message's own
                                       #   share — the system prompt + tool
                                       #   schemas, named but not measured
                                       #   (caching hashes them together with
                                       #   the first message; no line-item to
                                       #   read their size off of)

    # --- tool events add: ---
    tool:
      name: Agent
      use_id: toolu_01X8...
      input: { ... }                 # the tool's arguments (structured, named)
      result_ref: <event id of the result>
      is_error: false                # (b) did the tool call fail
      duration_ms: 307               # (b) from toolUseResult.durationMs
      result:                        # (b) named fields from toolUseResult
        content: "..."               #   the text result the model saw
        # tool-specific, named (only what we display; follow source for the rest):
        stdout: "..."                #   Bash
        stderr: "..."                #   Bash
        interrupted: false
        structured_patch: [ ... ]    #   Edit/Write diffs
        num_files: 3                 #   Glob/Grep
      subagent_tokens:               # (b) for Agent calls — subagent's own totals
        total_tokens: 124053
        total_tool_use_count: 27
        tool_stats: { ... }
      # on an Agent call's RESULT, from toolUseResult — which subagent answered:
      agent_id: agent-ae20659fd0f63295e
      agent_type: Explore
      status: completed
      # NOTE: no `approval:` field — these logs carry no per-tool approve/deny.
      # Add it later if a newer example log includes real approval data.

    # --- an Agent call OWNS a whole other conversation (kind: subagent) ---
    subagent:
      agent_id: agent-ae20659fd0f63295e   # matches meta.agents[].id
      agent_type: Explore
      description: "Explore timeline/replay features"
      log: agent-ae20659fd0f63295e.jsonl  # under <example>/subagents/
      meta: { ... }                # that story's OWN meta, same shape as above
      events: [ ... ]              # that story's OWN events, same shape, nested

  - id: ...
    agent: main
    kind: unknown                # FALLBACK ONLY: unrecognized record type.
    summary: "some-new-type"
    source: { file: ..., line: ... }
    detail: { raw: { ...original json... } }   # raw kept ONLY for unknown
```

## The schema is the contract — no raw for known types

Every event has `source: {file, line}` and the source logs are **committed**, so
the raw record is always one hop away for a human. Therefore:

- **Known event kinds store only named fields. No `raw`/source-JSON blob.** The
  renderer reads the schema, never the original log. Anything we want to display
  must be promoted to a named field here first.
- **`raw` survives on exactly one kind: `unknown`** — the fallback for record
  types we don't recognize yet, so nothing is silently lost while we're still
  discovering the format. When we learn a new type, we give it named fields and
  it stops being `unknown`.

## Hand edits live outside this document

`story.yaml` is **generated**, and stays that way. Hand edits are stored in a
sidecar, `edits/<name>.yaml`, keyed by event `ref` and split into two named
sections (session 20 added the second):

```yaml
summaries:
  episode-8-before:15: Here's how it works today...
beats:
  episode-8-before:35: false
```

`bin/parse` overlays both onto the freshly parsed document. A rewritten
`summaries:` entry sets `summary` and stamps `summary_edited: true`. A
`beats:` entry overrides where narration stops (see `beat`, below the `hidden`
field): `true` sets `event["beat"] = true`; `false` **deletes** the `beat` key
rather than storing `false`, so an override and the parser's own "not a beat"
converge on one shape — the key is `true` or absent, never `false`. `story.js`'s
`isBeat` reads it strictly (`c.dataset.beat === 'true'`); the renderer
(`renderer.rb`) and `bin/serve`'s response both do a plain truthiness check
(`event["beat"] ? … : …`, `!!event["beat"]`), which is safe only because the
value is never anything but `true` or missing — a genuine `false` would read
the same as absent either way, so nothing anywhere needs to, or does, tell them
apart. So the story is derived from *the log plus the sidecar*, and a
parser improvement still reaches every event Jess hasn't touched. Nothing
needs a "don't overwrite me" lock.

`summary_edited` is the one thing the renderer needs from the summaries side:
it means "print this text verbatim", which beats the composed card faces (a
`tool_call` normally ignores `summary` and draws its tool name plus primary
argument). It also gets a `data-edited` attribute on the card, which only the
local editing UI reacts to. A beat override gets no such stamp — there's no
composed card face for a beat to beat, and nothing to mark.

Keying by `ref` ties an edit to a line number, so editing a log orphans its
edits. `Edits#apply` returns the refs that matched nothing (from either
section) and `bin/parse` warns about them — deliberately noisy, since the
alternative is losing Jess's words, or a chosen beat, in silence.

## Subagents: a nested document, not more entries in the list

An `Agent` tool call isn't really a tool call — it's another whole conversation,
logged in its own file under `<example>/subagents/`. So the two records the main
log holds get reclassified:

| main-log record | kind | what it is |
|---|---|---|
| the `tool_use` | `subagent` | the job handed over, plus the nested story |
| its `tool_result` | `subagent_result` | the answer coming back to the caller |

and the subagent's log is parsed **by the same `Parser`, recursively**, landing
under the call as `subagent.meta` + `subagent.events`. That recursion is the
whole design: the nested story gets its own refs (`agent-ae2065…:2`, from *that*
file's name and line numbers), its own turn election, its own token running
total, and its own `tool_call`↔`tool_result` links — none of which can collide
with or leak into the parent's, because none of it is derived from the parent.

The hinge is `toolUseResult.agentId`, not the tool's name: the name has changed
across Claude versions (`Task`, now `Agent`), that field hasn't, and it appears
only on a real subagent result. A missing log file is fine — the card renders
with nothing to expand into.

Nested events deliberately do **not** join the parent's flat `events` list:
that list is one-event-per-line of the main log (`event_count` == line count).
Two consequences worth knowing:

- **Anything that counts cards has to walk the tree**, not the list (the
  renderer's `all_visible_events`, `test/story_events.rb`, `bin/serve`'s ref
  lookup, `Edits#apply`). The header's *Events* stat is the exception on
  purpose: it stays the size of the conversation being told, top-level and
  visible, which is also what `bin/site-index` counts.
- **`meta.total_tokens` stays the parent's own token use.** A subagent's context
  is its own — reported by `subagent.meta.total_tokens` (its whole run's use, in
  the millions) and by the Agent result's `tool.subagent_tokens.total_tokens`
  (what the harness reports for the run, ~124k here). Two different measures of
  two different things; the page labels them apart.

The subagent log's **first record is the prompt it was handed** — the same string
the parent's Agent call already shows — so it's marked `hidden: true` (still in
the document, like every other hidden record).

## Turns: one API response, several records, one set of numbers

An assistant "turn" is one API response, and the log splits it across several
records — a thinking block, a text block, one per `tool_use` — all carrying the
same `message.id`. **Every one of them repeats the whole turn's `usage`.** So
token counts are a fact about the turn, not the record: attributing them
per-record triples a running total, and prints identical numbers on three cards.

`links.message_id` is what makes the turn visible in the schema. Each turn
elects one **`turn_leader`** — the `assistant_message` record when the turn
produced prose, the turn's first record otherwise. Only the leader carries the
derived `context` / `added` / `cumulative_context`. The fallback is not
hypothetical: 7 of 33 turns in episode-8-before and 11 of 28 in episode-8-after
are bare `tool_use` with no text block, and without it their tokens — and the
jump they cause in the running total — would appear on no card at all.

The header's **Tokens** stat is `meta.total_tokens` — every turn's context plus
its output, each turn counted once. It is token *use*, which is why the stat
isn't called Context: most of that 1.21M is the same context re-sent each turn
and mostly served from cache. A conversation's largest context is far smaller
(45k here); the per-turn `context` field is where you read that.

`message_id` deliberately does **not** go into `link_ids`. That token drives the
board-wide causal highlight, and lighting a whole turn on every selection would
drown out the `tool_call`↔`tool_result` chains it exists for. The renderer
indexes `links.message_id` separately for the "Tool calls in this turn" section.

## Tool result tokens are estimated, and named so

A tool result is the thing that actually grows the context, but nothing counts
it: `usage` appears on assistant records only. The one measured signal is the
context delta at the next turn, and in the example logs that gap **always** also
holds harness records — 0 of 32 gaps contain a tool result by itself — so it
cannot be attributed cleanly. Hence `estimated_input`, from length over
`Parser::CHARS_PER_TOKEN` (3.5).

The name matters: it is **not** `input`, so nothing downstream can conflate our
arithmetic with a number the API reported, and the renderer prints it with a `≈`
plus a visible caveat. Calibration against those deltas put the median near 2.5
chars/token, but the delta overstates the result's own share (it covers the
whole gap) and tool output is code and JSON, which tokenizes denser than the
prose-tuned 4 — 3.5 splits the difference.

## Notes on the required fields

- **Tokens**: capture every count as a **named field** — input/output, cache
  creation & read, `ephemeral_1h`/`ephemeral_5m`, `service_tier`, and the
  per-`iterations` breakdown as a named list. No `raw` passthrough. Subagent
  totals (`total_tokens`, `total_tool_use_count`, `tool_stats`) come from the
  spawning `Agent` call's `toolUseResult` and live under `tool.subagent_tokens`.
- **Provenance**: jsonl is one record per line, so `{file, line}` is exact.
  Content blocks within a record share that record's line.
- **Hidden**: some records are harness bookkeeping, not part of the conversation
  "from Jess's perspective". The parser still emits them as events (so nothing is
  lost and `event_count` == line count), but marks them `hidden: true`; the
  renderer skips hidden events and its header "events" stat counts only visible
  ones. Hidden set: kinds `system`, `file_snapshot`, `permission_mode`,
  `ai_title`; the `last-prompt` record; and the `hook_success` attachment
  subtype. **Kept visible** (deliberately): all `queue_operation`s — including
  the bare `dequeue`/`remove` markers, so the enqueue→deliver lifecycle is
  legible — plus attachments `queued_command` (delivered queued input AND
  background `<task-notification>`s), `task_reminder` (the system nudging the
  agent), and (session 22) `deferred_tools_delta`/`mcp_instructions_delta`/
  `skill_listing` — the Underspecified attachment types, see below. The
  field is omitted (not `false`) on visible events. See
  `notes/2026-07-20-session-6-hidden-events.md` for the original rationale and
  `notes/2026-08-11-session-22-dark-matter-and-underspecified-events.md` for
  why the three Underspecified types moved from hidden to visible.
- **`attachment_type`** (session 22): the attachment's own subtype (e.g.
  `hook_success`, `queued_command`), stored directly on every `kind: attachment`
  event — previously only reachable by re-reading the log, which the schema's
  own contract forbids. Lets downstream code (the dark-matter pass, and any
  future display work) tell attachment subtypes apart without a raw passthrough.
- **Underspecified attachment events** (session 22): `deferred_tools_delta`,
  `mcp_instructions_delta`, `skill_listing` record that the system/tools
  portion of context changed mid-conversation, but their own logged content
  (a name list or delta reference) isn't the schema/instruction text actually
  billed — so they carry no `estimated_input` of their own, only a
  `dark_matter_estimate` when a dark-matter pass had unexplained context to
  attribute nearby. They're the recurring, mid-conversation version of turn
  1's `system_prompt_estimate`. No dedicated display treatment yet — see the
  session 22 note.
- **Queued**: `queue-operation` events (`operation: enqueue`, etc.) carry
  `content` referencing a `tool-use-id` and `task-id`. The visible `enqueue`
  event stores that content in `detail.text` (e.g. a "…failed with exit code 1"
  notification). The bare `dequeue` marker is hidden (no content of its own);
  instead, the parser matches it to whichever event actually delivers that
  content — a `task_notification` by `task-id`, or a plain queued Jess message
  by exact text match — and sets `dequeued: true` there, so the renderer can
  flag "this arrived via the queue, not as an ordinary turn" on the event that
  has something to show. The enqueue's `summary` is that payload verbatim, with
  no "Queue enqueue:" prefix: the card's gutter already says Queue and the
  renderer badges `operation`, so the prefix only pushed the words that matter
  past the two-line clamp.
- **`status`**: how a background job ended, lifted from `<status>…</status>`
  inside a `<task-notification>` blob. Present on the three kinds that can carry
  one — a delivered `task_notification`, a queue `enqueue` of one, and the
  `queued_command` attachment that redelivers it — and absent everywhere else,
  including an enqueue of text Jess typed. Read the tag, never the phrasing of
  `<summary>` ("… failed with exit code 1"): the tag is the harness's own word
  for it and doesn't vary. The renderer draws `status: failed` as the same Error
  badge a failed `tool_result` wears.
- **Beat** (session 20): `beat: true` marks where narration stops — `n` / `p` /
  shift+arrow step from one beat to the next. The parser sets it on every
  main-thread `user_message` and `assistant_message` (`Parser::BEAT_KINDS`),
  reproducing what `story.js` used to hard-code from CSS classes. Emitted only
  when true, like `hidden`, and **never set inside a subagent** — a subagent's
  log is parsed by the same `Parser` recursively
  (`Parser.new(path, nested: true)`), and a nested parser sets no `beat` at
  all, because a beat never stops inside a subagent (session 15). Jess can
  override it per card in edit mode; the override lives in `edits/<name>.yaml`'s
  `beats:` section (see "Hand edits", above) and can turn a default beat off or
  add one the parser wouldn't guess — a tool call, or an event inside a
  subagent.
- **Approval**: these example logs contain **no per-tool approve/deny record**
  (only global `permission-mode` change events and `stop_hook_summary` hooks), so
  we emit no approval field. Newer Claude logs may include real approval data; we
  add it when an example with it appears.
- **Agent identity**: records carry an explicit `agentId` in subagent files; use
  it directly for `agent:` (fall back to `main` when absent). `isSidechain`
  (`false` in the main log, `true` in subagent files) corroborates it. Every
  event gets `agent:` so subagent and main events coexist in one document and can
  be filtered/grouped by conversation.
- **Newly captured (b)**: `model`, `stop_reason`/`stop_details`/`stop_sequence`
  on assistant turns; `tool.is_error` and `tool.duration_ms`; the named
  `tool.result` fields (content, stdout/stderr, structured_patch, …); and
  `tool.subagent_tokens`. These were previously in the log but not in the schema.

## Event `kind`s (initial set + fallback)

- `user_message`, `assistant_message` (text)
- `thinking` (assistant reasoning block)
- `tool_call` (from `tool_use`) and `tool_result` — paired via `use_id`
- `subagent` (an `Agent` tool_call that owns a nested story) and
  `subagent_result` (that story's answer arriving back in the parent)
- `system`, `permission_mode`, `file_snapshot`, `ai_title`, `attachment`, `queue_operation`
- `unknown` — **the fallback**; keeps `detail.raw` verbatim so Mountain 1 can
  still render a card and we never lose data (satisfies the "good fallbacks"
  constraint).

Nested subagent stories are the *same document shape* recursively, so the
renderer handles them with the same code.
