# Session 2026-07-20 (2) — page design prototype

## What we did

Designed the look & feel of the output page, before generating anything, so Jess
never has to look at an ugly page. Built **`design-prototype.html`** — a
self-contained, static mockup with sample event cards (one per `kind`). This is a
design reference, not app code; the real renderer (ERB) will reproduce this look.

## The design (art-deco, from the brand assets)

- **Fonts** (`notes/fonts-and-colors.txt`): headings **Tenor Sans**, body **Sen**,
  fixed **Cascadia Code**. Loaded via Google Fonts CDN in the prototype; **self-host
  all three for the real static build.** CSS vars: `--font-head/--font-body/--font-mono`.
- **Palette**: the five `graceful-*` colors + derived warm-paper neutrals
  (`--paper`, `--ink`=navy, `--line`, `--gold`). Defined as CSS vars at `:root`.
- **Logo**: `images/logo.png` (black art-deco mandala, "GD"). Inverted to white
  (`filter: invert(1)`) to sit on the navy header.

## Layout & behavior settled

- **Header** scrolls off (not sticky). Shows logo, title, and stat cluster:
  Events / Duration / **Model** / **Branch**. Model & Branch = the *starting*
  model/branch (parallel definitions).
- **Rail label** above the timeline reads **"claude code"** (how the convo started),
  in spaced caps with a fading rule. (Was "Timeline".)
- **Cards**: left color spine keyed to `kind`. Per-kind treatment matters:
  - **user** — right-aligned like the far side of a chat (spine on the right),
    white bg, indented from left.
  - **assistant** — elevated: white card, wider navy spine, Tenor Sans 17px,
    soft shadow. The conversation *headline*.
  - **thinking / tool_call / tool_result / system** — background machinery:
    transparent, dimmed to 0.7 opacity, smaller text; **hover only brightens**
    (no movement, no shadow — Jess dislikes cards moving on hover).
  - **subagent** — red spine, sits on warm paper.
- **Detail sidebar** (right): collapsible + drag-resizable (300–720px). Three
  states: collapsed, open-empty (◇ clear button), populated (×  collapses).
  Its **left border + header rule take the selected card's kind color**
  (1px border — 4px was too thick).
- **Leader line**: dotted, kind-colored line from the active card to the sidebar.
  Implemented as an in-flow `.card::after` pseudo-element (NOT fixed-position) so
  it scrolls/rubber-bands *with* the card. Runs off-page, clipped by
  `html { overflow-x: clip }`; sidebar paints over it so it reads as going behind
  the pane. Shown/hidden purely by CSS classes (`.active`, `body.sidebar-collapsed`)
  — no JS style-poking.

## Tag (badge) vocabulary — deliberate, keep it tight

- Tool calls: **Read / Write / Exec** (Exec = Bash). Navy badges.
- **Error** — filled-red badge on failed tool calls/results.
- **Subagent** — red-outline badge on subagent cards.
- **Token & tool counts** appear on the **subagent card only**.
- Everything else (model name, "hook", durations) is NOT a summary badge — it
  lives in the detail view.

## Data findings (checked against examples/)

- **Model varies within one conversation**: main thread = `claude-opus-4-6` (104),
  subagents = `claude-haiku-4-5-20251001` (75). So a single "model" per document is
  wrong — hence per-event `model`, and the header shows the *starting* model.
- **`gitBranch`** present on all 346 records (value "main"). Reliable → header
  Branch stat is legit. Per-record, so a convo could in principle span branches.

## Working agreements reinforced

- **Commit every time I show Jess something.** Small commits, tagged `- claude`.
- Prefer named scripts over shell herefiles (still true; see session 1 gotcha).
- Use `AskUserQuestion`-style single-question flow; warn about mistakes.

## Next step

Still the parser skeleton + golden test (Mountain 1), per `notes/plan.md`. When we
build the ERB renderer, reproduce `design-prototype.html`'s look and self-host fonts.
