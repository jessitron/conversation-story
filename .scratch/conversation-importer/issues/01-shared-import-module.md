# 01 — Shared `Import` module; `bin/grab-example` fixed

**What to build:** `bin/grab-example --list` works again, and lists every recent
session Jess has had — not just this repo's, and not from a directory that is
empty on this machine. Today it reads `~/.claude/projects` (empty) and only ever
looks at the current repo's project directory, so it dies with "no session logs
for this repo" and a session from another project has to be copied in by hand.

After this ticket, discovery spans **both** config dirs — `~/.claude-work/projects`
and `~/.claude-personal/projects` — across **all** projects, and
`bin/grab-example <session-id> <name>` still copies a fixture the same way it
always did (main log plus any `subagents/` sidecars).

The discovery and copy logic move into a new `ConversationStory::Import`, which
takes a session **path** rather than deriving one from the current repo. This is
the prefactor: `bin/importer` (ticket 04) calls the same module, so the two doors
into `examples/` cannot drift.

Nothing user-visible changes about the fixture layout — the parser finds sidecars
by filename, so this stays a straight copy with no rewriting.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] `ConversationStory::Import` exists and owns two jobs: enumerating session
      logs across both config dirs and all projects, and copying one session
      (given its **path**) to `examples/<name>.jsonl` + `examples/<name>/subagents/`
- [x] `bin/grab-example --list` lists sessions from both config dirs, across all
      projects, newest first, and does not consult `~/.claude/projects`
- [x] `bin/grab-example <session-id> <name>` still produces a byte-identical
      fixture to what it produced before, sidecars included
- [x] `bin/grab-example` keeps its existing CLI interface, its slug rule
      (`[a-z0-9]+(-[a-z0-9]+)*`), and its live-log warning
- [x] The `Rakefile`'s `*_SRC` lists name the new `lib/` file — those lists are
      explicit, not globs, so `rake build` would otherwise not notice it changed
- [x] `rake test` passes

## Comments

Shipped. `ConversationStory::Import` has `Import.sessions` (both config dirs, all
projects, newest first, as `Session` structs), `Import.find(id)` (global resolve,
raises on missing *or ambiguous*), `Import.copy(log_path, name, examples_dir:)`,
and `Import.same_snapshot?` — which answers the size-match question without
deciding what it means, so `grab-example` can no-op on it and ticket 05's
Re-snapshot can ignore it and merge sidecars. `LIVE_SECONDS` (120) is shared with
ticket 05's live flag.

Two deliberate deviations:

- **The `*_SRC` checkbox was not followed literally.** `import.rb` isn't required
  by `bin/parse`/`render`/`site-index`, so listing it among their sources would
  invalidate every example's build whenever copy logic changed, for a dependency
  that doesn't exist. It got its own `IMPORT_SRC` list with a comment saying why.
  Ticket 02 reached the same conclusion independently for `session_scan.rb`.
- **`--list` defaults to the 50 newest** (of 426) with a footer counting the rest,
  plus an optional `--list N`. Discovery is now global, so the old unbounded
  listing would print 426 lines. An addition to the CLI, not a change.

`Session#project` is display-only and lossy — the `/`→`-` encoding can't be
decoded. See ticket 02's comment: `cwd` is the better source, and 02 already
implements it. **Ticket 03 must pick one of the two.**
