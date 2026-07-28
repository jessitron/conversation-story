# Session 18 — `bin/screenshot` shot blank paper, and why the diagnosis was wrong for four sessions

Jess's report: "agents are having a ton of trouble with: `bin/screenshot` with a
fragment shot fully blank for cards deep in these pages. It keeps snagging us."

That's the third session in a row where the blankness ate time. It was in
CLAUDE.md as a *known artifact* — "the region above the target screenshots blank
— a headless repaint artifact, not a page bug" — which is exactly the kind of
note that stops anyone from looking again. So this time we measured instead of
believing the note.

## What the note got wrong

The session-9 note said the band *above* the target goes blank and the page is
fine. Two of those three claims are false:

- It isn't a band. For `mtg-tabletop-plan:749` the entire 1400×1600 png is one
  flat sheet of paper — 9.6 KB, no header, no cards, nothing.
- It isn't about being deep, either. Blank starts at **scrollY = 10,000** on a
  182,275px page. Every card past the first screenful was affected, which on
  these pages is ~500 of 508.

The page really is fine, which is the part that made the artifact story
plausible. Measured with ferrum at the moment of capture:

```
scrollY=180762  innerHeight=1513  docHeight=182275
found=true  active=true  activeId=mtg-tabletop-plan:749  rectTop=911
```

Right card selected, scrolled to, sitting comfortably inside the viewport — and
the capture of that viewport is empty. So the bug was never in the page or in
`story.js`. It was in `bin/screenshot`.

## Root cause

**Headless Chrome only rasterizes the tiles around where the page is currently
scrolled.** A programmatic scroll (`scrollIntoView`, or a fragment) moves the
viewport but the newly exposed tiles never get painted, so there is nothing for
a viewport capture to read.

Things that do *not* fix it, all tried:

| Attempt | Result |
|---|---|
| `--headless=new` instead of old headless | still blank |
| CDP `Page.captureScreenshot` via ferrum instead of the CLI flag | still blank |
| scrolling less far (10k instead of 180k) | still blank |

The thing that does work is **not relying on the scroll at all**: pass an
explicit clip rectangle in page coordinates, which goes down Chrome's
capture-beyond-viewport path and rasterizes the region on demand. A clip of just
the card's rect came back with real pixels while the full-viewport shot of the
same page state was blank. That's the whole fix.

## The second rule, found the same way

A clip is not a free pass. **The clip must overlap the current viewport.** Two
pieces of evidence:

- Clip the deep region *after* `window.scrollTo(0, 0)` → blank again (10,144
  bytes). So it isn't "clips always work"; it's "clips work near the viewport".
- With the page scrolled 150px down, a clip starting at y=0 renders the cards
  but **not the static header** sitting at y=0..84 — 150px above the viewport
  was already too far.

That second one would have shipped as a quiet regression: every fragment shot
losing the header, and the header is where Events / Duration / Tokens / Model
live, which is precisely what a Mount Beautiful change wants to look at.

So the final algorithm is: position the page first, then clip *exactly* the
viewport.

- Card fits on the first screenful → `scrollTo(0, 0)`, so the header stays in
  frame.
- Deeper → `scrollIntoView({block: 'center'})`. The header is then legitimately
  out of shot: that's what a real browser scrolled to that card shows too.

## What changed

- **`bin/screenshot` is Ruby + ferrum now**, not bash around
  `chrome --screenshot`. The gem is already a `:test` dependency (`bin/check-modes`
  uses it) and it's the only way to get a clip rectangle, so this is a case of a
  gem earning its place rather than a new dependency. It self-bootstraps
  (`BUNDLE_GEMFILE` + `bundler/setup`), so plain `bin/screenshot` still works
  without `bundle exec`.
- **Argument shape, not position.** `bin/screenshot ex out.png` used to treat
  `out.png` as the ref and shoot the default card. A `.png` is now recognized as
  the destination wherever it appears, so the fragment is genuinely optional.
- **An unresolvable fragment warns on stderr** instead of silently shooting the
  default selection. Hidden events have no card *by design*, so this is a normal
  thing to hit — and it looked identical to "my CSS change did nothing".
- **Settling is condition-based** (fonts loaded, cards present, target actually
  `.active`, 5s cap) instead of a fixed `--virtual-time-budget=2000` guess.
- **`bin/check-screenshot` is new**, following the `bin/check-*` convention.
  Five cases: deep card, mid card, no fragment, landing page, unresolvable ref.
  Blankness is asserted **by file size** — a flat-colour PNG compresses to
  ~9.6 KB where a real shot is 200–450 KB, so the threshold (50 KB) is an order
  of magnitude from both. Crude, needs no image library, and fails exactly when
  the bug returns. The deepest ref is recomputed from the built HTML rather than
  hard-coded, so a re-parse that shifts line numbers can't turn it into a false
  failure.

## The meta lesson

A "known artifact" note is a load-bearing claim, and this one was never
re-tested after the session that guessed it. It cost more than the bug: three
sessions of agents seeing a blank shot, remembering the note, and shrugging. The
tell was available the whole time — the note said *part* of the image was blank,
and the actual images were *entirely* blank. Nobody compared the note to the
artifact.

When a note explains away a broken tool, the cheap check is whether the
explanation predicts the symptom in detail. If it doesn't, the note is a guess.
