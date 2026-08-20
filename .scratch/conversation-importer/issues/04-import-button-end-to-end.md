# 04 — Import: name it, press the button, get a story

**What to build:** the whole point of the page. Jess picks a session, names it,
presses **Import**, and a moment later has a golden fixture in `examples/` and a
link to the built story.

Each card gets an **editable name field**, pre-filled with a slug derived from the
session's AI title, so the good default is one keystroke away and a better name is
always possible. Underneath the field, the resulting **`examples/<slug>.jsonl`
path is shown live** as she types, so she sees exactly what file will appear.

Pressing Import:

1. Slugifies and validates the name against the same
   `[a-z0-9]+(-[a-z0-9]+)*` rule `bin/grab-example` enforces, refusing anything
   else — and refusing to overwrite an **unrelated** existing example rather than
   silently clobbering it.
2. Copies the main log **and** any `subagents/` sidecars, via
   `ConversationStory::Import` (ticket 01) — so the nested-document story survives
   the trip and the CLI and browser doors can't drift.
3. **Shells out to `bin/parse` then `bin/render`**, scoped to that one name. This
   follows `bin/serve`'s precedent: a write invokes the real programs rather than
   patching files in place, so a fixture built through the browser is identical to
   one built by `rake build`. Not a full `rake build` — adding one example must
   not re-render five unrelated ones.
4. Answers with a **link to the finished story on `bin/serve`**
   (`http://localhost:8080/<name>/`), gated on a `GET /api/health` probe of that
   server — the same trick `story.js` uses to decide whether to show the editor.
   When the probe fails, the response says to start `rake serve` instead of
   handing over a dead link. Not a `file://` link: `file://` silently loses edit
   mode.

The importer **never serves `out/` itself**. That is the leak that would drag it
back into being a second `bin/serve`.

**Blocked by:** 01 (shared `Import`), 03 (the listing page).

**Status:** done

- [x] Each card has a name field pre-filled with a slug of the session's AI title
- [x] The `examples/<slug>.jsonl` path updates live under the field as Jess types
- [x] A name that isn't a clean `[a-z0-9-]` slug is refused with a clear message
- [x] An import that would overwrite an unrelated existing example is refused
- [x] Import copies the main log and every `subagents/` sidecar
- [x] Import shells out to `bin/parse` and `bin/render` for that one name only —
      other examples in `out/` are untouched
- [x] On success the response links to `http://localhost:8080/<name>/`
- [x] With `bin/serve` down, the `GET /api/health` probe fails and the response
      says to start `rake serve` rather than showing a dead link
- [x] `bin/importer` serves no files out of `out/`
- [x] `rake test` passes
