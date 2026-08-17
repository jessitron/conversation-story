# SEAMAP — Conversation Story

## North Star

A conversation with an agent is intelligible: I can see and explain to another
person what was hard for the agent. This is easier when I enjoy looking at it.

## The Mountains

- **Mount Struggle** — it's clear where the agent is struggling: errors, merge
  conflicts, digging (going deep/wide to find something), context bloat. I can
  point at a stretch of the conversation and say "this is where it got hard."
- **Mount Complete** — everything recorded in the conversation log is
  intelligible on the web page.
- **Mount Beautiful** — I enjoy looking at it. The drill-into-detail feels like
  exploration.

*(Deprioritized: **Mount Malleable** — a local web app for shaping the story;
summaries are already editable on the page, but this isn't where the energy
is right now.)*

*(Climbed: **Mount Minimal** — every event in the main conversation shows as a
card, all looking the same. **Mount Interactive** — three modes, a keyboard
map, and a narrate mode that reveals the conversation a beat at a time.)*

Mount Struggle is the current priority. Session 22 laid the token-accounting
groundwork for its context-bloat signal — per-card context attribution and
"dark matter" (`notes/2026-08-11-session-22-dark-matter-and-underspecified-events.md`).
Session 23 shipped `context-map-sidebar` v1 (TODO.md, Next): a "where are we"
bar on the left, sized from that per-card accounting — main conversation
only, jumps on selection. Still open on that item: subagent bars, narrate-mode
animation, and a header toggle to show all subagent bars at once.
`underspecified-events-display` (TODO.md, Backlog) still needs an unobtrusive
way to show the dark-matter numbers session 22 computed but didn't style.

## Safe Harbor

Pushed to `main`, built and published on GitHub Pages
(<https://jessitron.github.io/conversation-story/>).

## Success looks like

I learn surprising things about how my agents are struggling. I can make my
work more efficient. I can teach this to others.

## How will we know it's working?

I change how I prompt/work based on what the page showed me. I make a
Graceful.Dev episode about it.

## Enabling Constraints

Static web pages. We can put the output of examples on gh-pages in this repo
when we choose to. It understands Claude logs from a range of time frames,
defined by the examples. We need good fallbacks for elements in the logs we
haven't seen before. The intermediate format can be modified by hand when
that's useful to me.

## Non-goals

Right now, no other agents; later, we can make new routes from logs ->
intermediate. Right now, it doesn't run on any conversation that isn't in the
examples directory. Later we'll give it ways to pull from whatever's
available in `.claude`. This doesn't need to run on anyone else's computer,
but I do like to document assumptions and prerequisites.

## Tracking

Where the live work for this project is recorded. (Contract: the seamapping
plugin's `TRACKING-ADAPTER.md`.)

- inbox: `TODO.md` — raw captures, pre-decision. Format: the plugin's
  `INBOX.md`.
- tracker: none configured. `TODO.md` is the whole system for now; run
  `/setup-matt-pocock-skills` if this ever outgrows the inbox.
