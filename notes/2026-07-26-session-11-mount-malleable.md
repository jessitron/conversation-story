# Session 11 — Mount Malleable: editing a summary on the page

Jess: "I want to work on Mount Malleable." The TODO had two items: edit a card's
summary live on the page, and — as a prerequisite — mark a `story.yaml` as
hand-edited so `rake parse` wouldn't overwrite it.

## The decision that shaped everything: a sidecar, not a lock

I offered three ways for a hand-written summary to survive a re-parse:

1. **Merge on re-parse** — stamp `summary_edited: true` in `story.yaml` and have
   `bin/parse` carry those summaries forward onto the newly parsed events.
2. **Lock the file** — a `hand_edited: true` flag that makes `rake parse` skip
   the story entirely (the TODO's own suggestion).
3. **Sidecar overrides** — edits in their own tracked file; `story.yaml` stays
   purely generated.

Jess picked **3**. That turned out to be the load-bearing choice:

- The prerequisite TODO item **disappeared**. There's nothing to lock, because
  `out/` is still fully derived — from the log *and* `edits/<name>.yaml`. A
  parser improvement keeps reaching every card Jess hasn't rewritten.
- The edits are diffable on their own, outside a 5000-line generated YAML.
- "Revert to generated" is trivial: delete the key and re-parse. No need to
  remember what the original was, because the original is always one parse away.

Worth remembering as a pattern: when a generated artifact needs hand-tuning,
**a lock freezes the generator; an overlay keeps it running.**

## What got built

- `lib/conversation_story/edits.rb` — `Edits`: load/set/save `edits/<name>.yaml`
  (a flat `ref -> summary` map), and `#apply(document)` to overlay it. `#apply`
  **returns the refs that matched no event**, and `bin/parse` warns about them —
  refs are line numbers, so editing a log orphans its edits, and losing Jess's
  words in silence would be the worst failure mode here.
- `bin/parse` gained `--edits DIR` / `--no-edits` and applies the overlay.
- `bin/serve` — a new program. WEBrick over `out/` plus `GET /api/health` and
  `PUT /api/summary`. **A save never patches anything in place**: it writes the
  sidecar and shells out to `bin/parse` then `bin/render`. So the write path
  can't drift from `rake build`, and the two-separate-programs rule survives a
  server being added to the repo. `rake serve` now runs it.
- `assets/story.js` — the editor, as pure progressive enhancement. It probes
  `/api/health`; no answer, no editor. The GitHub Pages site runs the same file.
- `bin/check-edit-api` — smoke-tests the write path end to end against a temp
  edits dir (save, sidecar, story.yaml, rendered page, both refusals, revert).
- `bin/screenshot` now accepts a full `http://…` URL, which is the only way to
  *see* the editor — `file://` can't reach the API.

## The bug that ate the middle of the session

`/api/health` returned 404 while static files served fine. I re-checked the
mount table, WEBrick's dispatch source, `ProcHandler`'s `do_PUT` alias — all
correct in isolation, all failing when served.

It wasn't the code. **Three `rake serve` processes from July 20 were still
running**, on 8080, 8099 and 8123. The old `ruby -run -e httpd` binds the
wildcard address; my server bound `127.0.0.1`. `localhost` resolves to `::1`
first, so every request went to the six-day-old static server, which of course
had no `/api/*` — and, being a file server, answered PUT with 405. Symptoms that
looked exactly like a servlet-mounting bug.

Two fixes, and the second is the real one:

- Killed the stale servers.
- `bin/serve` binds **`localhost`** (both `::1` and `127.0.0.1`) and rescues
  `EADDRINUSE` with a message naming `lsof`. Now a port conflict is a loud
  refusal to start instead of a silent shadow.

Lesson: when a local server behaves impossibly, check *who is actually
listening* before reading the framework's source. `lsof -nP -iTCP:PORT -sTCP:LISTEN`
should have been the first move, not the tenth.

## Verifying the browser half

Curl proves the API; it doesn't prove a button. So I wrote a temporary harness
page into `out/`, same-origin, holding the story page in an iframe: it typed
into `.summary-input`, clicked Save, waited, reported the DOM, clicked Revert,
reported again. `--dump-dom` printed the results. Both paths confirmed, including
the fiddly one — reverting a **tool call** restores its composed markup
(`<b>Agent</b> <code>Explore</code>`), because `applySavedSummary` stashes the
generated `innerHTML` before the first overwrite. Harness deleted afterward.

If a later session needs browser-level interaction testing again, that trick
(same-origin iframe harness + `--dump-dom`) works and needs no new dependency.

## Left open

In `TODO.md` under Mount Malleable: a stale-override indicator on the page,
"Related events" links going stale until reload, and the question of what else
wants shaping (hiding events, reordering) — which should be decided *before*
adding a second kind of entry to the sidecar file.
