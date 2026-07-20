# Session 3 — Rake pipeline scaffolding (2026-07-20)

## What we did

Set up how the app is *run*, before writing any real logic.

- **Phases are rake tasks**, not loose shell scripts. `rake parse / render /
  build / serve / test`. `rake -T` lists them. Rake ships with Ruby (no new
  dep) and `rake <task>` is easy to allowlist — no complicated inline bash.
- **Parse and render are TWO SEPARATE PROGRAMS** (`bin/parse`, `bin/render`),
  not two functions in one process. Jess was emphatic about this. Each program
  requires only its own `lib/` code; they share nothing at runtime except the
  intermediate `out/<name>/story.yaml` on disk — that file is the contract.
  This keeps the door open to swap in a different-source parser later without
  the renderer knowing.
- **Rake owns the dependency between the programs**, and only that. File tasks:
  `out/<name>/index.html` <- `out/<name>/story.yaml` <- `examples/<name>.jsonl`.
  Each task shells out (`sh "ruby", "bin/parse", ...`) to a real separate
  process. Asking for the page runs the parser first when the story is stale.
- Stub `lib/conversation_story/{parser,renderer}.rb` classes raise a clear
  `NotImplementedError` pointing at `notes/plan.md`. Plumbing is real; logic is
  the next step.
- Deleted `lib/conversation_story.rb` (an aggregator that `require`d both) —
  it implied a single combined program, which contradicts the separation.

## Decisions settled

- Intermediate YAML lives at `out/<name>/story.yaml`, alongside its rendered
  `index.html`. So the "hand-edit the intermediate" constraint just works, and
  gh-pages ignores the extra `.yaml`.
- Default = ALL examples. `LOG=examples/foo.jsonl rake build` scopes to one.
  `PORT=` for serve. (Dropped the earlier `NAME=` idea — `LOG=` scoping flows
  through the file-task deps to render too, so one knob is enough.)
- Programs also run standalone with `-o OUTPUT` (default stdout) for hand piping.

## Gotcha / open item (added to TODO.md)

- Need a way to mark a `story.yaml` as **hand-edited** so `rake parse` won't
  overwrite it. Note: rake's mtime rule already skips re-parsing when the story
  is newer than its log — but that's implicit, not an explicit "leave this
  alone" signal. Want a real marker (frontmatter flag or sidecar lock file the
  parse step checks).

## State at end of session

Scaffolding committed (2 commits). No real parse/render logic yet. Next step
unchanged: parser skeleton + golden-fixture test, Mountain 1 end-to-end
(every event as an identical card). See `notes/plan.md` "Staged build".
