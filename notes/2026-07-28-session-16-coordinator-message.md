# Session 16: a newer example, new harness concepts, and `coordinator_message`

Brought in `examples/mtg-tabletop-plan` — a real mtg-deck-shuffler conversation
from 2026-07-27, Claude Code v2.1.220, 755 lines / 10 subagents — and used the
gap against the old episode-8 examples (v2.1.105, April) to find what's new in
the harness itself.

## New harness record types (v2.1.105 → v2.1.220)

- **`mode`** replaces `permission-mode` — same one-word per-prompt indicator,
  just a rename (`permissionMode` field → `mode`). Mapped into the same
  `permission_mode` kind.
- **`ai-title`** — the harness continuously generates/refreshes a suggested
  conversation title. New kind `ai_title`, hidden like its bookkeeping
  siblings.
- **`file-history-delta`** — an incremental per-edit sibling to the existing
  `file-history-snapshot`. Both about the harness's own file-backup/undo
  system for files Jess's agent edits (`trackingPath`, `backup.backupFileName`
  etc.) — **not** about the conversation log itself. Mapped into the same
  `file_snapshot` kind.
- **Background/async subagents** — the actual big one. An `Agent` call can now
  return immediately with `toolUseResult.status == "async_launched"` (no
  `totalTokens` yet, plus `outputFile`/`canReadOutputFile`) instead of a
  finished answer. The real completion arrives later as a `<task-notification>`
  — same delivery mechanism the parser already had for background Bash tasks —
  still linked to the launch via the shared `tool:<use_id>` token. Fixed
  `test_..._agent_results_become_subagent_result_events` to only require
  `tool.subagent_tokens.total_tokens` when `tool.status != "async_launched"`.
- **`SendMessage`** — a new tool for steering an already-backgrounded agent
  (resume it, correct it, relay feedback) by its agent id.

## New kind: `coordinator_message`

`SendMessage`'s delivery lands inside the **target subagent's own log** as a
plain `role: user` record — same shape as a real prompt from Jess, but it
isn't one. The harness prefixes it with a literal, stable string:
`"The coordinator sent a message while you were working:"` — that prefix is
the *only* signal telling the two apart, so `Parser::COORDINATOR_MESSAGE_PREFIX`
matches on it in `user_kind`.

Rendering: styled like the assistant/user "real conversation" treatment
(paper background, summary-size text, baseline alignment) but kept in its own
gray (`--ink-faint`) rather than navy or blue, and **right-aligned like
`k-user`** — Jess's read: it's Claude, but arriving into this subagent from
outside its own thread, the same "other side" logic as a human message, just
not the human. Attribution goes through `who_for`'s early-return (always
"Claude", never remapped to the subagent's own name — that would credit the
subagent with steering itself). Thinking cards also moved from orange to that
same gray in this session, for a quieter/more consistent backstage palette.

## Gotcha: concurrent sessions editing the same repo

Jess had **four `claude` CLI processes open** in this repo at once this
session, and two of them picked up near-identical tasks (new fixture +
harness-record-type fixes) independently, editing `parser.rb`/`test/
parser_test.rb` at the same time. Caught it by noticing `git status` showed
files I hadn't touched, and confirmed with `ps aux | grep claude` + watching
a file's mtime change between two reads a few seconds apart.

**Lesson for next time**: before editing shared source (not just the new
fixture files), check `git status` for unexpected modifications and treat any
found as someone else's in-progress work, not something to revert or silently
overwrite. Committing separately once one side finishes, and re-reading files
right before editing them (never trusting a stale in-context copy), avoided
clobbering anything. `bin/check-anchors`/`bin/check-modes` (real headless
Chrome) stayed reliable throughout; `bin/screenshot` started returning fully
blank captures partway through the session (even on the old canonical
example) — never resolved, probably system load from the four sessions, not a
page bug.
