# Mount Interactive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the story page into something you drive — three modes
(explore / edit / narrate), a keyboard map, and a narrate mode that reveals the
conversation one beat at a time.

**Architecture:** All behavior lives in `assets/story.js` as four small modules
(sidebar state, mode, keyboard, narrate) that talk to the DOM through a body
class and a `.revealed` card class. Nothing is added to the schema and no Ruby
logic changes — `page.html.erb` swaps one header widget and drops one button.
Verification is a new `bin/check-modes`: an HTML harness that iframes a built
page and dispatches real `KeyboardEvent`s into it under headless Chrome.

**Tech Stack:** Vanilla ES2015+ browser JS (no build step, no framework), plain
CSS, ERB templates, Ruby 4 stdlib for the check script, headless Google Chrome.

**Spec:** `notes/2026-07-27-mount-interactive-design.md`. Read it first.

## Global Constraints

- **Ruby 4, stdlib only.** `json`, `yaml`, `erb`, `tmpdir`, `open3`. No Gemfile,
  no new gems. `bin/check-modes` must not require `webrick` — it runs against
  `file://` URLs, not `bin/serve`.
- **`assets/` is the source of truth.** Edit `assets/story.js` and
  `assets/story.css`; the build copies them into `out/assets/`. Never edit
  `out/assets/*` by hand.
- **`assets/design-prototype.html` links the real `assets/story.css` and
  `assets/story.js`.** Any header markup change in
  `lib/conversation_story/templates/page.html.erb` must be mirrored there in the
  same commit, or the prototype drifts from what ships.
- **Fragments carry colons** (`episode-8-before:174`). Resolve ids with
  `document.getElementById`, **never** `querySelector('#' + id)`, and add no
  id-based CSS selectors.
- **Progressive enhancement stays.** The published GitHub Pages site runs this
  same JS with no server. Nothing may throw or look broken when
  `GET /api/health` 404s.
- **The renderer already emits `data-edited`** on cards whose summary is
  hand-written. No parser or renderer change is needed to un-gate the ✎ marker.
- Commit messages are tagged `- claude` on their own last line.
- After every task: `rake build && rake test && bin/check-anchors` must pass.

---

### Task 1: Test harness + sidebar behavior

Builds `bin/check-modes` (needed by every later task) and uses it to drive the
sidebar changes from §2 of the spec. The harness comes first because it is the
only way to test any of this.

**Files:**
- Create: `bin/check-modes`
- Modify: `assets/story.js` (`selectCard`, `clearSelection`, the `#cards` click
  handler; delete the `#reopen` listener)
- Modify: `assets/story.css` (delete the `.reopen` rules)
- Modify: `lib/conversation_story/templates/page.html.erb` (delete the reopen button)
- Modify: `assets/design-prototype.html` (delete the reopen button)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces, in `bin/check-modes`, a JS harness whose scenario table later tasks
  append to. Each scenario is `{ name, run: async (win, doc, h) => string|null }`
  returning `null` for pass or a failure message. Helpers on `h`:
  `h.key(win, key, opts)` dispatches a `keydown` on the iframe's `window`;
  `h.click(el)` dispatches a real `click`; `h.sleep(ms)` awaits a timer;
  `h.cards(doc)` returns an array of all `.card` elements; `h.active(doc)`
  returns the `.card.active` element or `null`.
- Produces, in `assets/story.js`: `collapseSidebar()`, `openSidebar()`, and a
  `selectCard(card)` that no longer touches `sidebar-collapsed`.

- [ ] **Step 1: Write the harness**

Create `bin/check-modes`, `chmod +x` it. This is the whole file; later tasks
only add entries to `SCENARIOS`.

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Drive a built story page with real keystrokes and check what it does
# (Mount Interactive: modes, keyboard navigation, narrate).
#
#   bin/check-modes [example-name]
#
# HOW THIS WORKS. Headless Chrome can dump a page's DOM but cannot type into
# it. So we write a harness page to a temp dir that iframes the built page and
# dispatches synthetic KeyboardEvents into the iframe's window. Reaching into
# another file:// document needs --allow-file-access-from-files, which makes
# Chrome treat all file:// URLs as one origin. Each scenario reloads the iframe,
# so scenarios never inherit each other's state, and one Chrome launch runs them
# all. Results are written into the harness DOM and read back with --dump-dom.
#
# No server: this runs against file://, so it needs no webrick and no bin/serve.

require "tmpdir"

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
REPO   = File.expand_path("..", __dir__)
STORY  = ARGV[0] || "episode-8-before"
PAGE   = File.join(REPO, "out", STORY, "index.html")

abort "no such page: #{PAGE} (run 'rake build')" unless File.exist?(PAGE)
abort "Chrome not found at #{CHROME}" unless File.exist?(CHROME)

