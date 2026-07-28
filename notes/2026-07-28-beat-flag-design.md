# Design: the `beat` flag — choosing where narration stops

_TODO.md, Mount Interactive: "**modify when it stops**"._

Today `n` / `p` / shift+arrow move to the next User or Assistant message, and
which cards those are is hard-coded in `assets/story.js`:

```js
const isMessage = c =>
  (c.classList.contains('k-user') || c.classList.contains('k-assistant')) &&
  !c.closest('.subactions');
```

Jess wants to **exempt some messages** from that stepping — a tool-shaped
exchange she'd narrate as one breath shouldn't cost three beats — and
occasionally to **add** a stop somewhere the parser wouldn't guess.

So: make "does narration stop here?" a real field on the event, default it the
way the hard-coded rule already behaves, and let Jess override it per card in
edit mode.

## The name

**`beat`.** The codebase already calls one narrate step a beat —
`beatForwardTo`, `beatBackTo`, "a beat never stops inside a subagent". The flag
is the same word, so `beatForwardTo` looking for the next `beat` reads as a
tautology rather than a translation. UI label: "Beat stops here".

## 1. Schema: the parser sets the default

Every `user_message` and `assistant_message` **in the main thread** gets
`beat: true`. Emitted only when true — like `hidden` — so the schema doesn't
grow a field on 224 events to say "no".

`CSS_KIND` maps those two kinds to exactly `k-user` / `k-assistant`, so this
default reproduces today's `isMessage` set card-for-card. Behavior before any
override is unchanged, which is what makes this safe to land.

**The nesting wrinkle.** A subagent's log is parsed by
`self.class.new(path).to_document` — the same class, recursively — so a nested
`assistant_message` would pick up the same default, and a subagent's 70 events
would each become a beat. That directly contradicts the session-15 rule that a
beat never stops inside a subagent.

Fix: `Parser.new(path, nested: true)` on the recursive call, and a nested parser
never sets `beat`. The nested document is born correct — no second pass walking
the tree to strip flags — and a subagent that spawns a subagent works for free,
since the flag rides the constructor down.

This keeps `story.yaml` the contract: the file *states* which events are beats
rather than leaving the renderer and `story.js` to re-derive it from kind and
DOM position.

## 2. Renderer: one attribute, one CSS rule

`data-beat="true"` on the card `<a>`, next to the existing `data-edited` and
`data-link`. Omitted when false.

Plus a marker in the gutter of every beat card, **in edit mode only**:

```css
body.mode-edit .card[data-beat] .gutter::before { content: '▸'; }
```

[Correction, written after implementation: this doesn't work. `.gutter` at a
negative offset lands exactly on the card's own accent border — same pixel,
same color as `var(--kind)` — so it fires (confirmed via `--dump-dom`) but is
invisible. The rule that actually ships anchors to `.card` instead; see the
comment above `body.mode-edit .card[data-beat]::before` in `assets/story.css`,
and `notes/2026-07-28-session-17-beat-flag.md`. Left as-written above since
it's what was designed and tried, not what shipped.]

Edit mode is where Jess can change it, so that's where seeing the rhythm of
stops across the whole board pays for the ink. Explore and narrate stay clean —
in narrate especially, the board is the story and a row of authoring marks would
be noise.

## 3. `story.js`: `isMessage` becomes `isBeat`

```js
const isBeat = c => c.dataset.beat === 'true';
```

`beatForwardTo`, `beatBackTo` and the shift-arrow branch already funnel through
this one predicate, so they're untouched. The long comment above `isMessage`
explaining *why* subagent messages don't count moves to the parser, next to the
`nested:` logic that now enforces it.

The **detail pane shows the cue in every mode**: the header line becomes
`Assistant · 14:32 · 🥁` when the selected card is a beat, nothing when it
isn't. Read-only — a cue for Jess's eye, not a control. It costs no renderer
work, since it reads `card.dataset.beat` at selection time. The detail pane is
collapsed during narration anyway, so this can't leak into a talk.

## 4. Edits: the sidecar grows a section

An override is a hand edit, so it belongs in `edits/<name>.yaml` alongside the
hand-written summaries — same reason: `story.yaml` stays 100% derived, and a
parser improvement still reaches every card Jess hasn't touched.

The flat `ref: summary` map becomes two named sections:

```yaml
summaries:
  episode-8-before:15: Here's how it works today...
beats:
  episode-8-before:35: false
  episode-8-before:104: true
```

`Edits` gains `@beats` beside `@summaries`, with `beat(ref)` / `set_beat(ref,
bool)` mirroring `[]` / `set`, and `apply` writing `event["beat"]` from the
override. Both sections sort by log-then-line as today, so the file reads in
story order.

Because an override can be `true`, Jess can put a stop on a tool call, or inside
a subagent, not only switch messages off. Stale-ref reporting covers beats too —
same "the log moved" honesty as summaries.

The one existing sidecar (`edits/episode-8-before.yaml`, 8 entries) is converted
in the same commit. The loader accepts **only** the new shape: one file, in the
repo, no deployed readers — a back-compat branch would be dead code the day it
shipped.

**No `beat_edited` stamp.** `summary_edited` exists because a hand-written
summary must beat the composed card face and earn the ✎. A beat override has no
composed face to beat and nothing to mark — the marker says "this is a beat",
not "Jess chose this".

## 5. Write path: `PUT /api/beat`

Mirrors `/api/summary` exactly: `{story, ref, beat}` → write the sidecar → shell
out to `bin/parse` and `bin/render`. Nothing patches YAML or HTML in place, so a
reload still matches `rake build`.

The checkbox **submits on toggle**, with no Save button. A boolean has no draft
state to protect: unlike a summary, you can't half-type it, and the round trip
is the same pipeline either way. Undo is unchecking it.

Gated the same way the summary editor is: built only when `/api/health` answers
**and** the page is in edit mode. The detail-pane cue (§3) is *not* gated — it
paints on the published site too, same as the ✎ marker.

## 6. Tests

- **Golden test** (`test/story_events.rb` and friends): assert the `beat` count
  per example, and that **zero** events inside any `subagent.events` carry
  `beat` — that's the §1 wrinkle, and a regression there is invisible on the
  page until a talk breaks.
- **`bin/check-edit-api`**: PUT a `beat: false`, assert sidecar + `story.yaml` +
  page HTML all three agree, then clear it and assert it's gone. Plus the
  existing path-traversal and unknown-ref refusals on the new endpoint.
- **`bin/check-modes`**: with one message's beat turned off, shift+arrow skips it
  and lands on the next beat. Read the trap list at the top of that script
  first.

## Out of scope

- A count of beats in the header stats. Nice, maybe later; not needed to choose
  where to stop.
- Bulk editing ("turn off every beat in this stretch"). One card at a time until
  we know the shape of the tedium.
