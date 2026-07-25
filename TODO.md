# TODO

## now

- get the left padding the same between Assistant and Tool call cards
- highlighting because I clicked something with the same link ID should be identical to highlighting because I clicked that card, not subtly different
- I want input, output, and notifications to use a consistent font, background color, etc. for the INPUT, RESULT, NOTIFICATION fields.
- Queue enqueue should include the summary of what it is enqueueing


## later

- I clearly need a subagent whose job is to guard the CSS and keep it consistent. 
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
