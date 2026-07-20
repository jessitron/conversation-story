# Session 6 — Hidden events (which records aren't "the conversation")

Jess: "Let's start choosing events that we won't render, they're just hidden
because they're not part of the conversation from my perspective."

## What we did

Added a `hidden: true` flag to events the parser emits for harness-bookkeeping
records. The renderer **skips** hidden events; the parser still emits them, so
`meta.event_count` stays == line count and no data is lost (README constraint).
The renderer's header "events" stat now counts **visible** events.

Result on `episode-8-before`: 224 events total → **118 visible / 106 hidden**.

## The decision (and how we reached it)

We walked the real records before deciding. Key discoveries:

- **`file-history-snapshot`** = checkpoint/rewind bookkeeping (`trackedFileBackups`,
  `isSnapshotUpdate`). Not conversation. → hidden.
- **`attachment`** is a wrapper; the meaning is in `attachment.type`. In
  episode-8: `hook_success` (82!), `task_reminder` (5), `queued_command` (2),
  `deferred_tools_delta`/`mcp_instructions_delta`/`skill_listing` (1 each).
- **`queue-operation`** is the delivery-queue lifecycle: `enqueue` (carries
  content), `dequeue` / `remove` (bare markers, no content). Two delivery paths:
  - `enqueue` → **`dequeue`** → the item becomes its **own new `user` turn**
    (agent was idle; a `stop_hook_summary` sits right before).
  - `enqueue` → **`remove`** → the item is **folded into the current turn** as a
    `queued_command` attachment (agent was mid tool-loop; no `stop_hook_summary`,
    the same turn just continues).
- The content of a queued item appears **twice** (enqueue + its delivered copy),
  and a queued *user message* also lands as a real `user` record. So the content
  is never only in `queue-operation`.

### What Jess chose to KEEP visible

- `queued_command` — "I do want to see queued_command." It's the delivered form
  of both queued user input and background `<task-notification>`s.
- `task_reminder` — "I do want to see the agent being nudged by the system!"
  (empty `content:[]` in episode-8, so renders nothing here, but visible for
  logs where it isn't.)
- **All `queue-operation`s, including the bare `dequeue`/`remove` markers** —
  because "background command failed" is *important*, and Jess wants to see both
  **when something was enqueued and when it's delivered**. The dequeue-vs-remove
  distinction tells you whether the agent noticed a background result
  immediately (mid-turn) or only after it had stopped. "Keep the marker and I'll
  see what they look like."

### Hidden set (renderer ignores)

- kinds: `system` (stop_hook_summary, turn_duration), `file_snapshot`,
  `permission_mode`
- record type `last-prompt` (the unsent-prompt buffer; still the one intentional
  `unknown` fallback)
- attachment subtypes: `hook_success`, `deferred_tools_delta`,
  `mcp_instructions_delta`, `skill_listing`

## Also done

- Visible `queue_operation` `enqueue` events now put their `content` in
  `detail.text` (so the "…failed with exit code 1" notification is readable).
- Visible `attachment` events now put `attachment.prompt` (or its `content` text)
  in `detail.text`.

## Implementation

- `lib/conversation_story/parser.rb`: `HIDDEN_KINDS`,
  `HIDDEN_ATTACHMENT_TYPES`, `HIDDEN_RECORD_TYPES`, and `hidden?(kind, rec)`;
  detail for `queue_operation` + `attachment`.
- `lib/conversation_story/renderer.rb`: `visible_events` (rejects `hidden`),
  used for cards and the events stat.
- `test/parser_test.rb`: the "one card per event" and "one copy-ref per event"
  invariants are now **per visible event**; added an assertion that *some*
  events are hidden.

## Open threads / next

- Header currently shows only the visible count. Consider surfacing hidden count
  too (e.g. "118 events · 106 hidden") or a toggle to reveal hidden cards.
- `queued: true` cross-linking (enqueue → the conversational event it belongs to)
  is still unimplemented.
- The visible `queued_command` / `queue_operation` cards currently reuse the
  quiet `system` CSS treatment and dump the raw `<task-notification>` XML into
  `detail.text`. When Jess sees them, we may want a friendlier summary (parse the
  `<status>`/`<summary>` out) and a distinct look.
