/* ============================================================
   Conversation Story — shared page script (interactivity only).
   Authored here (source of truth). The build copies this to
   out/assets/story.js; both design-prototype.html and every generated page
   link it. No event data lives here — it reads everything from the DOM.
   ============================================================ */

/* ------------------------------------------------------------------
   The cards and their detail payloads are static HTML in the page (each card
   owns a <template class="detail">); this script just wires up selection,
   collapse/reopen, and drag-to-resize.

   Selection is driven by the URL fragment, so every event is deep-linkable and
   shareable. A generated card's id is the event's ref — `<example>:<line>`, e.g.
   #episode-8-before:174 — so a ref pastes straight into the URL. NOTE the colon:
   resolve fragments with getElementById (below), never querySelector('#'+id),
   which would read the colon as a pseudo-class. Cards are <a href="#..."> anchors,
   which also makes them keyboard-focusable and Enter-activatable for free.
------------------------------------------------------------------ */
const body    = document.body;
const sidebar = document.getElementById('sidebar');
const dKind   = document.getElementById('d-kind');
const dTime   = document.getElementById('d-time');
const dBody   = document.getElementById('d-body');
const cards   = document.querySelectorAll('.card');
const DEFAULT_CARD = document.querySelector('.card.k-assistant');  // so the page is never empty

/* ---- context map ("where are we", TODO.md: context-map-sidebar) ----
   A non-scrolling vertical bar sized from the data-ctx-before/-mine the
   renderer stamped on every main-thread card (see ctx_attr in renderer.rb).
   v1: main conversation only. */
const contextMap = document.getElementById('context-map');
const cmValue    = document.getElementById('cm-value');
const cmBar      = document.getElementById('cm-bar');
const cmPrior    = document.getElementById('cm-prior');
const cmCurrent  = document.getElementById('cm-current');
const cmFuture   = document.getElementById('cm-future');
const CTX_TOTAL  = parseInt(contextMap.dataset.ctxTotal || '0', 10);

/* The .subactions block a card's OWN subagent-economy numbers (data-sub-*)
   are scoped to: that block itself if `card` IS a subagent call (its
   subactions is the very next sibling — see renderer.rb's cards_for), else
   the nearest enclosing one (closest() finds the INNERMOST wrapper even for
   a subagent-in-a-subagent, since an inner .subactions is a DOM descendant
   of its outer one). */
function subactionsFor(card) {
  if (card.classList.contains('k-subagent')) {
    const wrap = card.nextElementSibling;
    return (wrap && wrap.classList.contains('subactions')) ? wrap : null;
  }
  return card.closest('.subactions');
}

/* A card inside a subagent's .subactions block carries no ctx-* of its own
   (that conversation is a separate token economy — see renderer.rb's
   ctx_attr) — walk up to the (possibly deeply nested) `subagent` call card
   that owns the block it's in, which does. From there, prefer that
   subagent's RESULT card over the call card itself: while the subagent is
   working the main conversation hasn't resumed, so "where are we" on the
   main bar means as of the point control comes back, not the moment it was
   handed off (also covers selecting the call card directly). */
function contextOwnerFor(card) {
  let c = card;
  while (c && c.dataset.ctxBefore === undefined) {
    const wrap = c.closest('.subactions');
    c = wrap ? wrap.previousElementSibling : null;
  }
  if (c && c.classList.contains('k-subagent')) {
    const wrap = c.nextElementSibling;
    const result = (wrap && wrap.classList.contains('subactions')) ? wrap.nextElementSibling : null;
    if (result && result.dataset.ctxBefore !== undefined) return result;
  }
  return c;
}

/* 24456 -> "24.5k", matching Renderer#token_label. */
function fmtTokens(n) {
  if (n < 1000) return String(n);
  if (n < 1_000_000) return (n / 1000).toFixed(1) + 'k';
  return (n / 1_000_000).toFixed(2) + 'M';
}