# Each scenario gets a freshly loaded iframe. `query` is appended to the page
# URL (before the fragment), `hash` is the fragment. Return null to pass, or a
# string describing what went wrong.
SCENARIOS = <<~JS
  const SCENARIOS = [
    {
      name: 'clicking a second card opens the sidebar on it',
      run: async (win, doc, h) => {
        const cards = h.cards(doc);
        h.click(cards[2]);
        await h.sleep(20);
        if (h.active(doc) !== cards[2]) return 'card 2 is not active';
        if (doc.body.classList.contains('sidebar-collapsed')) return 'sidebar collapsed';
        return null;
      },
    },
    {
      name: 'clicking the active card collapses the sidebar, clicking again reopens',
      run: async (win, doc, h) => {
        const cards = h.cards(doc);
        h.click(cards[2]); await h.sleep(20);
        h.click(cards[2]); await h.sleep(20);
        if (!doc.body.classList.contains('sidebar-collapsed')) return 'did not collapse';
        if (h.active(doc) !== cards[2]) return 'lost the selection on collapse';
        h.click(cards[2]); await h.sleep(20);
        if (doc.body.classList.contains('sidebar-collapsed')) return 'did not reopen';
        return null;
      },
    },
    {
      name: 'Escape collapses the sidebar, then clears the selection',
      run: async (win, doc, h) => {
        const cards = h.cards(doc);
        h.click(cards[2]); await h.sleep(20);
        h.key(win, 'Escape'); await h.sleep(20);
        if (!doc.body.classList.contains('sidebar-collapsed')) return 'first Escape did not collapse';
        if (h.active(doc) !== cards[2]) return 'first Escape also cleared the selection';
        h.key(win, 'Escape'); await h.sleep(20);
        if (h.active(doc)) return 'second Escape did not clear the selection';
        return null;
      },
    },
    {
      name: 'the Details reopen tab is gone',
      run: async (win, doc, h) => (doc.getElementById('reopen') ? 'reopen button still in the DOM' : null),
    },
  ];
JS

HARNESS = <<~HTML
  <!DOCTYPE html><meta charset="utf-8">
  <body><iframe id="f" width="1200" height="900"></iframe><div id="out"></div>
  <script>
  #{SCENARIOS}
  const frame = document.getElementById('f');
  const out = document.getElementById('out');
  const PAGE = new URLSearchParams(location.search).get('page');

  const h = {
    sleep: ms => new Promise(r => setTimeout(r, ms)),
    key: (win, key, opts = {}) =>
      win.dispatchEvent(new win.KeyboardEvent('keydown',
        Object.assign({ key, bubbles: true, cancelable: true }, opts))),
    click: el =>
      el.dispatchEvent(new el.ownerDocument.defaultView.MouseEvent('click',
        { bubbles: true, cancelable: true })),
    cards: doc => Array.from(doc.querySelectorAll('.card')),
    active: doc => doc.querySelector('.card.active'),
  };

  function load(url) {
    return new Promise(resolve => {
      frame.addEventListener('load', () => resolve(), { once: true });
      frame.src = url;
    });
  }

  function report(name, failure) {
    const div = document.createElement('div');
    div.className = 'r';
    div.textContent = 'RESULT\\t' + name + '\\t' + (failure ? 'FAIL\\t' + failure : 'PASS');
    out.appendChild(div);
  }

  (async () => {
    for (const s of SCENARIOS) {
      await load(PAGE + (s.query || '') + (s.hash || ''));
      await h.sleep(30);   // let story.js finish its initial paint
      const win = frame.contentWindow, doc = frame.contentDocument;
      try { report(s.name, await s.run(win, doc, h)); }
      catch (e) { report(s.name, 'threw: ' + (e && e.message)); }
    }
    document.title = 'DONE';
  })();
  </script></body>
HTML

dom = nil
Dir.mktmpdir("check-modes") do |dir|
  harness = File.join(dir, "harness.html")
  File.write(harness, HARNESS)
  url = "file://#{harness}?page=file://#{PAGE}"
  dom = `"#{CHROME}" --headless --disable-gpu --virtual-time-budget=20000 \
         --allow-file-access-from-files --dump-dom "#{url}" 2>/dev/null`
end

results = dom.to_s.scan(%r{<div class="r">RESULT\t(.*?)</div>}m).flatten
abort "no results — the harness never ran (is Chrome working?)" if results.empty?

failed = 0
results.each do |line|
  name, verdict, detail = line.split("\t")
  if verdict == "PASS"
    puts "OK    #{name}"
  else
    failed += 1
    puts "FAIL  #{name} — #{detail}"
  end
end

puts "#{results.length - failed}/#{results.length} scenarios passed"
exit(failed.zero? ? 0 : 1)
```

- [ ] **Step 2: Run it to watch the sidebar scenarios fail**

```sh
rake build && bin/check-modes
```

Expected: the harness runs and reports failures — `clicking the active card
collapses…` fails ("did not collapse", since the current click handler
early-returns on the active card), `Escape collapses…` fails (no keyboard
handler exists yet), and `the Details reopen tab is gone` fails. The first
scenario should already PASS. If you get "no results", fix the harness before
touching `story.js` — every later task depends on it.

- [ ] **Step 3: Make the sidebar sticky in `assets/story.js`**

Add these two helpers next to `selectCard`:

```js
/* The sidebar's open/collapsed state is Jess's, not selection's. Only an
   explicit open (clicking a card) or an explicit collapse (clicking the active
   card, Escape, ×, or advancing a narration beat) moves it. */
function collapseSidebar() { body.classList.add('sidebar-collapsed'); }
function openSidebar()     { body.classList.remove('sidebar-collapsed'); }
```

In `selectCard`, **delete** this line:

```js
  body.classList.remove('sidebar-collapsed');
```

In `clearSelection`, **delete** the same line.

Replace the `#cards` click handler's active-card early return so clicking the
active card toggles the sidebar:

```js
  e.preventDefault();
  if (card.classList.contains('active')) {          // clicking the open card closes it
    body.classList.toggle('sidebar-collapsed');
    return;
  }
  setFragment('#' + card.id);
  selectCard(card);
  openSidebar();
```

Delete the `#reopen` listener line entirely:

```js
document.getElementById('reopen').addEventListener('click', () => body.classList.remove('sidebar-collapsed'));
```

Add the Escape handler (the full keyboard map arrives in Task 3; this is the
one key Task 1 owns):

