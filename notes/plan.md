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

The intermediate schema lives in its own file: **[`intermediate-schema.md`](intermediate-schema.md)**.
It's an informal, working document describing the `story.yaml` shape — the
contract between `bin/parse` and `bin/render` — including the full annotated
YAML example, the "schema is the contract" rule, notes on the required fields
(tokens, provenance, queued, approval, agent identity), and the event `kind`s.

The settled high-level choices about the schema are recorded under
**Decisions** below.

## Proposed project layout

```
.ruby-version                 # for rbenv/asdf
Gemfile                       # minimal; minitest only to start
Rakefile                      # task runner: knows phase dependencies, shells out
bin/
  parse                       # PROGRAM: jsonl -> intermediate story.yaml
  render                      # PROGRAM: story.yaml -> index.html
lib/
  conversation_story/
    parser.rb                 # jsonl -> document (Ruby hash), with fallbacks
    schema.rb                 # document/event value objects + validation
    renderer.rb               # document -> HTML via ERB
    templates/                # ERB: page + event-card partial
out/                          # generated site — COMMITTED (Jess's choice)
  <name>/
    story.yaml                # intermediate YAML (parse output; hand-editable)
    index.html                # rendered page (render output)
test/
  parser_test.rb              # golden-fixture tests against examples/
  fixtures/
```

- **Parse and render are two SEPARATE PROGRAMS** (`bin/parse`, `bin/render`).
  They are not two functions in one process — each requires only its own `lib/`
  code and they share nothing at runtime except the `story.yaml` on disk (the
  contract). `bin/parse` could be swapped for a different-source parser later
  without the renderer knowing.
- **Rake is only the task runner.** It owns the *dependency* between the phases
  (a page needs its `story.yaml`, which needs its log) via file tasks, and shells
  out to each program in its own process. `rake -T` lists tasks; the everyday
  commands are simple enough to allowlist without bash-approval friction.
  - `rake parse`  — every `examples/*.jsonl` -> `out/<name>/story.yaml`
  - `rake render` — every `out/*/story.yaml` -> `out/<name>/index.html` (runs
    parse first when a story is missing or stale)
  - `rake build`  — parse then render
  - `rake serve`  — serve `out/` (`ruby -run -e httpd out -p 8080`)
  - `rake test`   — minitest golden fixtures
- **Default is all examples; `LOG=` scopes to one.** e.g.
  `LOG=examples/episode-8-before.jsonl rake build`.
- **Stdlib-first**: `json`, `yaml`, `erb` are built in. Only dev dep is
  `minitest`. No Rails.
- Intermediate YAML lives in `out/<name>/story.yaml` alongside its page, so the
  "hand-edit the intermediate" constraint just works and gh-pages ignores it.
- `out/` is **committed** (not gitignored), so examples ship with the repo and
  can be pushed to `gh-pages` when Jess chooses.

## Deferred to a later version

- **Hooks** (Jess *is* interested, just not yet). The logs carry a lot of hook
  detail we're currently leaving as summary-only: `system` events
  (`stop_hook_summary`, `turn_duration` with `durationMs`/`messageCount`,
  `hookInfos` = commands + timings, `hookErrors`, `level`,
  `preventedContinuation`) and the ~157 `attachment` records that are actually
  hook-execution records (`hookName`, `hookEvent`, `command`, `stdout`/`stderr`/
  `exitCode`/`durationMs`). When we tackle this, design named fields for them
  (same "schema is the contract" rule) so hook activity is intelligible on the
  page.

## Staged build (after schema is agreed) — Mountain 1 first

1. **Parser skeleton**: read a `.jsonl`, emit the schema above as YAML, routing
   unknown types to `unknown`. Golden test: every one of the 224 lines produces
   exactly one event; no data lost.
2. **Renderer skeleton**: ERB page that lists every event as an *identical* card
   showing `summary`. This is Mountain 1 done.
3. **Serve**: `rake serve` over `out/`.
4. Only then climb Mountain 2 (interactivity: step-through + drill-in) — the
   `detail` payload and the click-to-expand JS.

## Verification

- `LOG=examples/episode-8-before.jsonl rake parse` produces valid YAML;
  round-trip loads under `YAML.safe_load`.
- `test/parser_test.rb`: assert event count == log line count for both examples;
  assert no event has `kind: unknown` unexpectedly (track known coverage %).
- `rake render` on that YAML yields an `out/<name>/index.html` with one card per
  event; open via `rake serve` and eyeball.
- Run against BOTH `episode-8-before` and `-after` to confirm the fallback path
  and the range-of-timeframes constraint.
- Assert every event has non-null `source.file`/`source.line` (provenance) and a
  non-null `agent`; assert assistant messages carry named token fields
  (`tokens.input`/`tokens.output`); assert subagent events are present and tagged
  with their `agent:` id.

## Decisions (settled with Jess)

- **Schema first**: design the intermediate on paper before coding.
- **Subagents**: included in the one document; every event carries an `agent:` id.
- **Provenance**: every event records `source: {file, line}`.
- **Schema is the contract**: known event kinds store **only named fields** — no
  raw/source-JSON blob and the renderer never reads the original log. Provenance
  (`source: {file, line}`) into the committed source logs is the human escape
  hatch. `raw` survives only on the `unknown` fallback kind.
- **Tokens**: every count is a **named field** (input, output, cache
  creation/read, `ephemeral_1h`/`ephemeral_5m`, `service_tier`, and `iterations`
  as a named list). No raw. Subagent totals live under `tool.subagent_tokens`.
  - `ephemeral_1h`/`ephemeral_5m` = input tokens written to the 1-hour vs
    5-minute prompt cache tiers. `iterations` = per-internal-round-trip token
    breakdown within one recorded assistant turn (aggregate lives at top level).
- **More named fields (b)**: `model`, `stop_reason`/`stop_details`/
  `stop_sequence`, `tool.is_error`, `tool.duration_ms`, named `tool.result`
  fields, and `tool.subagent_tokens`.
- **Agent identity (c)**: use the record's explicit `agentId` for `agent:`
  (fall back to `main`); `isSidechain` corroborates.
- **Approval**: not present in these example logs, so not emitted. Add it when a
  newer example log includes real approval data.
- **Timezone**: display timestamps in **UTC**; time-of-day is a detail-view
  field, not shown on summary cards.
- **`summary` truncation**: adjustable later; not a blocker.
- **`out/`**: committed to the repo (not gitignored).
- **Ruby**: managed via rbenv/asdf (`.ruby-version`); stdlib-first, minitest only.