function updateContextMap(card) {
  const owner = contextOwnerFor(card);
  const before = owner ? parseInt(owner.dataset.ctxBefore, 10) : 0;
  const mine   = owner ? parseInt(owner.dataset.ctxMine, 10) : 0;
  const future = Math.max(0, CTX_TOTAL - before - mine);
  cmPrior.style.flexGrow = before;
  cmCurrent.style.flexGrow = mine;
  cmFuture.style.flexGrow = future;
  contextMap.style.setProperty('--kind', getComputedStyle(card).getPropertyValue('--kind'));
  cmValue.textContent = fmtTokens(before + mine) + ' / ' + fmtTokens(CTX_TOTAL);
}

function clearContextMap() {
  cmPrior.style.flexGrow = 0;
  cmCurrent.style.flexGrow = 0;
  cmFuture.style.flexGrow = CTX_TOTAL;
  contextMap.style.setProperty('--kind', 'var(--line-strong)');
  cmValue.textContent = '';
}

/* ---- subagent bar ("Subagent bars", TODO.md: context-map-sidebar) ----
   A second bar next to the main one, shown only while the selection is a
   subagent card or something inside one — v1 shows the DIRECTLY enclosing
   subagent only (a header toggle to line up every subagent's bar at once is
   still open). Same scale as the main bar: rather than flex-grow (relative
   within one container, not comparable across two independent ones), its
   segments get explicit pixel heights computed from the main bar's actual
   rendered height, so a token is the same number of pixels in both. */
const contextMapSub = document.getElementById('context-map-sub');
const cmValueSub    = document.getElementById('cm-value-sub');
const cmSpacerSub   = document.getElementById('cm-spacer-sub');
const cmPriorSub    = document.getElementById('cm-prior-sub');
const cmCurrentSub  = document.getElementById('cm-current-sub');
const cmFutureSub   = document.getElementById('cm-future-sub');

function updateSubagentMap(card) {
  const wrap = subactionsFor(card);
  if (!wrap) { hideSubagentMap(); return; }

  const total = parseInt(wrap.dataset.subCtxTotal || '0', 10);
  const callCard   = wrap.previousElementSibling;
  const isCallCard = card === callCard;
  const before = isCallCard ? 0 : parseInt(card.dataset.subBefore || '0', 10);
  const mine   = isCallCard ? 0 : parseInt(card.dataset.subMine || '0', 10);
  const future = Math.max(0, total - before - mine);

  const H = cmBar.getBoundingClientRect().height || 0;
  // Same scale as the main bar, UNLESS this subagent's own peak context is
  // bigger than the whole conversation's — then that scale would run off
  // the page, so fall back to the subagent's own full-height scale instead.
  const sameScale = CTX_TOTAL > 0 && total <= CTX_TOTAL;
  const pxPer = H / (sameScale ? CTX_TOTAL : (total || 1));

  let offsetPx = 0;
  if (sameScale) {
    const mainBefore = callCard ? parseInt(callCard.dataset.ctxBefore || '0', 10) : 0;
    const contentPx = (before + mine + future) * pxPer;
    const labelPx = cmValueSub.getBoundingClientRect().height || 0;
    // "starts at the height of the subagent invocation on the main bar,
    // unless that would push its summary off the bottom of the page, in
    // which case it moves up to fit"
    offsetPx = Math.max(0, Math.min(mainBefore * pxPer, H - contentPx - labelPx));
  }

  cmSpacerSub.style.height  = offsetPx + 'px';
  cmPriorSub.style.height   = (before * pxPer) + 'px';
  cmCurrentSub.style.height = Math.max(mine * pxPer, mine > 0 ? 4 : 0) + 'px';
  cmFutureSub.style.height  = (future * pxPer) + 'px';

  contextMapSub.style.setProperty('--kind', getComputedStyle(card).getPropertyValue('--kind'));
  cmValueSub.textContent = fmtTokens(before + mine) + ' / ' + fmtTokens(total);
  contextMapSub.classList.add('visible');
}

function hideSubagentMap() {
  contextMapSub.classList.remove('visible');
  cmValueSub.textContent = '';
}

/* the empty-state markup that ships in the sidebar; restored on clear */
const EMPTY_HTML = dBody.innerHTML;