```js
/* ---- keyboard ----
   Escape peels one layer at a time: an open sidebar first, then the selection.
   Ignored while typing, so Escape in the summary box still means "revert the
   box" (see showSummaryEditor). */
const TYPING = 'input, textarea, select, [contenteditable]';

window.addEventListener('keydown', e => {
  if (e.target.closest && e.target.closest(TYPING)) return;
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key !== 'Escape') return;
  e.preventDefault();
  if (!body.classList.contains('sidebar-collapsed')) { collapseSidebar(); return; }
  setFragment(location.pathname + location.search);
  clearSelection();
});
```

- [ ] **Step 4: Delete the reopen button from both pages**

In `lib/conversation_story/templates/page.html.erb`, delete:

```erb
<button class="reopen deco" id="reopen">Details</button>
```

Delete the identical line from `assets/design-prototype.html` (around line 408).

In `assets/story.css`, delete the whole `.reopen` block and its
`body.sidebar-collapsed .reopen` rule, including the
`/* Floating re-open tab when collapsed */` comment above them.

- [ ] **Step 5: Run the checks**

```sh
rake build && bin/check-modes && bin/check-anchors && rake test
```

Expected: all four `bin/check-modes` scenarios OK, `bin/check-anchors` OK,
`rake test` green.

- [ ] **Step 6: Commit**

```sh
git add bin/check-modes assets/story.js assets/story.css \
        assets/design-prototype.html \
        lib/conversation_story/templates/page.html.erb out/
git commit -m "Sidebar open/collapsed is sticky state, plus a keyboard test harness

Selecting a card no longer forces the sidebar open, so 'browse with the stage
clear' is a reachable state. Clicking the active card toggles it; Escape peels
the sidebar first and the selection second. The Details reopen tab is gone --
clicking any card brings the sidebar back.

bin/check-modes is new: headless Chrome cannot type, so it loads a harness page
that iframes the built page and dispatches real KeyboardEvents into it.

- claude"
```

---

### Task 2: Mode scaffold

Implements §1 of the spec: three modes on a body class, a header switch, the
`?mode=` URL parameter, edit gated on the server probe, focus mode deleted, and
the ✎ marker un-gated.

**Files:**
- Modify: `lib/conversation_story/templates/page.html.erb` (replace `#focus-toggle`)
- Modify: `assets/design-prototype.html` (same replacement)
- Modify: `assets/story.css` (rename `.focus-toggle` rules to `.mode-switch`,
  delete `body.focus-mode`, un-gate the ✎)
- Modify: `assets/story.js` (mode module; delete the focus toggle listener;
  rework the `/api/health` probe)
- Modify: `bin/check-modes` (new scenarios)

**Interfaces:**
- Consumes: `collapseSidebar()`, `openSidebar()` from Task 1.
- Produces: `setMode(name)`, the module-scoped `let mode` (one of `'explore'`,
  `'edit'`, `'narrate'`), `let editingAvailable` (boolean, true once the probe
  answers), and `setUrl(pathQueryHash)` replacing the old `setFragment`.
  Task 3 calls `setMode`; Task 4 hooks `enterNarrate`/`exitNarrate` into it.

- [ ] **Step 1: Add the failing scenarios to `bin/check-modes`**

Append to the `SCENARIOS` array (inside the heredoc), before the closing `];`:

```js
    {
      name: 'the page starts in explore mode',
      run: async (win, doc, h) => (doc.body.classList.contains('mode-explore')
        ? null : 'body classes: ' + doc.body.className),
    },
    {
      name: 'N switches to narrate, x back to explore',
      run: async (win, doc, h) => {
        h.key(win, 'N', { shiftKey: true }); await h.sleep(20);
        if (!doc.body.classList.contains('mode-narrate')) return 'N did not enter narrate';
        if (!win.location.search.includes('mode=narrate')) return 'URL is ' + win.location.search;
        h.key(win, 'x'); await h.sleep(20);
        if (!doc.body.classList.contains('mode-explore')) return 'x did not return to explore';
        if (win.location.search.includes('mode=')) return 'explore left mode= in the URL';
        return null;
      },
    },
    {
      name: '?mode=narrate loads straight into narrate',
      query: '?mode=narrate',
      run: async (win, doc, h) => (doc.body.classList.contains('mode-narrate')
        ? null : 'body classes: ' + doc.body.className),
    },
    {
      name: 'edit mode is unavailable with no server: button hidden, ?mode=edit degrades',
      query: '?mode=edit',
      run: async (win, doc, h) => {
        await h.sleep(60);   // let the /api/health probe fail
        if (!doc.body.classList.contains('mode-explore')) return 'did not degrade to explore';
        const btn = doc.querySelector('#mode-switch [data-mode="edit"]');
        if (!btn) return 'no edit button in the switch';
        if (!btn.hidden) return 'edit button is visible with no server';
        h.key(win, 'e'); await h.sleep(20);
        if (doc.body.classList.contains('mode-edit')) return 'e entered edit with no server';
        return null;
      },
    },
    {
      name: 'focus mode is gone',
      run: async (win, doc, h) => (doc.getElementById('focus-toggle')
        ? 'focus-toggle still in the DOM' : null),
    },
```

- [ ] **Step 2: Run to verify they fail**

```sh
bin/check-modes
```

Expected: the five new scenarios FAIL (no `mode-explore` class, no
`#mode-switch`, `focus-toggle still in the DOM`); Task 1's four still pass.

- [ ] **Step 3: Replace the header widget in both pages**

In `lib/conversation_story/templates/page.html.erb`, replace the
`focus-toggle` button line with:

