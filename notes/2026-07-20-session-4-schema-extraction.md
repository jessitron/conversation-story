# Session 4 — Schema extracted to its own file (2026-07-20)

## What we did

Documentation tidy-up. No code.

- **Moved the intermediate schema out of `plan.md` into
  `notes/intermediate-schema.md`.** `plan.md` had grown to hold the whole
  annotated `story.yaml` example plus its field notes; that's really its own
  document. The new file holds: the annotated YAML example, the "schema is the
  contract — no raw for known types" rule, the notes on required fields
  (tokens, provenance, queued, approval, agent identity), and the event
  `kind`s. Its header states plainly it's an **informal working document** —
  the contract between `bin/parse` and `bin/render`.
- **`plan.md` now references it** with a short pointer where the schema used to
  be. The settled high-level **Decisions** stayed in `plan.md` (those are
  project decisions, not the schema itself).
- **`CLAUDE.md` updated** to send readers to `notes/intermediate-schema.md` for
  the schema and `notes/plan.md` for the Decisions.
- **Fixed a stale contradiction Jess asked me to clean up**: the Verification
  section of `plan.md` still said "assert assistant messages carry
  `tokens.raw`" — but the "no raw for known types" decision means tokens are
  **named fields**. Now asserts `tokens.input`/`tokens.output`.

## Why this split

The schema is the contract and will be edited on its own as we learn the log
format; keeping it separate from the plan (which is about layout, staging, and
decisions) means each doc changes for its own reason. Same instinct as
splitting parse/render in session 3 — one thing, one place.

## State at end of session

3 commits (schema move, then the Verification fix). Still no real parse/render
logic. Next step unchanged from session 3: parser skeleton + golden-fixture
test, Mountain 1 end-to-end (every event as an identical card). See
`notes/plan.md` "Staged build" and `notes/intermediate-schema.md` for the
target shape.