/* Write path+query+fragment without scrolling or firing hashchange. Wrapped
   because some browsers block history writes on file:// URLs — selection and
   mode must still work when the URL can't be updated. */
function setUrl(url) {
  try { history.replaceState(null, '', url); } catch (_) { /* file:// */ }
}
function setFragment(frag) { setUrl(frag); }

/* The sidebar's open/collapsed state is Jess's, not selection's. Only an
   explicit open (clicking a card) or an explicit collapse (clicking the active
   card, Escape, ×, or advancing a narration beat) moves it. */
function collapseSidebar() { body.classList.add('sidebar-collapsed'); }
function openSidebar()     { body.classList.remove('sidebar-collapsed'); }

/* show a card's detail in the sidebar (pure UI — does not touch the URL).
   Also moves real DOM focus to the card: browsers auto-focus whatever element
   matches the URL fragment on load, and that focus (and its :focus-visible
   outline) otherwise just sits there forever after — completely decoupled
   from .active — so narrating past it left a stray outline on the start card
   while the real (correctly-moving) selection border was elsewhere. preventScroll
   because every caller already handles its own scrolling (or deliberately
   doesn't, e.g. the reveal flurry). */
function selectCard(card) {
  cards.forEach(c => c.classList.remove('active'));
  card.classList.add('active');
  card.focus({ preventScroll: true });

  dKind.textContent = card.querySelector('.gutter .kind').textContent;
  /* The beat cue rides along in every mode — it's for Jess's eye, on the
     published site too, like the ✎ marker. Read-only; the checkbox that CHANGES
     it is edit-mode only (see showBeatEditor). */
  dTime.textContent = card.dataset.time + ' UTC' + (card.dataset.beat === 'true' ? ' · 🥁' : '');
  sidebar.style.setProperty('--kind', getComputedStyle(card).getPropertyValue('--kind'));

  dBody.replaceChildren(card.querySelector('template.detail').content.cloneNode(true));
  dBody.scrollTop = 0;
  updateRelated(card);
  updateContextMap(card);
  updateSubagentMap(card);
  showSummary(card);
  showBeatEditor(card);      // prepended after showSummary, so it sits above it
}

/* The summary at the top of the detail pane. Edit mode gets the editable
   version (a textarea, only when the authoring server answered); every other
   mode gets the same line as plain, selectable prose — the card face has it
   too, but a card is an <a>, so dragging across it starts a link drag instead
   of a text selection. This is where you copy a summary from. */
function showSummary(card) {
  if (mode === 'edit' && editingAvailable) { showSummaryEditor(card); return; }
  const text = card.querySelector('.summary').textContent.trim();
  if (!text) return;

  const sec = document.createElement('div');
  sec.className = 'd-section summary-view';
  sec.innerHTML =
    '<h4 class="deco">Summary' +
      '<button type="button" class="copy-ref" title="Copy summary to clipboard">' +
        '<span class="copy-hint">copy</span></button>' +
    '</h4>' +
    '<p class="d-text"></p>';
  sec.querySelector('.copy-ref').dataset.copy = text;   // never through innerHTML
  sec.querySelector('.d-text').textContent = text;
  dBody.prepend(sec);
}

/* ---- causal-chain highlight ----
   The parser links causally-related events (a tool call and its result, a
   queue enqueue and its dequeue, the tool call that started a background task
   and the notification it eventually delivers) with a shared token in the
   card's data-link attribute. Selecting a card lights up every OTHER card
   that shares one of its tokens, so the connection is visible without
   hunting through the log for a matching id. */
function linkTokens(card) {
  return (card.dataset.link || '').split(' ').filter(Boolean);
}
function updateRelated(activeCard) {
  const tokens = new Set(linkTokens(activeCard));
  cards.forEach(c => {
    c.classList.toggle('related', tokens.size > 0 && c !== activeCard &&
      linkTokens(c).some(t => tokens.has(t)));
  });
}