```erb
  <div class="mode-switch deco" id="mode-switch" role="group" aria-label="Mode">
    <button type="button" data-mode="explore" aria-pressed="true">Explore</button>
    <button type="button" data-mode="edit" aria-pressed="false" hidden>Edit</button>
    <button type="button" data-mode="narrate" aria-pressed="false">Narrate</button>
  </div>
```

Put the identical block in `assets/design-prototype.html` in place of its
`focus-toggle` line (around line 28).

- [ ] **Step 4: Restyle in `assets/story.css`**

Replace the `header.site .focus-toggle` and
`header.site .focus-toggle:hover, header.site .focus-toggle[aria-pressed="true"]`
rules with:

```css
header.site .mode-switch {
  margin-left: 22px; flex: 0 0 auto;
  display: flex; border: 1px solid rgba(247,243,234,.35); border-radius: 2px;
  overflow: hidden;
}
header.site .mode-switch button {
  background: transparent; border: none; color: var(--paper);
  font-family: inherit;
  font-size: var(--fs-small); letter-spacing: var(--ls-wide);
  padding: 7px 12px; cursor: pointer;
}
header.site .mode-switch button + button { border-left: 1px solid rgba(247,243,234,.35); }
header.site .mode-switch button:hover { background: rgba(247,243,234,.14); }
header.site .mode-switch button[aria-pressed="true"] {
  background: rgba(247,243,234,.14); color: var(--yellow);
}
```

Delete the focus-mode rule and the comment above it:

```css
/* ---- focus mode: hide everything but the direct back-and-forth with Jess --- */
body.focus-mode .card:not(.k-user):not(.k-assistant) { display: none; }
```

Un-gate the ✎ marker — replace that rule and its comment with:

```css
/* Which cards carry Jess's words instead of the parser's. Shown in every mode
   and on the published site: whose sentence this is belongs to the story, not
   to the authoring UI. */
.card[data-edited] .summary::after {
  content: "✎"; margin-left: 8px; color: var(--gold); font-size: var(--fs-small);
}
```

Update the Mount Malleable section comment above it — the line claiming "the ✎
marker never paints" on Pages is now false. Change:

```css
   authoring server (bin/serve) and only adds body.editable when it answers, so
   on GitHub Pages the editor is never built and the ✎ marker never paints.
```

to:

```css
   authoring server (bin/serve) and only offers Edit mode when it answers, so on
   GitHub Pages the editor is never built. (The ✎ marker is NOT part of this —
   it paints everywhere; see the rule at the end of this section.)
```

- [ ] **Step 5: Add the mode module to `assets/story.js`**

Generalize the URL writer. Replace `setFragment` with:

```js
/* Write path+query+fragment without scrolling or firing hashchange. Wrapped
   because some browsers block history writes on file:// URLs — selection and
   mode must still work when the URL can't be updated. */
function setUrl(url) {
  try { history.replaceState(null, '', url); } catch (_) { /* file:// */ }
}
function setFragment(frag) { setUrl(frag); }
```

Add the mode module after the focus-mode section you're about to delete:

```js
/* ============================================================
   Modes — explore / edit / narrate.

   Exactly one body.mode-* class at a time. The mode is in the URL as
   ?mode=narrate so "the talk tab" is bookmarkable alongside the #ref that says
   which card; explore is the default and stays out of the URL, so ordinary
   links look untouched.

   Edit depends on the local authoring server. Its button ships hidden and
   un-hides only when GET /api/health answers, so ?mode=edit on the published
   site quietly falls back to explore.
   ============================================================ */
const MODES = ['explore', 'edit', 'narrate'];
const modeSwitch = document.getElementById('mode-switch');
const modeButtons = Array.from(modeSwitch.querySelectorAll('button'));
let mode = 'explore';
let editingAvailable = false;

function setMode(next) {
  if (!MODES.includes(next)) return;
  if (next === 'edit' && !editingAvailable) return;
  if (next === mode) return;
  const prev = mode;
  mode = next;

  MODES.forEach(m => body.classList.toggle('mode-' + m, m === mode));
  modeButtons.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.mode === mode)));

  const q = new URLSearchParams(location.search);
  if (mode === 'explore') q.delete('mode'); else q.set('mode', mode);
  const qs = q.toString();
  setUrl(location.pathname + (qs ? '?' + qs : '') + location.hash);

  onModeChange(prev, mode);
}

/* Per-mode entry/exit work. Task 4 fills in the narrate half; keeping it in one
   function means setMode never grows a chain of special cases. */
function onModeChange(prev, next) {
  const active = document.querySelector('.card.active');
  if (active) selectCard(active);   // rebuild the detail: the editor is edit-only
}

modeSwitch.addEventListener('click', e => {
  const btn = e.target.closest('button[data-mode]');
  if (btn) setMode(btn.dataset.mode);
});
```

Delete the whole focus-mode section — its comment block, `const focusToggle`,
and the listener.

Gate the summary editor on the mode. In `showSummaryEditor`, change the guard:

```js
function showSummaryEditor(card) {
  if (!editingAvailable || mode !== 'edit') return;
```

and delete `let editing = false;` (replaced by `editingAvailable`).

Rework the probe at the bottom of the file:

```js
fetch('/api/health')
  .then(r => (r.ok ? r.json() : Promise.reject(new Error('static'))))
  .then(info => {
    if (!info.editing) return;
    editingAvailable = true;
    modeButtons.find(b => b.dataset.mode === 'edit').hidden = false;
    if (wantedMode === 'edit') setMode('edit');
  })
  .catch(() => { /* published site: no write path, no edit mode */ });
```

Set the starting mode just above the existing `syncFromHash()` call at the
bottom, so the initial paint honors both the fragment and `?mode=`:

