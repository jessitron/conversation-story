# Mount Interactive — design

_Written 2026-07-27, before implementation. Supersedes the Mount Interactive
bullets in `TODO.md`._

The North Star says "I can step through it." Today the only way forward is
clicking the next card and scrolling. This design makes the page a thing you
*drive*: three modes, a keyboard map, and a narrate mode that reveals the
conversation a beat at a time while Jess talks over it.

No Ruby logic changes. No schema change. This is `story.js`, `story.css`, and
the header markup in `page.html.erb` + `design-prototype.html`.

## 1. The mode model

One class on `<body>`: `mode-explore`, `mode-edit`, or `mode-narrate`. Exactly
one, always. A segmented switch in the header — where the focus toggle is now —
shows all three, with `aria-pressed` on the live one.

**Focus mode is removed entirely**: the `#focus-toggle` button, its JS listener,
and the `body.focus-mode` CSS rule. It was a good idea that the mode switch
makes redundant; if filtering comes back it comes back as its own thing.

Mode lives in the URL as `?mode=narrate`, written with `replaceState` alongside
the existing `#ref` fragment. `explore` is the default and is omitted, so
ordinary links look exactly like they do today. This is what makes "the talk
tab" bookmarkable — a URL can say both *which mode* and *which card*.

**Edit mode still depends on the server.** The Edit button renders `hidden` and
un-hides only when the `GET /api/health` probe answers. `?mode=edit` on the
published site falls back to explore without complaint. This is the same
progressive enhancement `body.editable` does today, re-expressed as a mode: the
summary editor is built when `mode === 'edit'` *and* the probe succeeded.

**The ✎ edited marker stops being edit-only.** Today it's gated behind
`body.editable`, so it never paints on GitHub Pages. It should show in all three
modes and on the published site: "this line is Jess's, not the parser's" is part
of the story, not an authoring affordance. The summary text itself already shows
everywhere and continues to.

## 2. Sidebar behavior

Open/collapsed becomes **sticky state Jess owns**, not something selection
resets underneath her.

- Clicking a **different** card selects it and opens the sidebar.
- Clicking the **active** card collapses the sidebar. Clicking again reopens.
- **Escape** collapses the sidebar. If it's already collapsed, Escape clears the
  selection (explore/edit) or exits to explore (narrate). Innermost thing first.
- **Arrow-key navigation does not force the sidebar open.** So "browse the cards
  with the stage clear" is a real, reachable state.
- The `Details` reopen tab is **deleted** — it's visual noise during narration
  and clicking any card brings the sidebar back.

`selectCard` currently does `body.classList.remove('sidebar-collapsed')`. That
line moves out to the click handler, which is the only place an *open* is
actually intended.

## 3. Keyboard map

One delegated `keydown` on `window`. It **ignores every key when focus is inside
an `input`, `textarea`, or `contenteditable`** — otherwise typing "e" in the
summary box would throw you into another mode. This guard is the first line of
the handler, not an afterthought.

| key | explore / edit | narrate |
|---|---|---|
| `→` | select next visible card | reveal **one** card |
| `←` | select previous visible card | un-reveal **one** card |
| `shift+→` | next **user/assistant** card, scrolled into view | reveal one **beat** |
| `shift+←` | previous **user/assistant** card, scrolled into view | un-reveal one **beat** |
| `n` | enter narrate | reveal one beat (same as `shift+→`) |
| `p` | — | un-reveal one beat (same as `shift+←`) |
| `x` / `e` / `N` | switch to explore / edit / narrate | same |
| `Esc` | collapse sidebar → else clear selection | collapse sidebar → else exit to explore |

The shape is the same in both modes: **unshifted moves one card, shifted moves a
message**. `n`/`p` are shift-arrow's easier-to-press aliases, which is what a
hand on a clicker wants. Lowercase `n` in explore enters narrate (forgiving —
nothing else claims it there); `N` is the documented key. `e` is a no-op when
the probe hasn't answered, matching the hidden Edit button.

## 4. Narrate mechanics

A **beat** is a run of cards ending at the next `.k-user` or `.k-assistant`,
inclusive. The last beat in a story may have no message at its end; it simply
runs to the end of the timeline.

**Reveal is a class toggle**, nothing else: `body.mode-narrate .card { display:
none }` plus `.card.revealed`. No data changes, nothing removed from the DOM, and
`getElementById` still resolves a deep link into a card that hasn't appeared yet.

**Selection follows the newest revealed card**, whatever its kind. `→` reveals
and selects a tool call; `n` lands selection on the message that ends the beat.
In narrate the sidebar is shut, so selection is a highlight (plus the causal-chain
`.related` glow) — and it keeps the URL fragment pointing at where Jess actually
is, so a reload resumes rather than restarting.

**Entering narrate** starts from the URL fragment if there is one — everything up
to and including that card is revealed and it stays selected — and otherwise
starts on an **empty stage**. No hint text; this is Jess's app.

The distinction matters because `syncFromHash` auto-selects a default card when
there's no fragment, so "a card is active" is not the same as "Jess chose a
card." Only a real fragment counts as "start here."

**Every advance or retreat collapses the sidebar first**, so drilling into a card
mid-narration is deliberate and self-clearing: click to open, press on to close.

**Timing and scroll.** A beat's cards appear ~80ms apart. Each card as it appears
gets `scrollIntoView({ block: 'nearest' })`; the card that ends the press
finishes with `{ block: 'center', behavior: 'smooth' }`. Un-revealing is
immediate — no reverse animation.

**Exiting narrate** (Esc, `x`, or the switch) reveals everything again and keeps
the current selection, so Jess lands in explore looking at the card she was just
narrating.

### Edge cases

- `→` at the end of the timeline, or `←` with nothing revealed: no-op, no error.
- `shift+←` mid-beat (reached by `→`) backs up to the *previous* message
  boundary, and always un-reveals at least one card.
- Hidden events have no card at all (parser-level), so they never participate.

## 5. Staging and verification

Four commits, each independently usable:

1. **Sidebar behavior** (§2) — smallest change, immediately better in the app
   as it stands.
2. **Mode scaffold** (§1) — the switch, the body class, the URL param, edit
   gated on the probe, focus mode deleted.
3. **Keyboard navigation** (§3) — explore/edit half of the table.
4. **Narrate** (§4).

`design-prototype.html` links the same `assets/story.css` and `assets/story.js`,
so its header markup changes with `page.html.erb` in the same commit or it
drifts — which is the whole point of the prototype linking the real assets.

**`bin/check-modes`** (new), following `bin/check-anchors`' headless-Chrome
pattern, asserts:

- each hotkey sets the expected `body.mode-*` class, and `?mode=narrate` loads
  straight into it;
- `→` in explore moves selection to the next visible card, `shift+→` to the next
  user/assistant card;
- a `n` press in narrate reveals exactly through the next message and no
  further, and `p` puts it back;
- Escape collapses before it clears, and clears before it exits;
- keys inside the summary textarea change nothing;
- `?mode=edit` on a page with no server degrades to explore.

`bin/check-anchors` and `bin/check-edit-api` must still pass — fragment
resolution and the write path are both touched by this.