/* deselect any card but keep the sidebar open and empty */
function clearSelection() {
  cards.forEach(c => c.classList.remove('active', 'related'));
  dKind.textContent = 'Detail';
  dTime.textContent = '';
  sidebar.style.setProperty('--kind', 'var(--line-strong)');
  dBody.innerHTML = EMPTY_HTML;
  clearContextMap();
  hideSubagentMap();
}

/* Expand every collapsed subagent block this card is buried in (see the
   .subactions section below for what those are). Declared here because
   syncFromHash runs on load, before the narrate/keyboard section. */
function revealAncestors(card) {
  for (let w = card.closest('.subactions'); w; w = w.parentElement.closest('.subactions')) {
    const owner = w.previousElementSibling;
    if (owner) owner.classList.remove('collapsed');
  }
}

/* URL fragment -> selection. Unknown/empty fragment falls back to the default
   card so the page is never empty. Used on load and on hashchange; scrolls the
   target into view only when arriving via a real fragment (deep link). */
function syncFromHash() {
  const id = decodeURIComponent(location.hash.slice(1));
  const card = id ? document.getElementById(id) : null;
  const target = (card && card.classList.contains('card')) ? card : DEFAULT_CARD;
  /* A subaction's ref is a linkable ref like any other, so a deep link into a
     subagent's story opens the blocks it needs to open rather than resolving to
     a card nobody can see. */
  revealAncestors(target);
  selectCard(target);
  if (location.hash) target.scrollIntoView({ block: 'center' });
}

/* one delegated listener on the container: a click anywhere in a card selects
   it and writes its id to the URL (shareable), WITHOUT the native jump-to-anchor
   scroll — the detail shows in the sticky sidebar. Modified clicks (⌘/ctrl/…)
   fall through so "open link in new tab" still works. */
document.getElementById('cards').addEventListener('click', e => {
  if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
  const card = e.target.closest('.card');
  if (!card) return;
  e.preventDefault();
  /* The caret lives INSIDE the subagent card (it's the gutter's own affordance),
     so it has to be checked before the card's own select behavior — clicking it
     expands the subagent's story rather than selecting the card. */
  if (e.target.closest('.caret')) { toggleSubactions(card); return; }
  if (card.classList.contains('active')) {          // clicking the open card closes it
    body.classList.toggle('sidebar-collapsed');
    return;
  }
  setFragment('#' + card.id);
  selectCard(card);
  openSidebar();
});

/* deep links, back/forward, and hand-edited fragments */
window.addEventListener('hashchange', syncFromHash);

/* ---- click-to-copy the event id ----
   The copy chips live inside each card's <template> and are cloned into #d-body
   on select, so we delegate one listener on the stable #d-body container.
   navigator.clipboard needs a secure context (works on localhost/https); the
   textarea + execCommand path is the file:// fallback. */
function copyText(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    return navigator.clipboard.writeText(text);
  }
  return new Promise((resolve, reject) => {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy') ? resolve() : reject(); }
    catch (e) { reject(e); }
    finally { document.body.removeChild(ta); }
  });
}

function flashCopied(btn) {
  const hint = btn.querySelector('.copy-hint');
  const original = hint ? hint.textContent : null;
  btn.classList.add('copied');
  if (hint) hint.textContent = 'copied!';
  clearTimeout(btn._copyTimer);
  btn._copyTimer = setTimeout(() => {
    btn.classList.remove('copied');
    if (hint && original !== null) hint.textContent = original;
  }, 1200);
}

dBody.addEventListener('click', e => {
  const btn = e.target.closest('.copy-ref');
  if (!btn) return;
  copyText(btn.dataset.copy).then(() => flashCopied(btn)).catch(() => {});
});

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
/* Set the moment ANY mode change actually takes effect (hotkey, switch click,
   Escape, or the health-probe's own `?mode=edit` application below). The
   probe reads this before forcing edit mode, so pressing e.g. `n` while the
   probe is still in flight wins — the probe won't yank narrate back to edit
   out from under a mode Jess already chose. */
let modeChangedSinceLoad = false;

