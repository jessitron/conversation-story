# TODO

- recognize and display hook executions
- move the schema out of PLAN.md into its own file - it can still be informal
- mark an intermediate story.yaml as hand-edited so `rake parse` won't overwrite
  it (e.g. a frontmatter flag or sidecar lock file the parse task checks). Note:
  rake's mtime rule already skips re-parsing when the story is newer than its
  log, but that's not an explicit "leave this alone" signal — we want one.