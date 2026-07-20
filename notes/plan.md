# Conversation Story — Getting Started Plan

## Context

Brand-new project. The README lays out a clear vision: turn a Claude agent
conversation log into an explorable, pretty static web page so Jess can narrate
"how a conversation went" while a page shows it accurately. Architecture is
fixed: **Input Logs → Intermediate YAML → Output HTML**, three separate Ruby
programs, static output.

Jess's chosen approach: **design the intermediate schema on paper first**, before
writing code. Ruby managed via **rbenv/asdf**. This plan therefore focuses on
(1) a proposed intermediate schema, and (2) the project layout + staged build to
agree on. No code yet.

## What's already here

- `README.md` — vision, four "Mountains", constraints, accepted limitations.
- `examples/episode-8-before.jsonl` (224 lines) and `episode-8-after.jsonl`, each
  with a `subagents/` dir containing `agent-*.jsonl` + `agent-*.meta.json`.

### Log format (observed in episode-8-before)

- Top-level event `type`s: `user`, `assistant`, `system`, `attachment`,
  `file-history-snapshot`, `permission-mode`, `queue-operation`, `last-prompt`.
- `assistant`/`user` events hold a `message.content` array of blocks:
  `thinking`, `text`, `tool_use`, `tool_result`.
- Tools seen: `Agent`, `Grep`, `Read`, `Glob`, `Bash`, `Write`.
- **Linkage facts** the schema must preserve:
  - `tool_use` block: `{id, name, input}`.
  - matching `tool_result` (in a later `user` event): `tool_use_id` → the
    `tool_use.id`; also carries richer `toolUseResult` + `sourceToolAssistantUUID`.
  - `parentUuid` chains events; `uuid` identifies each.
  - `isSidechain` flags subagent turns; `Agent` tool_use links to a
    `subagents/agent-*.jsonl`, described by a sibling `.meta.json`
    (`{agentType, description}`).
- **Subagents (resolved)**: in this example, subagent turns live in the separate
  `subagents/*.jsonl` files, all flagged `isSidechain: true`, sharing the main
  `sessionId` but with their own `parentUuid` chain. The parser reads those files
  too and tags their events with an `agent:` id. (Still worth handling the
  case where a future log inlines sidechains.)

## Proposed intermediate schema (the "on paper" deliverable)

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
    agent: main                  # REQUIRED on every event: which conversation
                                 #   'main', or a subagent id. Derived from
                                 #   isSidechain + which file it came from.
    parent: <uuid|null>          # from parentUuid, for threading
    kind: assistant_message      # see kinds below
    role: assistant              # user | assistant | system | null
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

    # --- tokens: full usage, verbatim, on assistant messages ---
    tokens:
      input: 3
      output: 322
      cache_creation: 10619
      cache_read: 13834
      ephemeral_1h: 10619
      ephemeral_5m: 0
      service_tier: standard
      raw: { ...entire usage object... }   # keep everything, unflattened too

    # --- tool events add: ---
    tool:
      name: Agent
      use_id: toolu_01X8...
      input: { ... }                 # verbatim
      result_ref: <event id of the result>
      # NOTE: no `approval:` field — these logs carry no per-tool approve/deny.
      # Add it later if a newer example log includes real approval data.
    # Agent tool events also link to the nested story:
    subagent:
      agent_id: agent-ae20659fd0f63295e   # matches meta.agents[].id
      story: subagents/agent-ae20659fd0f63295e   # its events are in this doc too

  - id: ...
    agent: main
    kind: unknown                # FALLBACK: preserves raw for anything new
    summary: "queue-operation"
    source: { file: ..., line: ... }
    detail: { raw: { ...original json... } }