function setMode(next) {
  if (!MODES.includes(next)) return;
  if (next === 'edit' && !editingAvailable) return;
  if (next === mode) return;
  modeChangedSinceLoad = true;
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

/* Per-mode entry/exit work. Keeping it in one function means setMode never
   grows a chain of special cases. */
function onModeChange(prev, next) {
  if (next === 'narrate') enterNarrate();
  else if (prev === 'narrate') exitNarrate();
  const active = document.querySelector('.card.active');
  if (active) selectCard(active);   // rebuild the detail: the editor is edit-only
}

modeSwitch.addEventListener('click', e => {
  const btn = e.target.closest('button[data-mode]');
  if (btn) setMode(btn.dataset.mode);
});

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
/* Cards outside NAV() (inside a collapsed subagent) are left alone: the wrapper
   is display:none, so their `revealed` state can't show, and resyncReveal
   re-derives the count from whatever is navigable when the caret moves. */
function renderReveal() { NAV().forEach((c, i) => c.classList.toggle('revealed', i < revealed)); }

/* count of cards revealed after advancing one beat from `from` */
function beatForwardTo(from) {
  const nav = NAV();
  for (let i = from; i < nav.length; i++) if (isBeat(nav[i])) return i + 1;
  return nav.length;
}
/* count of cards revealed after backing up one beat from `from`; always
   un-reveals at least one card, so a half-finished beat backs up to the
   previous message rather than sitting still. */
function beatBackTo(from) {
  const nav = NAV();
  for (let i = from - 2; i >= 0; i--) if (isBeat(nav[i])) return i + 1;
  return 0;
}

/* Reveal (or hide) up to `target` cards. Going forward the new cards appear one
   after another so the flurry reads as a flurry; going back is immediate. */
function revealTo(target) {
  const nav = NAV();
  target = Math.min(nav.length, Math.max(0, target));
  clearPending();
  renderReveal();          // resync the DOM if a previous flurry was cut short
  const from = revealed;
  if (target === from) return;   // truly a no-op: don't touch the sidebar either
  collapseSidebar();       // the stage stays clear unless Jess clicks a card
  revealed = target;
  if (target < from) { renderReveal(); landOn(); return; }

  for (let i = from; i < target; i++) {
    const card = nav[i], last = i === target - 1;
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
  const card = NAV()[revealed - 1];
  setFragment('#' + card.id);
  selectCard(card);
  card.scrollIntoView({ block: 'center', behavior: 'smooth' });
}

/* Start from the URL fragment if there is one, else from an empty stage.
   syncFromHash auto-selects a default card when there's no fragment, so "a card
   is active" is NOT the same as "Jess chose a card" — only a real fragment
   counts as "start here". */
function enterNarrate() {
  const nav = NAV();
  const frag = decodeURIComponent(location.hash.slice(1));
  const at = frag ? nav.findIndex(c => c.id === frag) : -1;
  clearPending();
  revealed = at >= 0 ? at + 1 : 0;
  renderReveal();
  collapseSidebar();
  if (revealed) selectCard(nav[revealed - 1]); else clearSelection();
}

/* The nav list just changed length under `revealed` (a count into it), so
   re-derive the count from the last card that's actually revealed. Expanding a
   subagent Jess has already narrated past therefore reveals its subactions;
   expanding the one she's sitting on doesn't — they're the next beat. */
function resyncReveal() {
  const nav = NAV();
  revealed = 0;
  for (let i = nav.length - 1; i >= 0; i--) {
    if (nav[i].classList.contains('revealed')) { revealed = i + 1; break; }
  }
  renderReveal();
}

function exitNarrate() {
  clearPending();
  revealed = 0;
  CARDS.forEach(c => c.classList.remove('revealed'));
}

/* ---- collapse / reopen / clear ---- */
document.getElementById('d-close').addEventListener('click', () => body.classList.add('sidebar-collapsed'));
document.getElementById('d-clear').addEventListener('click', () => {
  setFragment(location.pathname + location.search);   // drop the #<ref>
  clearSelection();
});
/* ---- keyboard ----
   Escape peels one layer at a time: an open sidebar first, then the selection.
   Ignored while typing, so Escape in the summary box still means "revert the
   box" (see showSummaryEditor). */
const TYPING = 'input, textarea, select, [contenteditable]';

/* Every card in document order, materialized once. */
const CARDS = Array.from(cards);
/* Does narration stop here? A "beat" is one step of n / p / shift+arrow, and
   which cards count is now the PARSER's call, carried on the card as data-beat
   (see BEAT_KINDS in lib/conversation_story/parser.rb) and overridable per card
   from the edits sidecar. This used to sniff k-user/k-assistant plus "not inside
   .subactions" — the same set, but re-derived here from CSS classes, so Jess had
   no way to say "don't stop on that one". */
const isBeat = c => c.dataset.beat === 'true';

/* ---- subagent subactions ----
   A `subagent` card is followed by a .subactions block holding cards for the
   story that subagent produced. It ships COLLAPSED — the real subagent logs run
   to 70 events, which would bury the conversation they belong to — and the caret
   in the gutter opens it.

   Those cards are display:none while collapsed, so they must drop out of every
   list that means "cards Jess can step through": arrow navigation and narrate
   beats alike. NAV() is that list, recomputed on use because the caret changes
   it. With every subagent collapsed (the initial state) NAV() === CARDS. */
function inCollapsedBlock(card) {
  for (let w = card.closest('.subactions'); w; w = w.parentElement.closest('.subactions')) {
    const owner = w.previousElementSibling;   // the .card.k-subagent it belongs to
    if (owner && owner.classList.contains('collapsed')) return true;
  }
  return false;
}
const NAV = () => CARDS.filter(c => !inCollapsedBlock(c));

function toggleSubactions(card) {
  card.classList.toggle('collapsed');
  if (mode === 'narrate') resyncReveal();
}

/* Move the selection by one card, or by one user/assistant message with shift.
   Does NOT open the sidebar — that state is Jess's (see collapseSidebar).
   Only ever called in explore/edit: the keydown handler's narrate branch
   returns before reaching this, so there's no "revealed cards only" case to
   filter for here. */
function moveSelection(dir, byMessage) {
  const list = NAV();
  if (!list.length) return;
  const active = document.querySelector('.card.active');
  let i = list.indexOf(active);
  if (i < 0) i = dir > 0 ? -1 : list.length;
  let next = i + dir;
  if (byMessage) {
    while (next >= 0 && next < list.length && !isBeat(list[next])) next += dir;
  }
  if (next < 0 || next >= list.length) return;
  const card = list[next];
  setFragment('#' + card.id);
  selectCard(card);
  card.scrollIntoView({ block: 'nearest' });
}

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

  if (mode === 'narrate') {
    switch (key) {   // `key` is the case-folded e.key from Task 3
      case 'ArrowRight': return act(() => revealTo(e.shiftKey ? beatForwardTo(revealed) : revealed + 1));
      case 'ArrowLeft':  return act(() => revealTo(e.shiftKey ? beatBackTo(revealed) : revealed - 1));
      case 'n':          return act(() => revealTo(beatForwardTo(revealed)));
      case 'p':          return act(() => revealTo(beatBackTo(revealed)));
    }
    return;
  }

  switch (key) {
    /* 'n' and 'N' are the same key here: from explore or edit, both mean
       "start narrating". They only diverge inside narrate, where 'n' gets the
       beat-forward job above. */
    case 'n':          return act(() => setMode('narrate'));
    case 'ArrowRight': return act(() => moveSelection(1, e.shiftKey));
    case 'ArrowLeft':  return act(() => moveSelection(-1, e.shiftKey));
  }
});

