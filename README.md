# Conversation Story

I want to describe to people how a conversation with my agent went.
As I describe the story verbally, I also want to display a web page showing
the conversation accurately, based on the agent's log.

The web page should display everything that happened in the conversation, but most of it will be a tiny summary by default. I can click on an event for more detail.

**See it live: <https://jessitron.github.io/conversation-story/>** — the example
conversations in `examples/`, built and published on every push to `main`
(details in [Published site](#published-site)).

## Architecture

Input Logs -> Intermediate Descriptions -> Output HTML

The input logs are (for now) Claude logs. That's a jsonl file, along with a directory of subagent logs.

The output HTML is a static site. There is minimal JS to support interactivity.

The intermediate description is YAML to describe what will be on the page. It includes all the information needed to generate the output, and not more.

We're building this app in Ruby. Parse and render are **two separate programs**
(`bin/parse` and `bin/render`) that share nothing at runtime except the
intermediate `story.yaml` on disk. Rake is just the task runner — it knows the
dependency between the phases and shells out to each program.

## Running it

Ruby only — version pinned in `.tool-versions` for [asdf](https://asdf-vm.com)
(`asdf install` picks it up). Then:

```sh
bundle install
```

The programs themselves use stdlib (`json`, `yaml`, `erb`). The Gemfile exists
for one reason: **Ruby 4.0 unbundled webrick**, which `rake serve` needs, so
without a declared dependency a fresh machine's `rake serve` just fails.
`rake` and `minitest` are declared alongside it because they ship with Ruby as
*bundled* gems, not default gems — the same category webrick was in until 4.0
evicted it. `bin/serve` prints `bundle install` if webrick is missing.

Plain `rake` works fine; `bundle exec rake` pins the exact versions in
`Gemfile.lock`, which is what CI does.

```sh
rake -T        # list all tasks
rake parse     # bin/parse:  examples/*.jsonl -> out/<name>/story.yaml
rake render    # bin/render: out/*/story.yaml -> out/<name>/index.html
rake site      # bin/site-index: out/*/story.yaml -> out/index.html (landing page)
rake build     # parse, render, then site (dependency-ordered)
rake serve     # bin/serve: out/ at http://localhost:8080, with summary editing on
rake test      # golden-fixture tests
```

Because `rake` tracks the dependency, asking for the page (`rake render` /
`rake build`) runs `bin/parse` first when a `story.yaml` is missing or older
than its log.

The programs also run standalone if you want to pipe them by hand:

```sh
bin/parse examples/episode-8-before.jsonl -o out/episode-8-before/story.yaml
bin/render out/episode-8-before/story.yaml -o out/episode-8-before/index.html
```

**Default is all examples.** Scope to one with env vars:

```sh
LOG=examples/episode-8-before.jsonl rake build   # just this example
PORT=9000 rake serve                             # serve on a different port
```

### Seeing a page

```sh
bin/screenshot                                            # top of episode-8-before
bin/screenshot mtg-tabletop-plan '#mtg-tabletop-plan:749'  # that card, selected
bin/screenshot .                                          # the landing page
bin/check-screenshot                                      # guard the above
```

Headless Chrome against a built page. A fragment is an event ref, and it selects
that card — detail pane open, causal chain highlighted. Quote it; `#` starts a
comment in most shells. Arguments after the first go by shape, so a `.png` is
the output file wherever you put it and the fragment is optional.

Under the hood it clips the viewport around the target rather than scrolling and
shooting, because headless Chrome rasterizes only what's near the current scroll
position — a plain `chrome --screenshot` of a scrolled page comes back as blank
paper. `notes/2026-07-28-session-18-screenshot-clip.md` has the measurements.

The intermediate `out/<name>/story.yaml` is readable and tweakable — change it
and re-run `rake render` to see the difference. But it's a **generated** file:
the next `rake parse` rebuilds it from the log and your change is gone. For an
edit that lasts, use the sidecar below.

## Editing summaries (Mount Malleable)

A card's one-line summary is the parser's guess. To make it read the way you'd
narrate it, run `rake serve` and edit it right on the page: select a card and a
**Summary** box appears at the top of the detail pane. Save writes the new line;
clearing the box (or hitting Revert) goes back to the generated one.

Whenever a save or a revert throws away a line you wrote, the confirmation
carries an **undo** next to it — one click puts your words back. It lasts until
the next save or until you select another card; past that, the sidecar file is
in git.

The edit is stored **outside** the generated output, in `edits/<name>.yaml`,
tracked in git. The file has two named sections, one per kind of hand edit —
`summaries:` (event ref to rewritten line) and `beats:` (event ref to where
narration should stop, see below):

```yaml
summaries:
  episode-8-after:4: "Jess asks: can I rewind the timeline?"
beats:
  episode-8-after:35: false
```

Only this two-section shape is read — there's no fallback for the older flat
`ref: summary` map, so a hand-written flat file is silently ignored rather than
applied.

`bin/parse` re-reads the log from scratch every time and overlays these on top,
so a parser improvement still reaches every card you haven't rewritten, and
nothing in `out/` is ever off-limits. An overridden event is stamped
`summary_edited: true` in the story, which is what tells the renderer to print
your line instead of a composed one (a tool call's name-plus-argument face, say).

The write path is local only. `bin/serve` listens on localhost, and the page
finds it by probing `GET /api/health` — no answer, no editor. The published
GitHub Pages site is the same HTML with nothing to write to. Saving doesn't
patch anything in place either: the server writes the sidecar and re-runs
`bin/parse` and `bin/render` as subprocesses, so the page you reload came from
the same two programs `rake build` would have run.

```sh
bin/check-edit-api            # smoke-test the whole write path (uses a temp edits dir)
bin/screenshot 'http://localhost:8080/episode-8-after/?mode=edit' '#episode-8-after:4'
```

Because refs are line numbers, editing a log orphans its edits — `bin/parse`
warns on stderr about overrides that match no event rather than dropping them
silently.

## Modes and keyboard (Mount Interactive)

The header carries a three-way switch — **Explore / Edit / Narrate** — with
exactly one live at a time as `body.mode-explore|edit|narrate`. Explore is the
default and stays out of the URL; entering another mode writes it as
`?mode=edit` or `?mode=narrate`, so a link can say both which mode and which
card. Edit un-hides only once `bin/serve` answers `GET /api/health` — on the
published site `?mode=edit` quietly falls back to explore.

**Narrate** starts the timeline empty and fills it a **beat** at a time — a run
of cards ending at the next card flagged `beat: true`, inclusive, so the flurry
of tool calls in between is visible on the way. Which cards are beats is a
per-card flag the parser sets (main-thread user/assistant messages, by
default) and Jess can override in edit mode — exempting a message from the
stepping, or adding a stop on a card the parser wouldn't guess, like a tool
call. The newest revealed card is always the selection, so the URL fragment
tracks where you are and a reload resumes rather than restarting. Entering
narrate on a deep link (`#<ref>` already in the URL) reveals everything up to
that card instead of starting empty.

| key | explore / edit | narrate |
|---|---|---|
| `→` | select next visible card | reveal **one** card |
| `←` | select previous visible card | un-reveal **one** card |
| `shift+→` | next **beat** card, scrolled into view | reveal one **beat** |
| `shift+←` | previous **beat** card, scrolled into view | un-reveal one **beat** |
| `n` | enter narrate | reveal one beat (same as `shift+→`) |
| `p` | — | un-reveal one beat (same as `shift+←`) |
| `x` / `e` / `N` | switch to explore / edit / narrate | same |
| `Esc` | collapse sidebar → else clear selection | collapse sidebar → else exit to explore |

Unshifted moves one card, shifted moves one beat — the same shape in both
modes, and `n`/`p` are the easier-to-press aliases for shift-arrow. The sidebar
is sticky state Jess owns: clicking a card opens it, clicking the active card
closes it, and advancing a narration beat closes it too, so drilling into a
card mid-narration is a deliberate, self-clearing detour.

```sh
bin/check-modes    # drives all of it with real keystrokes in headless Chrome
```

## Published site

The examples are live at **https://jessitron.github.io/conversation-story/**.

`.github/workflows/pages.yml` publishes them on every push to `main`: it runs
`rake test`, then `rake build`, then uploads `out/` to GitHub Pages. The Pages
source is set to "GitHub Actions" rather than a branch, which is what lets the
site root be `out/` on `main` — branch-based Pages can only serve a repo root
or `/docs`, so there's no `gh-pages` branch and no `docs/` rename.

`out/` is still committed, so the generated pages show up in a diff. The
workflow rebuilds anyway: if the committed pages and a fresh build ever
disagree, what gets published follows `lib/` and `examples/`.

## North Star

A conversation with an agent is intelligible. I can display it, step through it, drill into it. I can explain what's happening to another person, and they can explore what happened too. Also, it's pretty.

## Along the journey

I love to learn more about how Claude Code works using what we encounter in these logs.

## Mountains

Mountains have names, not numbers — we climb them in whatever order the work
wants, and several are underway at once. `TODO.md` is the working list, grouped
by mountain.

- **Mount Complete** — everything recorded in the conversation log is
  intelligible on the web page.
- **Mount Beautiful** — I enjoy looking at it. The drill-into-detail feels like
  exploration.
- **Mount Malleable** — a local web app for shaping the story. Summaries are
  editable on the page and the change sticks (see above); what else wants
  shaping — which events show, what order they read in — is still open.

*(Climbed: **Mount Minimal** — every event in the main conversation shows as a
card, all looking the same. **Mount Interactive** — three modes, a keyboard
map, and a narrate mode that reveals the conversation a beat at a time; see
"Modes and keyboard" above.)*

## Constraints

Static web pages. We can put the output of examples on gh-pages in this repo when we choose to.
It understands claude logs from a range of time frames, defined by the examples.We need good fallbacks for elements in the logs we haven't seen before.
The intermediate format can be modified by hand when that's useful to me.

## Accepted Limitations

Right now, no other agents; later, we can make new routes from logs -> intermediate.
Right now, it doesn't run on any conversation that isn't in the examples directory. Later we'll give it ways to pull from whatever's available in .claude
This doesn't need to run on anyone else's computer, but I do like to document assumptions and prerequisites.