```

### Notes on the required fields

- **Tokens**: the log's `usage` object is rich (input/output, cache creation &
  read, `ephemeral_1h`/`ephemeral_5m`, `service_tier`, per-`iterations`
  breakdown). Capture named fields *and* keep `raw` so nothing is lost.
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
- **Agent identity**: `isSidechain` is `false` in the main log and `true` in
  subagent files (which share the session id but have their own parentUuid
  chain). Every event gets `agent:` so subagent and main events coexist in one
  document and can be filtered/grouped by conversation.

### Event `kind`s (initial set + fallback)

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

## Proposed project layout

```
.ruby-version                 # for rbenv/asdf
Gemfile                       # minimal; minitest only to start
bin/parse                     # logs dir/file  -> intermediate YAML  (stdout or -o)
bin/render                    # intermediate YAML -> static HTML dir
bin/serve                     # serve the HTML dir (ruby -run -e httpd or tiny Rack)
lib/
  conversation_story/
    parser.rb                 # jsonl -> document (Ruby hash), with fallbacks
    schema.rb                 # document/event value objects + validation
    renderer.rb               # document -> HTML via ERB
    templates/                # ERB: page + event-card partial
out/                          # generated site — COMMITTED (Jess's choice)
test/
  parser_test.rb              # golden-fixture tests against examples/
  fixtures/
```

- **Stdlib-first**: `json`, `yaml`, `erb` are built in. Only dev dep is
  `minitest`. No Rails.
- `bin/serve` uses `ruby -run -e httpd out -p 8080` — zero deps.
- `out/` is **committed** (not gitignored), so examples ship with the repo and
  can be pushed to `gh-pages` when Jess chooses.

## Staged build (after schema is agreed) — Mountain 1 first

1. **Parser skeleton**: read a `.jsonl`, emit the schema above as YAML, routing
   unknown types to `unknown`. Golden test: every one of the 224 lines produces
   exactly one event; no data lost.
2. **Renderer skeleton**: ERB page that lists every event as an *identical* card
   showing `summary`. This is Mountain 1 done.
3. **Serve**: `bin/serve` over `out/`.
4. Only then climb Mountain 2 (interactivity: step-through + drill-in) — the
   `detail` payload and the click-to-expand JS.

## Verification

- `bin/parse examples/episode-8-before.jsonl` produces valid YAML; round-trip
  loads under `YAML.safe_load`.
- `test/parser_test.rb`: assert event count == log line count for both examples;
  assert no event has `kind: unknown` unexpectedly (track known coverage %).
- `bin/render` on that YAML yields an `out/` with one card per event; open via
  `bin/serve` and eyeball.
- Run against BOTH `episode-8-before` and `-after` to confirm the fallback path
  and the range-of-timeframes constraint.
- Assert every event has non-null `source.file`/`source.line` (provenance) and a
  non-null `agent`; assert assistant messages carry `tokens.raw`; assert subagent
  events are present and tagged with their `agent:` id.

## Decisions (settled with Jess)

- **Schema first**: design the intermediate on paper before coding.
- **Subagents**: included in the one document; every event carries an `agent:` id.
- **Provenance**: every event records `source: {file, line}`.
- **Tokens**: `tokens.raw` is the source of truth (preserves `iterations` and the
  `ephemeral_*` cache-TTL breakdown); headline named fields exposed for
  convenience. Model `iterations` in detail only if/when we display it.
  - `ephemeral_1h`/`ephemeral_5m` = input tokens written to the 1-hour vs
    5-minute prompt cache tiers. `iterations` = per-internal-round-trip token
    breakdown within one recorded assistant turn (aggregate lives at top level).
- **Approval**: not present in these example logs, so not emitted. Add it when a
  newer example log includes real approval data.
- **Timezone**: display timestamps in **UTC**; time-of-day is a detail-view
  field, not shown on summary cards.
- **`summary` truncation**: adjustable later; not a blocker.
- **`out/`**: committed to the repo (not gitignored).
- **Ruby**: managed via rbenv/asdf (`.ruby-version`); stdlib-first, minitest only.
