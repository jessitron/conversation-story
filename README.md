# Conversation Story

I want to describe to people how a conversation with my agent went.
As I describe the story verbally, I also want to display a web page showing
the conversation accurately, based on the agent's log.

The web page should display everything that happened in the conversation, but most of it will be a tiny summary by default. I can click on an event for more detail.

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

Ruby only (see `.ruby-version`); the programs use stdlib (`json`, `yaml`, `erb`)
and rake, which ships with Ruby. The one dev dependency is `minitest`.

```sh
rake -T        # list all tasks
rake parse     # bin/parse:  examples/*.jsonl -> out/<name>/story.yaml
rake render    # bin/render: out/*/story.yaml -> out/<name>/index.html
rake site      # bin/site-index: out/*/story.yaml -> out/index.html (landing page)
rake build     # parse, render, then site (dependency-ordered)
rake serve     # serve out/ at http://localhost:8080
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

The intermediate `out/<name>/story.yaml` is meant to be hand-editable — tweak it
and re-run `rake render` to see the change.

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

1. Minimal: show every event that happened in the main conversation as a card, all looking the same.

2. Interactive: I can step through the story in a clear way. I can make events visible in progression, and zoom in to details when I want to.

3. Complete: everything recorded in the conversation log is intelligible on the web page

4. Beautiful: I enjoy looking at it. The drill-into-detail feels like exploration.

## Constraints

Static web pages. We can put the output of examples on gh-pages in this repo when we choose to.
It understands claude logs from a range of time frames, defined by the examples.We need good fallbacks for elements in the logs we haven't seen before.
The intermediate format can be modified by hand when that's useful to me.

## Accepted Limitations

Right now, no other agents; later, we can make new routes from logs -> intermediate.
Right now, it doesn't run on any conversation that isn't in the examples directory. Later we'll give it ways to pull from whatever's available in .claude
This doesn't need to run on anyone else's computer, but I do like to document assumptions and prerequisites.
