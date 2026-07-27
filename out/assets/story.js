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

/* show a card's detail in the sidebar (pure UI — does not touch the URL) */
function selectCard(card) {
  cards.forEach(c => c.classList.remove('active'));
  card.classList.add('active');

  body.classList.remove('sidebar-collapsed');
  dKind.textContent = card.querySelector('.gutter .kind').textContent;
  dTime.textContent = card.dataset.time + ' UTC';
  sidebar.style.setProperty('--kind', getComputedStyle(card).getPropertyValue('--kind'));

  dBody.replaceChildren(card.querySelector('template.detail').content.cloneNode(true));
  dBody.scrollTop = 0;
  updateRelated(card);
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
  body.classList.remove('sidebar-collapsed');
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
  if (card.classList.contains('active')) return;   // already showing; nothing to do
  setFragment('#' + card.id);
  selectCard(card);
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
document.getElementById('reopen').addEventListener('click', () => body.classList.remove('sidebar-collapsed'));

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

/* initial paint: honor a deep link if present, else open the default card */
syncFromHash();
