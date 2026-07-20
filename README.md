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

We're building this app in Ruby. Each phase of the pipeline is a **rake task**:
parse (Input Logs -> Intermediate), render (Intermediate -> Output HTML), and serve.

## Running it

Ruby only (see `.ruby-version`); the pipeline uses stdlib (`json`, `yaml`, `erb`)
and rake, which ships with Ruby. The one dev dependency is `minitest`.

```sh
rake -T        # list all tasks
rake parse     # examples/*.jsonl  -> out/<name>/story.yaml   (intermediate YAML)
rake render    # out/*/story.yaml  -> out/<name>/index.html   (the page)
rake build     # parse then render
rake serve     # serve out/ at http://localhost:8080
rake test      # golden-fixture tests
```

**Default is all examples.** Override for a single one with env vars:

```sh
LOG=examples/episode-8-before.jsonl rake parse   # parse just this log
NAME=episode-8-before rake render                # render just this story
PORT=9000 rake serve                             # serve on a different port
```

The intermediate `out/<name>/story.yaml` is meant to be hand-editable — tweak it
and re-run `rake render` to see the change.

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
