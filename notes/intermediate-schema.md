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

    # --- tokens: all counts, named (NO raw passthrough) ---
    tokens:
      input: 3
      output: 322
      cache_creation: 10619
      cache_read: 13834
      ephemeral_1h: 10619
      ephemeral_5m: 0
      service_tier: standard
      iterations:                    # per-internal-round-trip breakdown, named
        - { input: 3, output: 322, cache_read: 13834, cache_creation: 10619 }

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
        total_tokens: 45231
        total_tool_use_count: 12
        tool_stats: { ... }
      # NOTE: no `approval:` field — these logs carry no per-tool approve/deny.
      # Add it later if a newer example log includes real approval data.
    # Agent tool events also link to the nested story:
    subagent:
      agent_id: agent-ae20659fd0f63295e   # matches meta.agents[].id
      story: subagents/agent-ae20659fd0f63295e   # its events are in this doc too

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

## Notes on the required fields

- **Tokens**: capture every count as a **named field** — input/output, cache
  creation & read, `ephemeral_1h`/`ephemeral_5m`, `service_tier`, and the
  per-`iterations` breakdown as a named list. No `raw` passthrough. Subagent
  totals (`total_tokens`, `total_tool_use_count`, `tool_stats`) come from the
  spawning `Agent` call's `toolUseResult` and live under `tool.subagent_tokens`.
- **Provenance**: jsonl is one record per line, so `{file, line}` is exact.
  Content blocks within a record share that record's line.
- **Queued**: `queue-operation` events (`operation: enqueue`, etc.) carry
  `content` referencing a `tool-use-id` and `task-id`. Parser resolves these to
  set `queued: true` on the related event, and also emits the queue-operation as
  its own event so the raw fact is visible.
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
- `subagent` (an `Agent` tool_call that owns a nested story)
- `system`, `permission_mode`, `file_snapshot`, `attachment`, `queue_operation`
- `unknown` — **the fallback**; keeps `detail.raw` verbatim so Mountain 1 can
  still render a card and we never lose data (satisfies the "good fallbacks"
  constraint).

Nested subagent stories are the *same document shape* recursively, so the
renderer handles them with the same code.