/* Escape peels one layer at a time: an open sidebar first, then the selection
   (or, in narrate, the mode itself — see exitNarrate above). */
function escapeKey() {
  if (!body.classList.contains('sidebar-collapsed')) { collapseSidebar(); return; }
  if (mode === 'narrate') { setMode('explore'); return; }
  setFragment(location.pathname + location.search);
  clearSelection();
}

/* ---- drag to resize ---- */
const resizer = document.getElementById('resizer');
let dragging = false;
resizer.addEventListener('mousedown', e => { dragging = true; body.classList.add('resizing'); e.preventDefault(); });
window.addEventListener('mousemove', e => {
  if (!dragging) return;
  const w = Math.min(720, Math.max(300, window.innerWidth - e.clientX));
  document.documentElement.style.setProperty('--sidebar-w', w + 'px');
});
window.addEventListener('mouseup', () => { dragging = false; body.classList.remove('resizing'); });

/* ============================================================
   Mount Malleable — rewrite a card's summary on the page.

   PROGRESSIVE ENHANCEMENT, and deliberately so: the published site is static
   files with nowhere to write. On load we probe GET /api/health; only if the
   local authoring server (bin/serve) answers does an editor appear at the top
   of the detail pane. On GitHub Pages the probe 404s and this whole section
   stays dark — same JS file, same pages, no build flag.

   Saving PUTs {story, ref, summary} and the server rewrites
   edits/<story>.yaml, re-runs bin/parse + bin/render, and answers with the
   summary that actually landed on disk. So the page updates optimistically
   from the SERVER's answer, never from what we typed, and a reload always
   agrees with it. Clearing the text reverts to the parser's own summary.
   ============================================================ */
