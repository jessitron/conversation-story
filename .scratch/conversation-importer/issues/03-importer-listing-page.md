# 03 — `bin/importer`: a browser page of recent sessions

**What to build:** Jess runs one command and gets a browser page of her recent
Claude conversations, each one recognisable at a glance — so picking a fixture
stops being a JSONL grep.

`bin/importer` is a **fourth program** next to `bin/parse` / `bin/render` /
`bin/site-index`: a WEBrick server on **8081** (`PORT=`-overridable), a local
authoring tool that never ships to GitHub Pages. Deliberately **not** a route on
`bin/serve`, because what `bin/serve` serves is the published artifact.

The page shows the **~50 most recent** sessions, taken globally by mtime and
**then grouped by project**, with projects ordered by their newest session — so
the freshest work is at the top and every session's origin is on screen.

Each session is a **card, with the recap as its body** — closer to the landing
page's story cards than to a dense table, because the recap is prose and wants
room. The recap is shown **in full**, never truncated: it is the thing Jess
actually reads to decide whether a session is a story. The card also carries the
title, the first plain-string prompt, turns, subagent count, max context, file
size and date.

Styling is `assets/importer.css`, built on `story.css`'s tokens and loaded after
it — the pattern `assets/index.css` already demonstrates. Don't invent much new
visual language; this is a candidate for the `design-feature-owner` TODO later.

There is deliberately **no publishing warning** on the page, even though work
sessions appear in a list whose Import button leads to a public repo. Jess's
call: her work conversations are almost never about proprietary code, and
grouping by project already puts the origin on screen as plain information.

The generated HTML lands in the same **gitignored directory** as the scan cache.

**Blocked by:** 02 — `SessionScan`.

**Status:** ready-for-agent

- [ ] `bin/importer` starts a server on 8081 and serves a listing page; `PORT=`
      overrides the port
- [ ] The page shows the ~50 most recent sessions, taken globally by mtime, then
      grouped by project, projects ordered by their newest session
- [ ] Each card shows title, first prompt, full recap, turns, subagents, max
      context, size and date
- [ ] A session with no recap renders a sensible card rather than a broken one
- [ ] `assets/importer.css` is loaded after `story.css` and reuses its tokens
- [ ] Generated HTML is written into the gitignored directory alongside the cache
- [ ] A second page load is fast — unchanged logs come from the cache
- [ ] No publishing warning appears on the page
- [ ] The `Rakefile`'s `*_SRC` lists name any new `lib/` files
- [ ] `rake test` passes
