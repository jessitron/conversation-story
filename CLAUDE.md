# Conversation Story

Turn a Claude agent conversation log into an explorable, pretty static web page,
so Jess can narrate "how a conversation went" while the page shows it accurately.

Read `README.md` for the vision (the four "Mountains", constraints, limitations)
and `notes/plan.md` for the current design — especially the **intermediate schema**
and the settled **Decisions**.

## Architecture

Fixed pipeline, three separate Ruby programs:

```
Input Logs  ->  Intermediate YAML  ->  Output HTML (static)
   bin/parse         bin/render + bin/serve
```

- **Input logs** are Claude logs: a `.jsonl` plus a sibling `subagents/` dir of
  `agent-*.jsonl` + `agent-*.meta.json`.
- **Intermediate** is YAML: one ordered list of events, each with a tiny
  `summary` (default view) and a `detail` payload (drill-in). Hand-editable.
- **Output** is a static site; minimal JS for interactivity.

## Conventions

- **Ruby**, managed via rbenv/asdf (`.ruby-version`). **Stdlib-first**
  (`json`, `yaml`, `erb`); only dev dep is `minitest`. No Rails.
- **Never drop log data.** Unknown event types route to a generic `unknown`
  event that preserves the raw JSON, so nothing is lost (a README constraint).
- **`examples/` are golden fixtures.** Test the parser against both
  `episode-8-before` and `episode-8-after`.
- **`out/` is committed** (not gitignored); examples ship with the repo and can
  be pushed to `gh-pages` when Jess chooses.
- **`notes/`** holds design docs and session notes, tracked in git so they follow
  across Jess's computers. Put plans and learnings here, not in machine memory.

## Status

Planning / schema-design phase. No app code yet. Next step per `notes/plan.md`:
the parser skeleton + golden-fixture test, building Mountain 1 (every event as an
identical card) end-to-end first.
