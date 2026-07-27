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

/* the empty-state markup that ships in the sidebar; restored on clear */
const EMPTY_HTML = dBody.innerHTML;

/* update the URL fragment without scrolling or firing hashchange.
   Wrapped because some browsers block history writes on file:// URLs —
   selection must still work even when the URL can't be updated. */
function setFragment(frag) {
  try { history.replaceState(null, '', frag); } catch (_) { /* file:// */ }
}

/* The sidebar's open/collapsed state is Jess's, not selection's. Only an
   explicit open (clicking a card) or an explicit collapse (clicking the active
   card, Escape, ×, or advancing a narration beat) moves it. */
function collapseSidebar() { body.classList.add('sidebar-collapsed'); }
function openSidebar()     { body.classList.remove('sidebar-collapsed'); }

/* show a card's detail in the sidebar (pure UI — does not touch the URL) */
function selectCard(card) {
  cards.forEach(c => c.classList.remove('active'));
  card.classList.add('active');

  dKind.textContent = card.querySelector('.gutter .kind').textContent;
  dTime.textContent = card.dataset.time + ' UTC';
  sidebar.style.setProperty('--kind', getComputedStyle(card).getPropertyValue('--kind'));

  dBody.replaceChildren(card.querySelector('template.detail').content.cloneNode(true));
  dBody.scrollTop = 0;
  updateRelated(card);
  showSummaryEditor(card);   // no-op unless the authoring server answered
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
}

/* URL fragment -> selection. Unknown/empty fragment falls back to the default
   card so the page is never empty. Used on load and on hashchange; scrolls the
   target into view only when arriving via a real fragment (deep link). */
function syncFromHash() {
  const id = decodeURIComponent(location.hash.slice(1));
  const card = id ? document.getElementById(id) : null;
  const target = (card && card.classList.contains('card')) ? card : DEFAULT_CARD;
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

/* ---- focus mode: hide the background-machinery cards (thinking, tool calls
   and results, system/queue chatter) so only the actual back-and-forth with
   Jess shows. A CSS class toggle — no data is removed, so switching back
   loses nothing and deep links into a hidden card still work (the click
   listener and #cards still see it; only its box is display:none). ---- */
const focusToggle = document.getElementById('focus-toggle');
focusToggle.addEventListener('click', () => {
  const on = body.classList.toggle('focus-mode');
  focusToggle.textContent = on ? 'Show everything' : 'Just the conversation';
  focusToggle.setAttribute('aria-pressed', String(on));
});

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

window.addEventListener('keydown', e => {
  if (e.target.closest && e.target.closest(TYPING)) return;
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key !== 'Escape') return;
  e.preventDefault();
  if (!body.classList.contains('sidebar-collapsed')) { collapseSidebar(); return; }
  setFragment(location.pathname + location.search);
  clearSelection();
});

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
let editing = false;

/* Rebuild the editor for `card` at the top of the detail pane. Called from
   selectCard, so it runs on every selection; a no-op until the probe succeeds. */
function showSummaryEditor(card) {
  if (!editing) return;
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
    editing = true;
    body.classList.add('editable');
    const active = document.querySelector('.card.active');
    if (active) showSummaryEditor(active);   // the probe lost the race with the first paint
  })
  .catch(() => { /* published site: no write path, no editor */ });

/* initial paint: honor a deep link if present, else open the default card */
syncFromHash();
