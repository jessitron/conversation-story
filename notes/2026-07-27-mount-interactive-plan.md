# Mount Interactive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the story page into something you drive — three modes
(explore / edit / narrate), a keyboard map, and a narrate mode that reveals the
conversation one beat at a time.

**Architecture:** All behavior lives in `assets/story.js` as four small modules
(sidebar state, mode, keyboard, narrate) that talk to the DOM through a body
class and a `.revealed` card class. Nothing is added to the schema and no Ruby
logic changes — `page.html.erb` swaps one header widget and drops one button.
Verification is a new `bin/check-modes`, which drives a real headless Chrome
over the DevTools Protocol with **ferrum** and types at the page.

**Tech Stack:** Vanilla ES2015+ browser JS (no build step, no framework), plain
CSS, ERB templates, Ruby 4 + ferrum for the check script, headless Google Chrome.

**Spec:** `notes/2026-07-27-mount-interactive-design.md`. Read it first.

## Global Constraints

- **Ruby 4.** `ferrum ~> 0.17` is already added to the `Gemfile`'s `:test`
  group and installed. `bin/check-modes` runs under **`bundle exec`**. It drives
  `file://` URLs — no server, no `bin/serve`, no `webrick`.
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
- After every task: `rake build && rake test && bin/check-anchors && bundle exec
  bin/check-modes` must pass.

## Verified facts about driving the page with ferrum

These were all established by experiment before this plan was written. Do not
re-derive them, and do not "simplify" past them — each one is a trap that
already cost a debugging round:

1. **`at_css("#episode-8-before:4")` throws `Ferrum::JavaScriptError`.** The
   colon in a card id is a CSS pseudo-class introducer. In the check script,
   reach cards by **index** into `browser.css(".card")`, or by
   `document.getElementById(...)` inside an `evaluate`. Never build a `#id`
   selector — the same rule the page's own JS follows.
2. **A real click on a card far down the page silently misses.** Ferrum scrolls
   the node barely into view and the computed click point lands outside the
   viewport; the click reports success and nothing happens. Always
   `scrollIntoView({block:'center'})` via `evaluate` first, then click. The
   `Story#click` helper below does this — use it rather than clicking nodes
   directly.
3. **`keyboard.type([:Shift, "n"])` produces `e.key === "n"` with
   `shiftKey: true`** — *not* `"N"` the way a real keyboard does. Use
   `keyboard.type("N")` to get `e.key === "N"`. Because both shapes are
   reachable, the page's handler normalizes case (see Task 3).
   `type(:Escape)` → `"Escape"`, `type(:Right)` → `"ArrowRight"`,
   `type([:Shift, :Right])` → `"ArrowRight"` with `shiftKey` — all correct.
4. **The page always loads with a card already selected.** `syncFromHash` falls
   back to `DEFAULT_CARD` (the first `.k-assistant`, which is
   `episode-8-before:10`). No scenario may assume "nothing is active" on load,
   and clicking that particular card exercises the *active-card* branch, not
   the fresh-selection branch.
5. **`history.replaceState` works on `file://`** in this Chrome, so URL
   assertions (`location.hash`, `location.search`) are valid without a server.
