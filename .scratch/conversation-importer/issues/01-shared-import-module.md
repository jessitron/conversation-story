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

**Status:** ready-for-agent

- [ ] `ConversationStory::Import` exists and owns two jobs: enumerating session
      logs across both config dirs and all projects, and copying one session
      (given its **path**) to `examples/<name>.jsonl` + `examples/<name>/subagents/`
- [ ] `bin/grab-example --list` lists sessions from both config dirs, across all
      projects, newest first, and does not consult `~/.claude/projects`
- [ ] `bin/grab-example <session-id> <name>` still produces a byte-identical
      fixture to what it produced before, sidecars included
- [ ] `bin/grab-example` keeps its existing CLI interface, its slug rule
      (`[a-z0-9]+(-[a-z0-9]+)*`), and its live-log warning
- [ ] The `Rakefile`'s `*_SRC` lists name the new `lib/` file — those lists are
      explicit, not globs, so `rake build` would otherwise not notice it changed
- [ ] `rake test` passes