```js
/* initial paint: honor a deep link if present, else open the default card */
syncFromHash();

/* ...then the mode. `wantedMode` is remembered because ?mode=edit can't be
   honored until the health probe answers, which is after this runs. */
const wantedMode = new URLSearchParams(location.search).get('mode');
body.classList.add('mode-explore');
if (wantedMode && wantedMode !== 'edit') setMode(wantedMode);
```

Note `wantedMode` is referenced inside the probe callback above it — that's
fine, `const` is hoisted to the module scope and the callback runs later. Keep
the declaration where the initial paint happens; that's where it reads.

- [ ] **Step 6: Run the checks**

```sh
rake build && bin/check-modes && bin/check-anchors && rake test
```

Expected: all nine scenarios OK. Then look at it:

```sh
bin/screenshot episode-8-before '#episode-8-before:174' /tmp/modes.png
```

Expected: the header shows a two-segment Explore | Narrate switch (Edit is
hidden — there's no server behind a screenshot), with Explore lit.

- [ ] **Step 7: Commit**

```sh
git add assets/ lib/conversation_story/templates/page.html.erb bin/check-modes out/
git commit -m "Three modes on a body class, with ?mode= in the URL

explore / edit / narrate as a header switch and a body.mode-* class, replacing
the focus toggle (deleted -- the mode switch makes it redundant). The mode is a
URL query param so a bookmark can say both which mode and which card. Edit is
gated on the /api/health probe, so ?mode=edit degrades to explore on Pages.

The pencil marker for a hand-written summary now paints everywhere, not just
in the authoring UI: whose sentence it is belongs to the story.

- claude"
```

---

### Task 3: Keyboard navigation

Implements the explore/edit half of §3: arrows move the selection, shift-arrows
jump between user/assistant messages, `x`/`e`/`N`/`n` switch modes.

**Files:**
- Modify: `assets/story.js` (extend the keydown handler from Task 1)
- Modify: `bin/check-modes` (new scenarios)

**Interfaces:**
- Consumes: `setMode(name)`, `mode`, `editingAvailable` (Task 2);
  `collapseSidebar()` (Task 1).
- Produces: `CARDS` (a materialized `Array` of every `.card`, in document
  order), `isMessage(card)`, `navigable()` (the cards the arrows may land on),
  and `moveSelection(dir, byMessage)`. Task 4 uses `CARDS`, `isMessage`, and
  `navigable`.

- [ ] **Step 1: Add the failing scenarios to `bin/check-modes`**

Append to `SCENARIOS`:

```js
    {
      name: 'right arrow moves the selection one card, left arrow back',
      run: async (win, doc, h) => {
        const cards = h.cards(doc);
        h.click(cards[3]); await h.sleep(20);
        h.key(win, 'ArrowRight'); await h.sleep(20);
        if (h.active(doc) !== cards[4]) return 'right did not land on card 4';
        h.key(win, 'ArrowLeft'); await h.sleep(20);
        if (h.active(doc) !== cards[3]) return 'left did not return to card 3';
        return null;
      },
    },
    {
      name: 'shift+right jumps to the next user/assistant card',
      run: async (win, doc, h) => {
        const cards = h.cards(doc);
        const isMsg = c => c.classList.contains('k-user') || c.classList.contains('k-assistant');
        h.click(cards[0]); await h.sleep(20);
        h.key(win, 'ArrowRight', { shiftKey: true }); await h.sleep(20);
        const landed = h.active(doc);
        if (!isMsg(landed)) return 'landed on a ' + landed.className;
        const expected = cards.slice(1).find(isMsg);
        if (landed !== expected) return 'skipped past the first message';
        return null;
      },
    },
    {
      name: 'arrow navigation leaves a collapsed sidebar collapsed',
      run: async (win, doc, h) => {
        const cards = h.cards(doc);
        h.click(cards[2]); await h.sleep(20);
        h.key(win, 'Escape'); await h.sleep(20);   // collapse
        h.key(win, 'ArrowRight'); await h.sleep(20);
        if (!doc.body.classList.contains('sidebar-collapsed')) return 'arrow popped the sidebar open';
        if (h.active(doc) !== cards[3]) return 'arrow did not move the selection';
        return null;
      },
    },
    {
      name: 'keys typed in the summary box do not reach the page',
      run: async (win, doc, h) => {
        const ta = doc.createElement('textarea');   // stand-in: no server, so no real editor
        doc.body.appendChild(ta);
        const before = doc.body.className;
        ta.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'N', shiftKey: true, bubbles: true }));
        await h.sleep(20);
        return doc.body.className === before ? null : 'typing changed the mode';
      },
    },
```

- [ ] **Step 2: Run to verify they fail**

```sh
bin/check-modes
```

Expected: the four new scenarios FAIL ("right did not land on card 4" etc.);
the previous nine still pass. The typing scenario may pass already — Task 1's
`TYPING` guard covers it — that's fine; it's there so Task 3 can't regress it.

- [ ] **Step 3: Extend the keyboard handler in `assets/story.js`**

Just above the keydown listener, add:

```js
/* Every card in document order, materialized once. `navigable` is the subset
   the arrows may land on — all of them, except in narrate where only what has
   been revealed exists to the user yet. */
const CARDS = Array.from(cards);
const isMessage = c => c.classList.contains('k-user') || c.classList.contains('k-assistant');
function navigable() {
  return mode === 'narrate' ? CARDS.filter(c => c.classList.contains('revealed')) : CARDS;
}

/* Move the selection by one card, or by one user/assistant message with shift.
   Does NOT open the sidebar — that state is Jess's (see collapseSidebar). */
function moveSelection(dir, byMessage) {
  const list = navigable();
  if (!list.length) return;
  const active = document.querySelector('.card.active');
  let i = list.indexOf(active);
  if (i < 0) i = dir > 0 ? -1 : list.length;
  let next = i + dir;
  if (byMessage) {
    while (next >= 0 && next < list.length && !isMessage(list[next])) next += dir;
  }
  if (next < 0 || next >= list.length) return;
  const card = list[next];
  setFragment('#' + card.id);
  selectCard(card);
  card.scrollIntoView({ block: 'nearest' });
}
```

Replace the Task 1 keydown listener body with the full map:

```js
window.addEventListener('keydown', e => {
  if (e.target.closest && e.target.closest(TYPING)) return;
  if (e.metaKey || e.ctrlKey || e.altKey) return;

  const act = fn => { e.preventDefault(); fn(); };

  switch (e.key) {
    case 'x': return act(() => setMode('explore'));
    case 'e': return act(() => setMode('edit'));
    case 'N': return act(() => setMode('narrate'));
    case 'Escape': return act(escapeKey);
  }

  if (mode === 'narrate') return;   // Task 4 owns narrate's arrows

  switch (e.key) {
    case 'n':          return act(() => setMode('narrate'));
    case 'ArrowRight': return act(() => moveSelection(1, e.shiftKey));
    case 'ArrowLeft':  return act(() => moveSelection(-1, e.shiftKey));
  }
});

/* Escape peels one layer at a time: an open sidebar first, then the selection
   (or, in narrate, the mode itself — see Task 4's exit). */
function escapeKey() {
  if (!body.classList.contains('sidebar-collapsed')) { collapseSidebar(); return; }
  if (mode === 'narrate') { setMode('explore'); return; }
  setFragment(location.pathname + location.search);
  clearSelection();
}
```

Note `e` is bound as the event; `case 'e'` is the letter key, not the variable —
they don't collide, but don't rename either one.

- [ ] **Step 4: Run the checks**

```sh
rake build && bin/check-modes && bin/check-anchors && rake test
```

Expected: all thirteen scenarios OK.

- [ ] **Step 5: Commit**

```sh
git add assets/story.js bin/check-modes out/
git commit -m "Keyboard navigation: arrows move one card, shift-arrows one message

Unshifted moves a card, shifted moves a user/assistant message -- the same
shape narrate will use, so there is one map to remember. x/e/N switch modes,
and the handler ignores everything typed into an input or textarea so 'e' in
the summary box stays an 'e'.

- claude"
```

---

### Task 4: Narrate

Implements §4: reveal one card or one beat at a time, starting from the URL
fragment or an empty stage.

**Files:**
- Modify: `assets/story.js` (narrate module; wire `onModeChange`; narrate's arrows)
- Modify: `assets/story.css` (the reveal rule)
- Modify: `bin/check-modes` (new scenarios)
- Modify: `README.md`, `CLAUDE.md`, `TODO.md`

**Interfaces:**
- Consumes: `CARDS`, `isMessage`, `navigable` (Task 3); `setMode`,
  `onModeChange` (Task 2); `collapseSidebar` (Task 1).
- Produces: nothing later tasks need — this is the last task.

- [ ] **Step 1: Add the failing scenarios to `bin/check-modes`**

Append to `SCENARIOS`:

```js
    {
      name: 'narrate starts on an empty stage',
      query: '?mode=narrate',
      run: async (win, doc, h) => {
        const shown = h.cards(doc).filter(c => c.classList.contains('revealed'));
        if (shown.length) return shown.length + ' cards revealed on entry';
        if (!doc.body.classList.contains('sidebar-collapsed')) return 'sidebar is open';
        return null;
      },
    },
    {
      name: 'n reveals exactly through the next message; p puts it back',
      query: '?mode=narrate',
      run: async (win, doc, h) => {
        const cards = h.cards(doc);
        const isMsg = c => c.classList.contains('k-user') || c.classList.contains('k-assistant');
        h.key(win, 'n'); await h.sleep(2000);   // the beat animates ~80ms per card
        const shown = cards.filter(c => c.classList.contains('revealed'));
        if (!shown.length) return 'n revealed nothing';
        if (!isMsg(shown[shown.length - 1])) return 'beat did not end on a message';
        if (shown.slice(0, -1).some(isMsg)) return 'beat ran past a message';
        if (h.active(doc) !== shown[shown.length - 1]) return 'did not select the landing message';
        const n = shown.length;
        h.key(win, 'p'); await h.sleep(200);
        const after = cards.filter(c => c.classList.contains('revealed')).length;
        if (after >= n) return 'p did not un-reveal (' + n + ' -> ' + after + ')';
        return null;
      },
    },
    {
      name: 'right arrow in narrate reveals one card at a time',
      query: '?mode=narrate',
      run: async (win, doc, h) => {
        const cards = h.cards(doc);
        h.key(win, 'ArrowRight'); await h.sleep(200);
        h.key(win, 'ArrowRight'); await h.sleep(200);
        const shown = cards.filter(c => c.classList.contains('revealed'));
        if (shown.length !== 2) return 'expected 2 revealed, got ' + shown.length;
        if (h.active(doc) !== cards[1]) return 'newest revealed card is not selected';
        h.key(win, 'ArrowLeft'); await h.sleep(200);
        if (cards.filter(c => c.classList.contains('revealed')).length !== 1) return 'left did not un-reveal one';
        return null;
      },
    },
    {
      name: 'narrate entered on a deep link starts from that card',
      query: '?mode=narrate',
      run: async (win, doc, h) => {
        const cards = h.cards(doc);
        const target = cards[5];
        win.location.hash = '#' + target.id;
        await h.sleep(50);
        h.key(win, 'x'); await h.sleep(20);          // leave narrate
        h.key(win, 'N', { shiftKey: true }); await h.sleep(50);   // re-enter on that card
        const shown = cards.filter(c => c.classList.contains('revealed'));
        if (shown.length !== 6) return 'expected 6 revealed, got ' + shown.length;
        if (h.active(doc) !== target) return 'did not select the deep-linked card';
        return null;
      },
    },
    {
      name: 'advancing a beat closes an opened sidebar',
      query: '?mode=narrate',
      run: async (win, doc, h) => {
        h.key(win, 'ArrowRight'); await h.sleep(200);
        h.click(h.cards(doc)[0]); await h.sleep(20);
        if (doc.body.classList.contains('sidebar-collapsed')) return 'click did not open the sidebar';
        h.key(win, 'n'); await h.sleep(2000);
        if (!doc.body.classList.contains('sidebar-collapsed')) return 'n left the sidebar open';
        return null;
      },
    },
    {
      name: 'leaving narrate shows everything again',
      query: '?mode=narrate',
      run: async (win, doc, h) => {
        h.key(win, 'ArrowRight'); await h.sleep(200);
        h.key(win, 'Escape'); await h.sleep(20);   // collapsed already -> exits narrate
        if (!doc.body.classList.contains('mode-explore')) return 'Escape did not exit narrate';
        const hidden = h.cards(doc).filter(c => c.offsetParent === null);
        if (hidden.length) return hidden.length + ' cards still hidden in explore';
        return null;
      },
    },
```

- [ ] **Step 2: Run to verify they fail**

```sh
rake build && bin/check-modes
```

Expected: the six new scenarios FAIL; the previous thirteen pass. Nothing sets
`.revealed` yet, so "narrate starts on an empty stage" passes for the wrong
reason (zero revealed cards, but also every card still visible) while the rest
fail with "n revealed nothing" and friends. That's the expected shape — the
reveal rule in the next step is what makes the first one meaningful.

- [ ] **Step 3: Add the reveal rule to `assets/story.css`**

Put this where the deleted focus-mode rule was:

```css
/* ---- narrate: the stage starts empty and fills a beat at a time ----
   Reveal is a class toggle and nothing else: no card leaves the DOM, so a
   fragment still resolves to a card that has not appeared yet, and leaving
   narrate brings everything back with no re-render. */
body.mode-narrate .card { display: none; }
body.mode-narrate .card.revealed { display: grid; }
```

`display: grid` because that's what `.card` is (see the `.card` block); if you
write `block` the gutter and body stop laying out side by side.

- [ ] **Step 4: Add the narrate module to `assets/story.js`**

After the mode module:

```js
/* ============================================================
   Narrate — reveal the conversation a beat at a time.

   `revealed` is a COUNT: cards 0..revealed-1 are shown, and the newest one is
   the selection. Keeping it a prefix count (rather than a set) makes stepping
   back the same operation as stepping forward, and makes "start from this
   card" just an index lookup.

   A BEAT is a run of cards ending at the next user/assistant message,
   inclusive — one press per conversational turn, with the tool-call flurry
   visible on the way. The last beat may have no message at its end; it runs to
   the end of the timeline.
   ============================================================ */
const BEAT_MS = 80;
let revealed = 0;
let pending = [];

function clearPending() { pending.forEach(clearTimeout); pending = []; }
function renderReveal() { CARDS.forEach((c, i) => c.classList.toggle('revealed', i < revealed)); }

/* count of cards revealed after advancing one beat from `from` */
function beatForwardTo(from) {
  for (let i = from; i < CARDS.length; i++) if (isMessage(CARDS[i])) return i + 1;
  return CARDS.length;
}
/* count of cards revealed after backing up one beat from `from`; always
   un-reveals at least one card, so a half-finished beat backs up to the
   previous message rather than sitting still. */
function beatBackTo(from) {
  for (let i = from - 2; i >= 0; i--) if (isMessage(CARDS[i])) return i + 1;
  return 0;
}

/* Reveal (or hide) up to `target` cards. Going forward the new cards appear one
   after another so the flurry reads as a flurry; going back is immediate. */
function revealTo(target) {
  target = Math.min(CARDS.length, Math.max(0, target));
  clearPending();
  renderReveal();          // resync the DOM if a previous flurry was cut short
  collapseSidebar();       // the stage stays clear unless Jess clicks a card
  const from = revealed;
  if (target === from) return;
  revealed = target;
  if (target < from) { renderReveal(); landOn(); return; }

  for (let i = from; i < target; i++) {
    const card = CARDS[i], last = i === target - 1;
    pending.push(setTimeout(() => {
      card.classList.add('revealed');
      card.scrollIntoView({ block: 'nearest' });
      if (last) landOn();
    }, (i - from) * BEAT_MS));
  }
}

/* The newest revealed card is the selection — whatever its kind. That keeps the
   URL fragment pointing at where Jess actually is, so a reload resumes. */
function landOn() {
  if (!revealed) { setFragment(location.pathname + location.search); clearSelection(); return; }
  const card = CARDS[revealed - 1];
  setFragment('#' + card.id);
  selectCard(card);
  card.scrollIntoView({ block: 'center', behavior: 'smooth' });
}

/* Start from the URL fragment if there is one, else from an empty stage.
   syncFromHash auto-selects a default card when there's no fragment, so "a card
   is active" is NOT the same as "Jess chose a card" — only a real fragment
   counts as "start here". */
function enterNarrate() {
  const frag = decodeURIComponent(location.hash.slice(1));
  const at = frag ? CARDS.findIndex(c => c.id === frag) : -1;
  clearPending();
  revealed = at >= 0 ? at + 1 : 0;
  renderReveal();
  collapseSidebar();
  if (revealed) selectCard(CARDS[revealed - 1]); else clearSelection();
}

function exitNarrate() {
  clearPending();
  revealed = 0;
  CARDS.forEach(c => c.classList.remove('revealed'));
}
```

Wire it into `onModeChange` (replacing the Task 2 body):

```js
function onModeChange(prev, next) {
  if (next === 'narrate') enterNarrate();
  else if (prev === 'narrate') exitNarrate();
  const active = document.querySelector('.card.active');
  if (active) selectCard(active);   // rebuild the detail: the editor is edit-only
}
```

Give narrate its arrows — replace the `if (mode === 'narrate') return;` line in
the keydown handler with:

```js
  if (mode === 'narrate') {
    switch (e.key) {
      case 'ArrowRight': return act(() => revealTo(e.shiftKey ? beatForwardTo(revealed) : revealed + 1));
      case 'ArrowLeft':  return act(() => revealTo(e.shiftKey ? beatBackTo(revealed) : revealed - 1));
      case 'n':          return act(() => revealTo(beatForwardTo(revealed)));
      case 'p':          return act(() => revealTo(beatBackTo(revealed)));
    }
    return;
  }
```

- [ ] **Step 5: Run the checks**

```sh
rake build && bin/check-modes && bin/check-anchors && bin/check-edit-api && rake test
```

Expected: all nineteen scenarios OK, and both other check scripts green.
`bin/check-edit-api` matters here because Task 2 changed how the editor is
gated — it must still save and revert.

- [ ] **Step 6: See it by hand**

```sh
rake serve      # then open http://localhost:8080/episode-8-before/?mode=narrate
```

Press `n` a few times and confirm: the stage fills a beat at a time, the flurry
of tool calls is visible, each press lands selection on a message and closes the
sidebar, clicking a card opens it, `p` backs up, Escape drops you into explore
with everything showing. Check that Edit appears in the switch here (the server
is running) and that `e` opens the summary box.

- [ ] **Step 7: Update the docs**

In `TODO.md`, delete the whole **Mount Interactive** section — every bullet in
it is now built. Leave the heading out entirely rather than leaving an empty
section.

In `README.md`, under the Mountains list, move Mount Interactive to the
climbed line at the bottom and add a short section after "Editing summaries"
documenting the modes and the keyboard map (the table from §3 of the design
note, plus `?mode=narrate`).

In `CLAUDE.md`, under Status, replace the "Focus mode" bullet with:

```markdown
- **Three modes** (session 12): `body.mode-explore|edit|narrate`, a header
  switch (`#mode-switch`), and `?mode=` in the URL — explore is the default and
  stays out of the URL. Edit un-hides only when the `/api/health` probe answers.
  Focus mode is gone. Keyboard: unshifted arrows move one card, shifted move one
  user/assistant message; `n`/`p` are shift-arrow aliases in narrate; `x`/`e`/`N`
  switch modes; Escape peels sidebar → selection → mode. In narrate,
  `.revealed` is a prefix of the cards and the newest one is the selection.
  `bin/check-modes` drives all of it with real keystrokes in headless Chrome.
```

Also update the `bin/check-anchors` paragraph to mention `bin/check-modes`
alongside it, and drop the "Focus mode" mention from the last bullet list.

Write `notes/2026-07-27-session-12-mount-interactive.md` covering what shipped,
why the sidebar became sticky state, and the harness trick
(`--allow-file-access-from-files` + iframe, because headless Chrome can dump a
DOM but can't type).

- [ ] **Step 8: Commit**

```sh
git add assets/ bin/check-modes README.md CLAUDE.md TODO.md notes/ out/
git commit -m "Narrate mode: reveal the conversation a beat at a time

A beat is a run of cards ending at the next user/assistant message. n advances
one, p backs up one, plain arrows move a single card; the newest revealed card
is the selection, so the URL fragment always says where you are and a reload
resumes. Entering narrate starts from the fragment if there is one, else on an
empty stage -- a default auto-selection does not count as choosing a card.

Reveal is a class toggle, so nothing leaves the DOM and leaving narrate brings
it all back.

Mount Interactive is climbed.

- claude"
```

---

## Self-review notes

Checked against the design note:

- §1 modes, URL param, edit gating, focus deleted, ✎ un-gated → Task 2.
- §2 sidebar sticky, click-to-toggle, Escape layering, reopen deleted → Task 1.
- §3 full keyboard table → Task 1 (Escape) + Task 3 (explore/edit) + Task 4
  (narrate's arrows and `n`/`p`).
- §4 beats, class-toggle reveal, selection follows newest, fragment-or-empty
  entry, sidebar collapse on advance, timing/scroll, exit → Task 4.
- §5 staging, prototype parity, `bin/check-modes` assertions → each task's
  file list and check step.

**One deliberate deviation from the design note:** §3's table says shift-arrow
scrolls the target into view and is silent about plain arrows. `moveSelection`
scrolls on both, with `block: 'nearest'` — a selection you can't see is a bug
either way, and `nearest` does nothing when the card is already on screen.

**Edge cases from the design that the code covers:** `revealTo` clamps to
`[0, CARDS.length]`, so `→` at the end and `←` at the start are no-ops;
`beatBackTo` starts at `from - 2` so it always un-reveals at least one card;
hidden events never render a card, so they can't participate in a beat.
