# 02 — `SessionScan`: one streaming pass per log, cached

**What to build:** the ability to ask "what is this session?" of any Claude
session log and get back the handful of facts Jess needs to judge whether it is
worth turning into a story — without reading 621 MB every time.

A new `ConversationStory::SessionScan` makes one **streaming** pass over a single
log and produces:

- `session_id` — the first line's `sessionId`
- `title` — the **last** `type: "ai-title"` record's `aiTitle` (the harness
  regenerates the title as the session runs, so the last one is best informed)
- `first_prompt` — the first `type: "user"` record whose `message.content` is a
  plain String and doesn't start with `<` (that would be a harness blob, not Jess)
- `recap` — the `content` of the `type: "system"` / `subtype: "away_summary"`
  record, with the trailing `"(disable recaps in /config)"` tail stripped. May be
  absent; a session without one must scan fine.
- `turns` — count of **distinct `message.id`** values across assistant records.
  Counting assistant records inflates this ~3× (one record per thinking / text /
  tool_use block of the same API response — the same fact `Parser`'s turn-leader
  logic exists for).
- `subagents` — number of files in the session's `subagents/` sidecar directory
  (a directory listing, so free)
- `max_context` — the **true max** over all assistant records. Free, because the
  pass reads the whole file anyway; no log in the corpus has ever compacted
  (zero `isCompactSummary` records across 416 logs), and on the sample log the
  last record's total was exactly the max.
- `size`, `mtime`, `path`, `project`

It deliberately does **not** reuse `Parser`: `Parser` accumulates a full event
array and recursively parses every subagent sidecar, so 50 runs over 621 MB would
take minutes and gigabytes to compute five numbers.

Two performance rules, both from a real memory-blowup warning:

- **Pre-filter before `JSON.parse`** with a cheap `line.include?` check. The
  hazard is a *single line* — one tool result can be megabytes — and the filter
  means those lines are read as a String and discarded, never turned into Ruby
  objects.
- **Never hold 50 scans in memory.** Each result is written to the cache the
  moment it completes, so a crash partway through a cold scan keeps what's done.

The cache is keyed by **path + mtime + size**, so an unchanged log is never
reopened and an appended-to log is rescanned. It lives in a **gitignored
directory** — private derived data must never land in a public repo.

**Blocked by:** None — can start immediately (independent of 01).

**Status:** ready-for-agent

- [ ] `ConversationStory::SessionScan` scans one log in a single streaming pass
      and returns every field listed above
- [ ] A log with no `away_summary` record scans successfully with an absent recap
- [ ] The recap's `"(disable recaps in /config)"` tail is stripped
- [ ] `turns` counts distinct `message.id`, not assistant records — asserted on a
      fixture where the two numbers differ
- [ ] Lines are pre-filtered with a cheap string check before `JSON.parse`, and
      memory stays flat across a multi-hundred-MB log
- [ ] Each session's result is written to the cache as it completes, not batched
- [ ] The cache hits on an unchanged log (no reopen) and misses when mtime or
      size changed
- [ ] The cache directory is in `.gitignore`
- [ ] Minitest covers `SessionScan` against **every** `examples/*.jsonl` golden
      fixture, the same treatment `Parser` gets
- [ ] The `Rakefile`'s `*_SRC` lists name the new `lib/` file
- [ ] `rake test` passes
