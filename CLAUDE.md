# Conversation Story

Turn a Claude agent conversation log into an explorable, pretty static web page,
so Jess can narrate "how a conversation went" while the page shows it accurately.

Read `README.md` for the architecture and  vision (the four "Mountains", constraints, limitations)
and `notes/plan.md` for the current design — especially the **intermediate schema**
and the settled **Decisions**.


## Conventions

- **Ruby**, managed via rbenv/asdf (`.ruby-version`). **Stdlib-first**
  (`json`, `yaml`, `erb`); only dev dep is `minitest`. No Rails.
- **The schema is the contract.** Known event kinds store only *named* fields —
  no raw source-JSON blob, and the renderer reads the schema, never the original
  log. Anything to be displayed must first be promoted to a named field. The
  human escape hatch is provenance: every event has `source: {file, line}` into
  the committed source logs. Only the `unknown` fallback kind keeps `raw`, so
  unrecognized record types aren't silently lost (a README constraint).
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
