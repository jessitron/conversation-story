# Session 17: `mtg-tabletop-plan`, background subagents, `coordinator_message`

Ran concurrently with session 16 (`notes/2026-07-28-session-16-examples-and-prompt-mode.md`,
which has the `mode`/`ai-title`/`file-history-delta` story — not repeated
here). This session's fixture was `examples/mtg-tabletop-plan`: a real
mtg-deck-shuffler conversation, Claude Code v2.1.220, 755 lines / 10 subagents.

## Background/async subagents, and `SendMessage`

An `Agent` call can now return immediately with
`toolUseResult.status == "async_launched"` (no `totalTokens` yet, plus
`outputFile`/`canReadOutputFile`) instead of a finished answer. The real
completion arrives later as a `<task-notification>` — same delivery mechanism
the parser already had for background Bash tasks — still linked to the launch
via the shared `tool:<use_id>` token, so the causal chain lights up even
though the launch card itself carries no tokens. Fixed
`test_..._agent_results_become_subagent_result_events` to only require
`tool.subagent_tokens.total_tokens` when `tool.status != "async_launched"`.

**`SendMessage`** is the new tool for steering an already-backgrounded agent
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

**Lesson for next time**: before editing shared source (not just new fixture
files), check `git status` for unexpected modifications and treat any found
as someone else's in-progress work — investigate, don't revert or silently
overwrite. Re-reading a file right before editing it (never trusting a stale
in-context copy) avoided clobbering anything; committing source-only changes
and leaving `out/` alone until the other session finished kept the two
threads from tangling in the build output. (`bin/screenshot` also came back
fully blank on every fragment this session, including the old canonical
example — session 16's note found the real cause: it scales with how deep
the target card sits in a long page, not something specific to this session.)
