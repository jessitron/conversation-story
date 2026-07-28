# Session 16 — grabbing examples, and the mode a prompt was sent in

2026-07-28. Two threads: a script for bringing conversation logs into
`examples/`, and showing which mode a prompt was sent in. The second one is
mostly a story about being wrong in a way that only a deliberate experiment
could catch.

## `bin/grab-example`

Copying a session log into `examples/` had become a three-time move, so it's a
script now:

    bin/grab-example --list                    # sessions for this repo, newest first
    bin/grab-example <session-id> <name>

`--list` prints id, size, mtime and **the first thing the human typed**, which is
how you recognize a session without opening a 7 MB file. The grab copies the main
log plus `<session>/subagents/*` if the session delegated — the parser finds those
by filename, so it's a straight copy with no rewriting.

Grabbing the session you're sitting in copies a **live** file: the fixture stops
wherever the log happened to be, and everything after (including the copy) is
missing. The script says so when it notices. Re-run to re-snapshot.

Two logs came in this way: `inlining-subagents` (683 lines — session 15, where we
built subagent inlining) and `mode-switches` (443 lines — this session).

### New record types showed up in the newer logs

The episode-8 fixtures predate three record types that newer logs carry:
`mode`, `ai-title`, `file-history-delta`. They all fell to the `unknown`
fallback and broke `only_expected_unknowns`. They're recognized hidden kinds
now (`file-history-delta` → `file_snapshot`, `mode` → `permission_mode`,
`ai-title` → a new `ai_title` kind that keeps the title in `detail.text`, so
naming the kind loses nothing).

Also: the subagent tests asserted that *every* example spawns an Agent. A log
that never delegates now `skip`s them instead of failing.

### Fixtures are big

`inlining-subagents.jsonl` is 6.8 MB and its built page another 2.3 MB, all
committed. `examples/` was 550 KB before this session. Fine occasionally, worth a
policy if we keep adding sessions.

## The mode a prompt was sent in

**Where it lives: `permissionMode`, on the prompt record itself**, next to
`promptId`. One line in `Parser#build_event` reads it; a `Mode` row shows in the
prompt's detail pane. Because a prompt card right-aligns its own content, "show
it on the right" came free — no new CSS.

### What I got wrong, and how it got caught

The harness also writes a timestamp-less trio — `last-prompt`, `mode`,
`permission-mode` — and I built the first version on it. The reasoning looked
airtight: the trio lands *after* a prompt, and `last-prompt` holds **that
prompt's own text**, so surely the trio describes the prompt it follows. I even
wrote a test asserting that reading the stamp *before* the prompt would credit a
switch one prompt too late, and documented the direction in two places.

Then Jess sent a prompt in plan mode on purpose, to make a fixture with a real
switch in it. The log said:

    374  18:21:05  user   permissionMode=plan   "this is a prompt in plan mode"
    ...
    392            last-prompt   "this is a prompt in plan mode"   ← that prompt
    394            mode          normal                            ← but: normal

The trio arrived 18 lines and three minutes later, by which time Jess had left
plan mode — and it recorded *that*. **All 22 `mode` records in the log say
`normal`**, in a session containing a genuine plan-mode prompt. The shipped code
reported `normal` for that prompt and badged nothing: it failed silently on the
exact case it existed for.

So: `last-prompt` is the **up-arrow recall buffer**, not a binding to a prompt.
A trio *following* a prompt is not a trio *about* it. The records hold UI state
at write time, and a mode switched back before the turn ends never appears in
them at all. They stay hidden, nothing derives from them, and a test in
`parser_test.rb` fails if that regresses. The warning lives on
`Parser::TYPE_TO_KIND`, where someone reaching for those records would look.

**The lesson worth keeping:** for a question about log *format*, a plausible
story about neighbouring records is a hypothesis, not a finding. The phenomenon
was cheap to generate on purpose — one prompt in plan mode — and that experiment
was worth more than the two documentation sections I'd written around the guess.
Generate the case before building on the inference. (Jess's `/loop`-free version
of this: "the curious mind over the inventive mind.")

### Then it got simpler

The first working version also tracked `mode_changed` and badged the card face
when the mode moved. Jess asked whether it would simplify things to just put the
mode in the prompt's fields. It did: dropping the flag and the badge removed the
whole `stamp_modes!` pass — `events.zip(records)`, cross-event state, the
`to_document` call — leaving one line where every fact is local to its own
record. Net −40 lines.

Noticing a *change* and marking it in the stream is now a TODO under Mount
Complete, not code.

## Two gotchas for future sessions

- **Grepping a page built from a log about editing that page's own code.**
  Counting `badge mode` in `out/mode-switches/index.html` returned 38 — 37 of
  them my own source code, escaped, inside tool cards. Self-referential fixtures
  inflate string counts. Count the unescaped markup
  (`<span class="badge mode">`), not a bare substring.
- **`bin/screenshot` on a card deep in a long page comes back fully blank.**
  The known "region above the target repaints blank" artifact scales up: card
  374 of 449 means the whole viewport is blank. To *see* a card treatment,
  build a small synthetic story (8 records) and shoot that — the throwaway
  script pattern in the scratchpad worked well and is worth recreating rather
  than fighting the artifact.
