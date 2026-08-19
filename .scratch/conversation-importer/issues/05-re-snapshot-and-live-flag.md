# 05 — Already imported: Re-snapshot, and a "live" warning

**What to build:** Jess never imports the same conversation twice under two
names, and never mistakes a still-running session's half-log for a finished
fixture.

A session that is **already in `examples/`** is recognised on the listing page. It
shows the example **name it went in as**, so she can find it, and its button reads
**Re-snapshot** instead of Import: overwrite in place under the existing name and
rebuild — the behaviour `bin/grab-example` already documents ("Re-run to
re-snapshot").

Recognition is done by reading the first line's `sessionId` out of each
`examples/*.jsonl`. The fixtures answer the question themselves, so there is no
manifest file to maintain or to go stale.

Re-snapshot **merges sidecars** rather than no-opping on a main-log size match: a
subagent that finished after the first snapshot is a *new file*, which a size
comparison can't see.

A log written to within the **last couple of minutes** wears a **live** flag on
its card, because the harness is still appending and that fixture is guaranteed
incomplete — everything after the copy, including the copy itself, will be
missing.

**Blocked by:** 04 — the import action.

**Status:** ready-for-agent

- [ ] A session whose `sessionId` matches the first line of an existing
      `examples/*.jsonl` is shown as already imported, with that example's name
- [ ] Its button reads Re-snapshot and overwrites in place under the existing
      name, then rebuilds that one story
- [ ] Re-snapshot copies sidecars that appeared since the first snapshot, even
      when the main log's size is unchanged
- [ ] Re-snapshot does not create a second fixture under a different name
- [ ] A log written to within the last couple of minutes is flagged live
- [ ] Recognition reads the fixtures themselves — no manifest file is introduced
- [ ] `rake test` passes
