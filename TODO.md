# TODO

## now

(empty — see notes/2026-07-26-session-9-card-alignment-and-one-machine-voice.md
for the four that just landed)


## later

- I clearly need a subagent whose job is to guard the CSS and keep it consistent.
  Two things it would have caught this session: a `var()` on a token that no
  longer exists (fails silently), and a rule whose `opacity` override lost to a
  same-specificity rule later in the file.
- the prototype has no sample RESULT / NOTIFICATION detail section, so the
  "machine voice" (`pre.code`) is only half-demonstrated there. Add one so the
  prototype keeps showing everything that ships.
- mark an intermediate story.yaml as hand-edited so `rake parse` won't overwrite
  it (e.g. a frontmatter flag or sidecar lock file the parse task checks). Note:
  rake's mtime rule already skips re-parsing when the story is newer than its
  log, but that's not an explicit "leave this alone" signal — we want one.
- self-host the fonts (Tenor Sans / Sen / Cascadia Code) into `assets/fonts/`
  with `@font-face` in `story.css`, replacing the CDN `<link>`.
- the deterministic HTML well-formedness check (plan.md TODO).
- Mountain 2: block-level cards (split thinking/text/tool_use within one
  record into separate cards — right now a record is still one card, just
  classified by its single content block), richer per-kind detail, subagent
  nesting (inline a spawned Agent's own story instead of just linking to it).
- the `<ol>`/`<ul>` merge in `Markdown` only re-glues _adjacent_ same-type
  blocks; a loose list interrupted by an aside paragraph would still split.
  Fine for what's in the example logs; revisit if a real log hits it.