const STORY = body.dataset.story;

/* Rebuild the editor for `card` at the top of the detail pane. Called from
   selectCard, so it runs on every selection; a no-op until the probe succeeds. */
function showSummaryEditor(card) {
  if (!editingAvailable || mode !== 'edit') return;
  const summaryEl = card.querySelector('.summary');

  const sec = document.createElement('div');
  sec.className = 'd-section summary-edit';
  sec.innerHTML =
    '<h4 class="deco">Summary</h4>' +
    '<textarea class="summary-input" rows="2" spellcheck="true"></textarea>' +
    '<div class="summary-actions">' +
      '<button type="button" class="summary-btn save">Save</button>' +
      '<button type="button" class="summary-btn revert">Revert</button>' +
      '<span class="summary-status"></span>' +
    '</div>';

  const input  = sec.querySelector('.summary-input');
  const save   = sec.querySelector('.save');
  const revert = sec.querySelector('.revert');
  const status = sec.querySelector('.summary-status');

  const currentText = () => summaryEl.textContent.trim();
  const load = () => { input.value = currentText(); autogrow(input); };
  load();
  revert.disabled = !card.dataset.edited;

  /* Send a summary to the server and reconcile the page with its answer.
     Empty text means "no override". */
  function submit(text) {
    // What we're about to throw away, if it was Jess's line and not the
    // parser's. Captured before the request so undo has something to restore.
    const lost = card.dataset.edited ? currentText() : null;

    status.className = 'summary-status';
    status.textContent = 'saving…';
    return fetch('/api/summary', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ story: STORY, ref: card.id, summary: text }),
    })
      .then(r => r.json().then(j => (r.ok ? j : Promise.reject(new Error(j.error || ('HTTP ' + r.status))))))
      .then(result => {
        applySavedSummary(card, result);
        revert.disabled = !result.edited;
        status.textContent = result.edited ? 'saved' : 'reverted to generated';
        status.classList.add('ok');
        if (lost !== null && lost !== result.summary) offerUndo(lost);
      })
      .catch(err => {
        status.textContent = err.message;
        status.classList.add('bad');
      });
  }

  /* A hand-written line just disappeared — Revert dropped it, or a Save wrote
     over an older one. The sidecar is in git and the box is right there, but
     neither is a *click*, and Revert is one keystroke away from being an
     accident. So the confirmation itself carries the way back. It survives only
     until the next request or reselect: one level, in-session, which is what
     this is protecting against. */
  function offerUndo(lost) {
    const undo = document.createElement('button');
    undo.type = 'button';
    undo.className = 'undo';
    undo.textContent = 'undo';
    undo.addEventListener('click', () => submit(lost).then(load));
    status.append(' · ', undo);
  }

  save.addEventListener('click', () => submit(input.value));
  revert.addEventListener('click', () => { submit('').then(load); });
  input.addEventListener('input', () => autogrow(input));
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); save.click(); }
    if (e.key === 'Escape') { e.preventDefault(); load(); }
  });

  dBody.prepend(sec);
  autogrow(input);   // scrollHeight only reads true once it's in the document
}

