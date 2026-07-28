# Session 17 — the `beat` flag

2026-07-28. Closed the TODO item "modify when it stops": `n` / `p` /
shift+arrow used to step over exactly the cards `story.js` sniffed as
`k-user`/`k-assistant` outside `.subactions` — hard-coded, no way for Jess to
say "don't stop on that one". Design in
`notes/2026-07-28-beat-flag-design.md`, plan in
`notes/2026-07-28-beat-flag-plan.md`. Shipped across six commits: parser
default + `nested:` guard, `data-beat` on the card, `story.js`'s `isBeat` +
🥁 detail-pane cue + edit-mode ▸ marker, the two-section edits sidecar,
`PUT /api/beat` + the edit-mode checkbox, and both checkers extended.

Where it landed matches the design doc closely enough that it isn't worth
repeating here. Two things are worth writing down because they cost real time
and will bite again if this shape of change comes up.

## 1. The recursive-parse trap

`subagent_story` parses a subagent's log by calling `self.class.new(path)` —
the same `Parser`, recursively — so any kind-based default the parser adds
lands on every event inside every subagent too, unless it's told not to. The
`beat` default (`user_message`/`assistant_message` → `beat: true`) is exactly
that kind of default, and without a guard it would have turned a 70-event
subagent into 70 beats, shattering what session 15 established as one beat of
Jess's conversation.

The fix is `Parser.new(path, nested: true)` on the recursive call — a nested
parser sets no `beat` at all, full stop. The nested document is born correct;
nothing walks the tree afterward stripping flags back off. The general
lesson: **any parser default that isn't unconditional needs to ask "does this
also apply the moment the parser recurses into a subagent log?"** — the
answer has been "no" twice now (this, and the beat-never-stops-in-a-subagent
rule it's built on).

The tripwire is `test_*_no_event_inside_a_subagent_is_a_beat` in
`test/parser_test.rb`: it walks every `subagent.events` list and asserts none
of them carry a `beat` key at all. If a future field needs the same
main-thread-only treatment, write that test *first* — it fails loud and
immediately if the `nested:` plumbing is missing, whereas the symptom on the
page (a subagent flurry chopped into dozens of stops) is easy to miss until a
narration actually hits it.

## 2. `beat: false` deletes the key — it never gets stored

The parser only ever emits `beat: true`, on the same "omit when false" rule as
`hidden`. So an override that turns a beat *off* can't set `beat: false` in
the document — that would be a shape the parser itself never produces, and
`story.js`'s `isBeat` (`c.dataset.beat === 'true'`) would still have to special-
case it. Instead `Edits#apply` **deletes** the `beat` key when the override is
`false`:

```ruby
on ? event["beat"] = true : event.delete("beat")
```

so "not a beat" converges on one shape everywhere — parser default and hand
override look identical in `story.yaml`, and `dataset.beat === 'true'` is the
only truthiness check anywhere in the codebase for this flag. Worth
remembering next time a boolean gets a sidecar override: "only emit when
true" and "override to false" want the same absent-key representation, or you
end up with two ways to mean the same thing and a renderer that has to check
both.

## 3. The ▸ marker isn't in the gutter — it couldn't be

The design doc's first attempt anchored the edit-mode ▸ marker to `.gutter` at
a negative offset (the brief's own numbers). That lands exactly on the card's
own accent border — same pixel, same `var(--kind)` color — so the rule fires
(confirmed via `--dump-dom`) but is completely invisible. The version that
shipped anchors to `.card` instead, sitting just inside the border in the
padding strip before the gutter's text, in `--gold` so it reads against every
kind's border. See the comment above `body.mode-edit .card[data-beat]::before`
in `assets/story.css`, and the correction added inline in
`notes/2026-07-28-beat-flag-design.md`. Say "the ▸ marker", not "the gutter
marker" — a future session told to look in the gutter will go hunting for (or
worse, re-add) the rule that already failed.

## Smaller things

- **A stale `bin/serve` on port 8080 burned time for three separate
  implementers** across this feature, each debugging what looked like "my
  change isn't taking effect" against a server that was quietly still serving
  pre-edit assets. Before trusting a live reload, check for a leftover
  process: `lsof -nP -iTCP:8080 -sTCP:LISTEN`. This is the same
  wrong-listener shape as the `localhost` vs `127.0.0.1` gotcha from session
  11 — a server answering that isn't the one you think you started.
- **A file-format change has call sites outside `lib/` and `test/`.** Task 4
  converted the sidecar's flat `ref: summary` map into the two-section
  `summaries:`/`beats:` shape, and every `lib/` and `test/` reference was
  updated in that commit — but `bin/check-edit-api` still read the old flat
  shape, and that mismatch wasn't caught until Task 6 (206c3e6) actually ran
  it. When a file format changes, grep `bin/` too; the golden tests and unit
  tests don't cover the standalone scripts.
- **The plan said `edits/episode-8-before.yaml` held 8 hand-written
  summaries; it held 7.** The miscount came from wrapped YAML lines being
  counted as separate entries. Whoever hit this correctly declined to
  fabricate an eighth entry to make the file match the plan, and instead
  verified the real count against `git show` / the actual file. The plan is a
  hypothesis about the repo, not the repo — when a concrete count disagrees
  with a planning doc, trust `git show`, don't reconcile reality to the plan.

## Verification

`bundle exec rake test` is green after the documentation-only changes in this
session (no code touched). The suite has no test that reads `CLAUDE.md` or
any other doc file, so a documentation pass can't fail it — confirmed by
running the suite, not assumed.
