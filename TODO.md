# TODO

The mountains are named in `README.md`. This is the working list, grouped by
which mountain each item climbs. Order within a group is roughly "what I'd pick
up next" — nothing here is scheduled.

## Mount Interactive

- **Step-through navigation.** The North Star says "I can step through it," and
  right now the only way forward is clicking the next card and scrolling.
  Wanted: keyboard next/prev over the visible cards, and a way to reveal events
  in progression while narrating (a presenter mode) rather than showing the
  whole timeline at once. Selection is fragment-driven, so "next" is
  "`getElementById` the next `.card` and set the hash."

## Mount Complete

- **Say when an assistant turn includes tool calls.** Every assistant record in
  the example logs carries exactly one content block, so a turn where Claude
  says something *and* calls a tool becomes two separate cards with nothing on
  the message card announcing the tool call. Reading the page, it looks like
  Claude spoke and then, unrelatedly, a tool ran. The card should show that the
  message led to tool calls (and which ones).
- **Subagents** (wanted, not urgent): inline a spawned Agent's own story instead
  of only listing it in `meta.agents`. The subagent logs are already on disk
  (`examples/<name>/subagents/agent-*.jsonl` + `.meta.json`) and the schema
  already reserves an `agent:` id on every event.
- **Block-level cards**: split thinking / text / tool_use *within* one record
  into separate cards. Today a record is one card, classified by its single
  block — which works only because these logs never mix block types in a record.
- The `<ol>`/`<ul>` merge in `Markdown` only re-glues _adjacent_ same-type
  blocks; a loose list interrupted by an aside paragraph would still split.
  Fine for what's in the example logs; revisit if a real log hits it.

## Mount Beautiful

- Self-host the fonts (Tenor Sans / Sen / Cascadia Code) into `assets/fonts/`
  with `@font-face` in `story.css`, replacing the CDN `<link>`.
- A subagent whose job is to guard the CSS and keep it consistent. Two things it
  would have caught in session 9: a `var()` on a token that no longer exists
  (fails silently), and a rule whose `opacity` override lost to a
  same-specificity rule later in the file.
- The prototype has no sample RESULT / NOTIFICATION detail section, so the
  "machine voice" (`pre.code`) is only half-demonstrated there. Add one so the
  prototype keeps showing everything that ships.

## Mount Malleable

*A local web app for shaping the story — edit on the page, not in YAML.*

- Edit a card's **summary** live on the page and have the change persist back to
  `out/<name>/story.yaml`. Needs a local (dev-only) write path; the published
  site stays static.
- Prerequisite: **mark a story.yaml as hand-edited** so `rake parse` won't
  overwrite it (a frontmatter flag or sidecar lock file the parse task checks).
  Rake's mtime rule already skips re-parsing when the story is newer than its
  log, but that's not an explicit "leave this alone" signal — we want one.

## Maybe later

- **Hooks.** The logs carry a lot of hook detail we currently leave as
  summary-only: `system` events (`stop_hook_summary`, `turn_duration`,
  `hookInfos`, `hookErrors`) and the ~157 `attachment` records that are really
  hook-execution records (`hookName`, `hookEvent`, `command`, `stdout`/`stderr`/
  `exitCode`/`durationMs`). Interesting, not urgent — if we do it, they get
  named schema fields like everything else.
