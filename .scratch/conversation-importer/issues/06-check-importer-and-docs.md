# 06 — `bin/check-importer`, and pointing the docs at the new door

**What to build:** a way to know the import path still works after someone
touches it, and a CLAUDE.md that sends the next agent to the right tool.

**`bin/check-importer`** drives a **real import over plain HTTP**, in the same
mould as `bin/check-edit-api`: start the importer, post an import, assert the
fixture and the built page appeared, assert the slug and overwrite refusals still
refuse. No Chrome — `bin/check-modes` earns ferrum because keyboard and mode
behaviour is unobservable from Ruby, and a `<form>` submitting is not.

It runs against a **temp examples dir and a temp cache**, so it never touches
Jess's real fixtures — and a small temp examples dir also keeps the shelled-out
parse/render fast enough to loop on. (Note the trap `bin/check-edit-api` fell
into: a temp dir that doesn't mirror the real one can make a rebuild strip real
hand-written data. See TODO.md's `check-edit-api-sidecar-bug`.)

Then **CLAUDE.md's `bin/grab-example` paragraph** gets rewritten around the
importer: `bin/importer` is the primary door for bringing a new example in,
`bin/grab-example` is the CLI one — scriptable, needs no browser, still
documented. Without this, the next session's agent reaches for the wrong tool.

**Blocked by:** 05 — the last of the import behaviour.

**Status:** done

- [x] `bin/check-importer` starts the importer, performs a real import over plain
      HTTP, and asserts the fixture and the built page both appeared
- [x] It asserts the bad-slug and unrelated-overwrite refusals
- [x] It uses a temp examples dir and temp cache, and leaves the real `examples/`,
      `out/` and cache untouched
- [x] It uses no Chrome / ferrum
- [x] CLAUDE.md names `bin/importer` as the primary door and `bin/grab-example` as
      the CLI one
- [x] `README.md`'s program list mentions the importer alongside parse / render /
      site-index / serve
- [x] `rake test` passes and every `bin/check-*` script still passes