/* The beat toggle: is this where narration stops? Same gate as the summary box —
   the authoring server must be answering AND the page must be in edit mode — so
   the published site shows the 🥁 cue (see selectCard) with no way to change it.
   It SUBMITS ON TOGGLE, with no Save button: a boolean has no draft state to
   protect the way half-typed prose does, and unchecking it is the undo. */
function showBeatEditor(card) {
  if (!editingAvailable || mode !== 'edit') return;

  const sec = document.createElement('div');
  sec.className = 'd-section beat-edit';
  sec.innerHTML =
    '<label class="beat-toggle"><input type="checkbox">' +
    '<span>Beat stops here</span></label>' +
    '<span class="summary-status"></span>';

  const box    = sec.querySelector('input');
  const status = sec.querySelector('.summary-status');
  box.checked = card.dataset.beat === 'true';

  box.addEventListener('change', () => {
    const wanted = box.checked;
    status.className = 'summary-status';
    status.textContent = 'saving…';
    fetch('/api/beat', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ story: STORY, ref: card.id, beat: wanted }),
    })
      .then(r => r.json().then(j => (r.ok ? j : Promise.reject(new Error(j.error || ('HTTP ' + r.status))))))
      .then(result => {
        // Believe the server, not the checkbox: the flag on the page comes from
        // the rebuilt story.yaml, exactly like a saved summary does.
        if (result.beat) card.dataset.beat = 'true'; else delete card.dataset.beat;
        box.checked = result.beat;
        status.textContent = result.beat ? 'beat on' : 'beat off';
        status.classList.add('ok');
      })
      .catch(err => {
        box.checked = card.dataset.beat === 'true';
        status.textContent = err.message;
        status.classList.add('bad');
      });
  });

  dBody.prepend(sec);
}

/* Fit the box to the summary. A summary is one line of prose but can wrap to
   several in a narrow sidebar, and a clipped half-line reads like a bug. CSS
   caps the growth (max-height) and takes over with a scrollbar past that. */
function autogrow(input) {
  input.style.height = 'auto';
  input.style.height = input.scrollHeight + 2 + 'px';
}

/* Put the server's answer on the card face. A generated summary can be markup
   (a tool call's bold name + <code> argument), so we stash that HTML before
   the first overwrite — that's what a revert restores. Other cards' "Related
   events" links still show the old text until the page is reloaded. */
function applySavedSummary(card, result) {
  const summaryEl = card.querySelector('.summary');
  if (result.edited) {
    if (card.dataset.generatedSummary === undefined) card.dataset.generatedSummary = summaryEl.innerHTML;
    summaryEl.textContent = result.summary;
    card.dataset.edited = 'true';
  } else if (card.dataset.generatedSummary !== undefined) {
    summaryEl.innerHTML = card.dataset.generatedSummary;
    delete card.dataset.edited;
  } else {
    summaryEl.textContent = result.summary;
    delete card.dataset.edited;
  }
}

fetch('/api/health')
  .then(r => (r.ok ? r.json() : Promise.reject(new Error('static'))))
  .then(info => {
    if (!info.editing) return;
    editingAvailable = true;
    modeButtons.find(b => b.dataset.mode === 'edit').hidden = false;
    // Only force edit mode for a `?mode=edit` load if Jess hasn't already
    // moved on to something else while this request was in flight.
    if (wantedMode === 'edit' && !modeChangedSinceLoad) setMode('edit');
  })
  .catch(() => { /* published site: no write path, no edit mode */ });

/* initial paint: honor a deep link if present, else open the default card */
syncFromHash();

/* ...then the mode. `wantedMode` is remembered because ?mode=edit can't be
   honored until the health probe answers, which is after this runs. */
const wantedMode = new URLSearchParams(location.search).get('mode');
body.classList.add('mode-explore');
if (wantedMode && wantedMode !== 'edit') setMode(wantedMode);