6. **Focus is real**: focusing a textarea via `evaluate` makes `e.target` the
   textarea for subsequently typed keys. The "typing must not reach the page"
   test is honest, not a synthetic stand-in.

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
- Produces, in `bin/check-modes`, a `scenario(name, query:, hash:) { |s| ... }`
  registry and a `Story` helper class that later tasks write scenarios against.
  Its full API — every method later tasks call:
  - reading: `card_ids` → `Array[String]`, `revealed_ids` → `Array[String]`,
    `shown_ids` → `Array[String]` (cards actually laid out, i.e.
    `offsetParent != null`), `active_id` → `String|nil`, `mode` → `String|nil`,
    `collapsed?` → `Boolean`, `search` → `String`, `hash` → `String`,
    `message?(id)` → `Boolean`, `exists?(dom_id)` → `Boolean`,
    `hidden_attr?(css)` → `Boolean`, `scroll_y` → `Integer`
  - acting: `key(*keys)` (ferrum key syntax), `click(index)`,
    `click_id(id)`, `click_mode(name)`, `focus_new_textarea`, `set_hash(id)`,
    and `js(expr)` for a one-off assertion with no helper
  - waiting: `settle(ms = 150)`, `wait_stable` (polls until `revealed_ids`
    stops growing — for narrate's animated beats)
- Produces, in `assets/story.js`: `collapseSidebar()`, `openSidebar()`, and a
  `selectCard(card)` that no longer touches `sidebar-collapsed`.

- [ ] **Step 1: Write the harness**

Create `bin/check-modes` and `chmod +x` it. This is the whole file; later tasks
only add `scenario` blocks to it.

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Drive a built story page with real keystrokes and check what it does
# (Mount Interactive: modes, keyboard navigation, narrate).
#
#   bundle exec bin/check-modes [example-name]
#
# Uses ferrum to talk to the installed Chrome over the DevTools Protocol, so
# these are REAL key and mouse events: focus decides what e.target is, and the
# page's own preventDefault actually applies. Runs against file:// — no server.
#
# THREE TRAPS, each of which has already bitten (see the plan note):
#   * Card ids contain a colon, which CSS reads as a pseudo-class. `at_css("#" +
#     id)` THROWS. Reach cards by index, or getElementById inside evaluate.
#   * A real click on a card far down the page silently misses unless you
#     scrollIntoView({block:'center'}) first. Story#click does that for you.
#   * The page always loads with a card already selected (DEFAULT_CARD, the
#     first assistant message). "Nothing is active" is never the start state.

require "ferrum"

REPO   = File.expand_path("..", __dir__)
STORY  = ARGV[0] || "episode-8-before"
PAGE   = File.join(REPO, "out", STORY, "index.html")
CHROME = ENV.fetch("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

abort "no such page: #{PAGE} (run 'rake build')" unless File.exist?(PAGE)
abort "Chrome not found at #{CHROME} (set CHROME=...)" unless File.exist?(CHROME)

SCENARIOS = []

# Register a scenario. Each one gets a freshly loaded page, so no scenario can
# inherit another's state. `query` is appended before the fragment ("?mode=..."),
# `hash` after it ("#<ref>"). The block gets a Story and returns nil to pass or
# a string saying what went wrong.
def scenario(name, query: "", hash: "", &block)
  SCENARIOS << { name: name, query: query, hash: hash, run: block }
end

# The vocabulary the scenarios speak. Everything goes through `evaluate` and
# returns plain Ruby data rather than Ferrum nodes, because node handles go
# stale across reloads and ids can't be used as selectors here anyway.
class Story
  def initialize(browser) = @b = browser

  def load(query, hash)
    @b.goto("file://#{PAGE}#{query}#{hash}")
    settle(250)   # let story.js run its initial paint
    self
  end

  # ---- reading ----
  def js(expr) = @b.evaluate(expr)
  def card_ids     = js("Array.from(document.querySelectorAll('.card')).map(c => c.id)")
  def revealed_ids = js("Array.from(document.querySelectorAll('.card.revealed')).map(c => c.id)")
  def shown_ids    = js("Array.from(document.querySelectorAll('.card')).filter(c => c.offsetParent !== null).map(c => c.id)")
  def active_id    = js("(document.querySelector('.card.active') || {}).id || null")
  def mode         = js("(document.body.className.match(/\\bmode-(\\w+)\\b/) || [])[1] || null")
  def collapsed?   = js("document.body.classList.contains('sidebar-collapsed')")
  def search       = js("location.search")
  def hash         = js("location.hash")
  def scroll_y     = js("Math.round(window.scrollY)")
  def exists?(dom_id) = js("!!document.getElementById(#{dom_id.inspect})")
  def hidden_attr?(css) = js("(document.querySelector(#{css.inspect}) || {}).hidden === true")

  def message?(id)
    js("(() => { const c = document.getElementById(#{id.inspect}); " \
       "return !!c && (c.classList.contains('k-user') || c.classList.contains('k-assistant')); })()")
  end

  # ---- acting ----
  def key(*keys)
    @b.keyboard.type(*keys)
    settle
    self
  end

  # Real mouse click on the nth card. The scroll is not optional — see the
  # trap list at the top.
  def click(index)
    js("document.querySelectorAll('.card')[#{index}].scrollIntoView({block:'center'})")
    settle(80)
    @b.css(".card")[index].click
    settle
    self
  end

  def click_id(id) = click(card_ids.index(id) || raise("no card #{id}"))

  # The header's mode buttons. Plain class/attribute selectors, so at_css is
  # safe here — it's only card ids that carry a colon.
  def click_mode(name)
    node = @b.at_css(%(#mode-switch [data-mode="#{name}"])) or raise("no #{name} button")
    node.click
    settle
    self
  end

  def set_hash(id)
    js("location.hash = #{("#" + id).inspect}")
    settle
    self
  end

  # A stand-in for the summary editor's textarea (which needs a server). Focus
  # is real, so keys typed after this genuinely land on the textarea.
  def focus_new_textarea
    js("(() => { const t = document.createElement('textarea'); t.id = 'probe-input'; " \
       "document.body.appendChild(t); t.focus(); })()")
    settle
    self
  end

  # ---- waiting ----
  def settle(ms = 150)
    sleep(ms / 1000.0)
    self
  end

  # Narrate reveals a beat's cards ~80ms apart, so "the beat is done" is "the
  # revealed count stopped growing". Beats the alternative of a long fixed sleep.
  def wait_stable(timeout: 5)
    deadline = Time.now + timeout
    last = -1
    while Time.now < deadline
      now = revealed_ids.size
      return self if now == last && now.positive?
      last = now
      sleep 0.12
    end
    self
  end
end

# ---------------------------------------------------------------- scenarios

scenario "clicking an unselected card selects it and opens the sidebar" do |s|
  target = s.card_ids.find { |id| id != s.active_id }
  s.click_id(target)
  next "expected #{target} active, got #{s.active_id.inspect}" unless s.active_id == target
  next "sidebar is collapsed" if s.collapsed?
  next "URL fragment is #{s.hash.inspect}" unless s.hash == "##{target}"
  nil
end

scenario "clicking the active card collapses the sidebar; clicking again reopens" do |s|
  target = s.card_ids.find { |id| id != s.active_id }
  s.click_id(target)
  s.click_id(target)
  next "did not collapse" unless s.collapsed?
  next "lost the selection on collapse (active=#{s.active_id.inspect})" unless s.active_id == target
  s.click_id(target)
  next "did not reopen" if s.collapsed?
  nil
end

scenario "Escape collapses the sidebar, then clears the selection" do |s|
  target = s.card_ids.find { |id| id != s.active_id }
  s.click_id(target)
  s.key(:Escape)
  next "first Escape did not collapse" unless s.collapsed?
  next "first Escape also cleared the selection" unless s.active_id == target
  s.key(:Escape)
  next "second Escape did not clear the selection (active=#{s.active_id.inspect})" if s.active_id
  nil
end

scenario "the Details reopen tab is gone" do |s|
  s.exists?("reopen") ? "reopen button still in the DOM" : nil
end

# ---------------------------------------------------------------- runner

browser = Ferrum::Browser.new(headless: true, window_size: [1400, 900], browser_path: CHROME)
failures = 0

begin
  SCENARIOS.each do |sc|
    story = Story.new(browser).load(sc[:query], sc[:hash])
    failure =
      begin
        sc[:run].call(story)
      rescue StandardError => e
        "raised #{e.class}: #{e.message.lines.first.to_s.strip}"
      end

    if failure
      failures += 1
      puts "FAIL  #{sc[:name]} — #{failure}"
    else
      puts "OK    #{sc[:name]}"
    end
  end
ensure
  browser.quit
end

puts "#{SCENARIOS.size - failures}/#{SCENARIOS.size} scenarios passed"
exit(failures.zero? ? 0 : 1)
```

- [ ] **Step 2: Run it to watch the sidebar scenarios fail**

```sh
rake build && bundle exec bin/check-modes
```

Expected: four scenarios run. The first ("clicking an unselected card…") should
already PASS against today's code. The other three FAIL: "did not collapse"
(the click handler currently early-returns on the active card), "first Escape
did not collapse" (no keyboard handler exists yet), and "reopen button still in
the DOM".

If instead you get a Ferrum error or zero scenarios, fix the harness before
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

bin/check-modes is new: ferrum drives the installed Chrome over the DevTools
Protocol, so the tests use real key and mouse events against the built page --
focus decides what e.target is, which is the only honest way to check that
typing in the summary box does not trigger a hotkey.

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

Append these below Task 1's scenarios, above the `# ---- runner` comment:

```ruby
scenario "the page starts in explore mode" do |s|
  s.mode == "explore" ? nil : "mode is #{s.mode.inspect}"
end

# NOTE: this clicks the switch rather than pressing a hotkey. The hotkeys don't
# exist until Task 3 — a scenario for them lives there.
scenario "the switch enters narrate and writes ?mode=; explore clears it" do |s|
  s.click_mode("narrate")
  next "did not enter narrate (mode=#{s.mode.inspect})" unless s.mode == "narrate"
  next "URL is #{s.search.inspect}" unless s.search.include?("mode=narrate")
  next "aria-pressed not moved" unless s.js(
    %(document.querySelector('#mode-switch [data-mode="narrate"]').getAttribute('aria-pressed') === 'true')
  )
  s.click_mode("explore")
  next "did not return to explore (mode=#{s.mode.inspect})" unless s.mode == "explore"
  next "explore left mode= in the URL (#{s.search.inspect})" if s.search.include?("mode=")
  nil
end

scenario "?mode=narrate loads straight into narrate", query: "?mode=narrate" do |s|
  s.mode == "narrate" ? nil : "mode is #{s.mode.inspect}"
end

scenario "with no server, the Edit button is hidden and ?mode=edit degrades",
         query: "?mode=edit" do |s|
  s.settle(300)   # let the /api/health probe fail
  next "did not degrade to explore (mode=#{s.mode.inspect})" unless s.mode == "explore"
  next "no edit button in the switch" unless s.js("!!document.querySelector('#mode-switch [data-mode=\"edit\"]')")
  next "edit button is visible with no server" unless s.hidden_attr?('#mode-switch [data-mode="edit"]')
  nil
end

scenario "focus mode is gone" do |s|
  s.exists?("focus-toggle") ? "focus-toggle still in the DOM" : nil
end
```

- [ ] **Step 2: Run to verify they fail**

```sh
rake build && bundle exec bin/check-modes
```

Expected: the five new scenarios FAIL — `mode is nil` (no `body.mode-*` class
yet), no `#mode-switch` element, and `focus-toggle still in the DOM`. Task 1's
four still pass.
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

```ruby
scenario "right arrow moves the selection one card, left arrow moves it back" do |s|
  ids = s.card_ids
  start = ids[3]
  s.click_id(start)
  s.key(:Right)
  next "right did not land on #{ids[4]} (got #{s.active_id.inspect})" unless s.active_id == ids[4]
  s.key(:Left)
  next "left did not return to #{start} (got #{s.active_id.inspect})" unless s.active_id == start
  nil
end

scenario "shift+right jumps to the next user/assistant card" do |s|
  ids = s.card_ids
  s.click_id(ids[0])
  s.key([:Shift, :Right])
  landed = s.active_id
  next "landed on nothing" unless landed
  next "#{landed} is not a message card" unless s.message?(landed)
  expected = ids.drop(1).find { |id| s.message?(id) }
  next "skipped past #{expected} to #{landed}" unless landed == expected
  nil
end

scenario "arrow navigation leaves a collapsed sidebar collapsed" do |s|
  ids = s.card_ids
  s.click_id(ids[2])
  s.key(:Escape)          # collapse, keeping the selection
  s.key(:Right)
  next "arrow popped the sidebar open" unless s.collapsed?
  next "arrow did not move the selection (active=#{s.active_id.inspect})" unless s.active_id == ids[3]
  nil
end

scenario "keys typed into a focused text box do not reach the page" do |s|
  before_mode = s.mode
  before_active = s.active_id
  s.focus_new_textarea
  s.key("N")
  s.key(:Right)
  next "typing changed the mode to #{s.mode.inspect}" unless s.mode == before_mode
  next "typing moved the selection to #{s.active_id.inspect}" unless s.active_id == before_active
  nil
end

scenario "the x / e / N hotkeys switch modes" do |s|
  s.key("N")   # type("N") gives e.key === 'N'; [:Shift,'n'] would give 'n' + shiftKey
  next "N did not enter narrate (mode=#{s.mode.inspect})" unless s.mode == "narrate"
  s.key("x")
  next "x did not return to explore (mode=#{s.mode.inspect})" unless s.mode == "explore"
  s.key("n")   # lowercase is the forgiving alias from explore
  next "n did not enter narrate (mode=#{s.mode.inspect})" unless s.mode == "narrate"
  s.key("x")
  s.key("e")   # no server here, so edit must stay unavailable
  next "e entered edit mode with no server" if s.mode == "edit"
  nil
end

scenario "shift+right scrolls the target into view" do |s|
  s.click_id(s.card_ids[0])
  before = s.scroll_y
  8.times { s.key([:Shift, :Right]) }
  next "page never scrolled (still at #{before})" unless s.scroll_y > before
  nil
end
```

- [ ] **Step 2: Run to verify they fail**

```sh
rake build && bundle exec bin/check-modes
```

Expected: the arrow scenarios FAIL ("right did not land on …") and the scroll
scenario FAILs; the previous nine pass (Task 3 adds six). "keys typed into a focused text box"
may already pass — Task 1's `TYPING` guard covers it — which is fine; it is
here so Task 3 cannot regress it.
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

  /* Letter keys are matched case-insensitively. Shift+N arrives as 'N' from a
     real keyboard but as 'n' + shiftKey from CDP-synthesized input, and caps
     lock is a third way to get the same intent — folding case means one case
     label covers all of them. Named keys ('ArrowRight', 'Escape') are longer
     than one character and pass through untouched. */
  const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
  const act = fn => { e.preventDefault(); fn(); };

  switch (key) {
    case 'x': return act(() => setMode('explore'));
    case 'e': return act(() => setMode('edit'));
    case 'Escape': return act(escapeKey);
  }

  if (mode === 'narrate') return;   // Task 4 owns narrate's arrows

  switch (key) {
    /* 'n' and 'N' are the same key here: from explore or edit, both mean
       "start narrating". They only diverge inside narrate, where Task 4 gives
       'n' the beat-forward job. */
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

Expected: all fifteen scenarios OK.

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

```ruby
scenario "narrate starts on an empty stage", query: "?mode=narrate" do |s|
  next "#{s.revealed_ids.size} cards revealed on entry" unless s.revealed_ids.empty?
  next "#{s.shown_ids.size} cards still laid out" unless s.shown_ids.empty?
  next "sidebar is open" unless s.collapsed?
  nil
end

scenario "n reveals exactly through the next message; p puts it back",
         query: "?mode=narrate" do |s|
  s.key("n").wait_stable
  shown = s.revealed_ids
  next "n revealed nothing" if shown.empty?
  next "beat did not end on a message (#{shown.last})" unless s.message?(shown.last)
  early = shown[0..-2].select { |id| s.message?(id) }
  next "beat ran past a message: #{early.inspect}" unless early.empty?
  next "did not select the landing message (active=#{s.active_id.inspect})" unless s.active_id == shown.last

  s.key("p").settle(300)
  after = s.revealed_ids.size
  next "p did not un-reveal (#{shown.size} -> #{after})" unless after < shown.size
  nil
end

scenario "right arrow in narrate reveals one card at a time", query: "?mode=narrate" do |s|
  ids = s.card_ids
  s.key(:Right).settle(300)
  s.key(:Right).settle(300)
  next "expected 2 revealed, got #{s.revealed_ids.size}" unless s.revealed_ids.size == 2
  next "newest revealed card is not selected (active=#{s.active_id.inspect})" unless s.active_id == ids[1]
  s.key(:Left).settle(300)
  next "left did not un-reveal one (#{s.revealed_ids.size} revealed)" unless s.revealed_ids.size == 1
  nil
end

scenario "narrate entered on a deep link starts from that card" do |s|
  target = s.card_ids[5]
  s.set_hash(target)
  s.key("N").settle(300)
  next "expected 6 revealed, got #{s.revealed_ids.size}" unless s.revealed_ids.size == 6
  next "last revealed is #{s.revealed_ids.last}, not #{target}" unless s.revealed_ids.last == target
  next "did not select the deep-linked card (active=#{s.active_id.inspect})" unless s.active_id == target
  nil
end

scenario "advancing a beat closes a sidebar opened by clicking", query: "?mode=narrate" do |s|
  s.key(:Right).settle(300)
  s.click_id(s.revealed_ids.first)
  next "click did not open the sidebar" if s.collapsed?
  s.key("n").wait_stable
  next "n left the sidebar open" unless s.collapsed?
  nil
end

scenario "leaving narrate shows everything again", query: "?mode=narrate" do |s|
  s.key(:Right).settle(300)
  s.key(:Escape)   # already collapsed on entry, so this exits the mode
  next "Escape did not exit narrate (mode=#{s.mode.inspect})" unless s.mode == "explore"
  missing = s.card_ids.size - s.shown_ids.size
  next "#{missing} cards still hidden in explore" unless missing.zero?
  nil
end
```

- [ ] **Step 2: Run to verify they fail**

```sh
rake build && bundle exec bin/check-modes
```

Expected: the six new scenarios FAIL; the previous fifteen pass. Nothing sets
`.revealed` yet and no CSS hides cards, so expect "narrate starts on an empty
stage" to fail with "109 cards still laid out", and the rest with "n revealed
nothing" and friends.
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
    switch (key) {   // `key` is the case-folded e.key from Task 3
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

Expected: all twenty-one scenarios OK, and both other check scripts green.
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
why the sidebar became sticky state, and what the ferrum harness taught us —
including the four traps in the "Verified facts" section of this plan (colon
ids break `at_css`, far clicks miss without an explicit center-scroll,
`[:Shift,'n']` is not `"N"`, and the page always loads with a card selected).
Also note in `CLAUDE.md` that `ferrum` is why there is now a `:test` group.

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

**Two deliberate deviations from the design note:**

1. §3's table says shift-arrow scrolls the target into view and is silent about
   plain arrows. `moveSelection` scrolls on both, with `block: 'nearest'` — a
   selection you can't see is a bug either way, and `nearest` does nothing when
   the card is already on screen.
2. §3 distinguishes `n` from `N`. The handler folds letter case instead, so they
   are the same key. This costs nothing: the design already made lowercase `n`
   a forgiving alias for entering narrate, so the two only ever differed inside
   narrate, where `N` would have meant "enter the mode you are already in". It
   buys correctness under caps lock and under CDP-synthesized input, which
   delivers shift+n as `'n'` rather than `'N'`.

**Edge cases from the design that the code covers:** `revealTo` clamps to
`[0, CARDS.length]`, so `→` at the end and `←` at the start are no-ops;
`beatBackTo` starts at `from - 2` so it always un-reveals at least one card;
hidden events never render a card, so they can't participate in a beat.
