# Session 12 — Ruby 4, asdf pinned in the repo, and the first Gemfile

Two commits: `99da7e0` (pin Ruby 4 with asdf) and `7e1b304` (declare webrick in
a Gemfile). Both are the same bug at different levels: **a prerequisite that
lived in Jess's home directory and was reproduced by a sentence in the README.**
Jess works across multiple computers, so that class of bug is always real here.

## What was wrong

`asdf current ruby` in this repo resolved to `~/.tool-versions` — there was no
pin in the project at all. The docs claimed `.ruby-version` managed by
"rbenv/asdf"; neither the file nor rbenv existed. A second computer with a
different global pin builds this project on a different Ruby, silently.

Fixed by `.tool-versions` (asdf's native file) holding `ruby 4.0.6`, and CI's
`ruby/setup-ruby` moving `3.4` → `4.0`.

## Gotcha: the pin was globally gitignored

`/Users/jessitron/code/jessitron/dotfiles/gitexcludes` lists `.tool-versions`.
A sensible global default — tool pins are usually personal — but it meant the
fix would never have been committed and nothing would have changed on the other
laptop.

**A repo `.gitignore` outranks `core.excludesFile`**, so `!.tool-versions` in
this repo's `.gitignore` wins. That negation is there on purpose; don't tidy it
away. `Gemfile.lock` is *not* in the global excludes, so it tracks normally.

Also: `git check-ignore -v` exits 0 when *any* pattern matches, including a
negation, so it prints `!.tool-versions` and looks like it's still ignored. Use
`git status` to check — ignored files don't appear there.

## Ruby 4's three tiers of "ships with Ruby"

This is the distinction the whole Gemfile question turned on:

| tier | examples here | can a future Ruby drop it? |
|---|---|---|
| **default gem** | `json`, `psych`, `erb` | no, part of the interpreter |
| **bundled gem** | `rake`, `minitest` | yes — ordinary gems, just preinstalled |
| **dropped** | `webrick` (as of 4.0) | already did |

Check with `Gem::Specification#default_gem?` — `gem list` won't tell you:

    ruby -e 'puts Gem::Specification.select { |s| %w[rake minitest webrick json].include?(s.name) }.map { |s| "#{s.name} #{s.version} default=#{s.default_gem?}" }.uniq'

So "stdlib-only" was always a bit generous for the test suite: `minitest` and
`rake` are bundled, not default. Minitest here is **6.x** now (it pulls `prism`
and `drb`), a major version up from the 5.x era.

## The diagnostic that settled the Gemfile question

Ruby 4.0 unbundled `webrick`, which `bin/serve` needs, and the fix in flight was
a README line saying `gem install webrick`. Was that acceptable? Compare mtimes
of the gem directory against the interpreter:

    stat -f '%Sm  %N' ~/.asdf/installs/ruby/4.0.6/bin/ruby
    stat -f '%Sm  %N' ~/.asdf/installs/ruby/4.0.6/lib/ruby/gems/4.0.0/gems/webrick-*

`ruby`, `minitest`, `rake` all read Jul 19 23:03 (install time). `webrick` read
Jul 26 20:46 — a week later, i.e. hand-installed. **That's the proof a gem
didn't ship with Ruby**, and it meant `rake serve` was broken on Jess's other
machine, taking the whole Mount Malleable editing workflow with it.

Hence the Gemfile. It declares `webrick` plus `rake`/`minitest` (so the next
eviction is a `bundle install`, not a debugging session). No `ruby` directive —
`.tool-versions` stays the single pin rather than two that can disagree.

**CI needed `bundler-cache: true` + `bundle exec`.** Without it the committed
lock is decorative: CI's Ruby ships `minitest 6.0.0` while the lock resolves
`6.0.6`, so the two places test different code. If you ever see CI-only test
failures, check that first.

## Process: two Claude windows on one repo

Jess had a second session working Mount Interactive in the same checkout. Worth
knowing what that feels like and what to do:

- **Symptom**: `git status` changes between your own tool calls — files you never
  touched appear modified, `HEAD` moves under you. It is not a bug in your
  reasoning. Re-check state before committing rather than trusting a status from
  earlier in the turn.
- **Never `git add -A`.** Stage explicit paths. When your change and theirs land
  in the *same file*, stage just your hunk — build a patch and
  `git apply --cached` it, which applies against the index and so can't be made
  stale by further working-tree edits:

      git diff -U3 -- FILE | awk '/^@@/ { h++ } h < 2 { print }' | git apply --cached -

- **The real hazard is standing instructions, not text conflicts.** The other
  window wrote into CLAUDE.md: *"there's still no Gemfile — keep it that way."*
  Both statements were true when written and false an hour later. A future
  session reading it would have undone this work. After any change that
  invalidates a documented rule, grep for the rule's own words
  (`grep -rn "no Gemfile" README.md CLAUDE.md TODO.md bin/ lib/ notes/`) — not
  just for the code you changed.
- Direction of assumption: the parallel window was *cleaning up after* the Ruby 4
  pin (it found the webrick breakage), not fighting. Read their commits before
  concluding otherwise.

## Verified

41 tests green bare and under `bundle exec`; `rake build` clean; no warnings
under `RUBYOPT=-W`; `bin/check-edit-api`'s ten write-path checks all pass (that
one exercises webrick for real, so it's the test that proves `rake serve` works).

## Loose ends

- Any long-running `bin/serve` started before the pin is still on the old Ruby.
  Restart it after changing `.tool-versions`.
- `rake serve` is the only program needing a gem. If a second one ever does, the
  README's "the programs themselves use stdlib" line needs revisiting.
