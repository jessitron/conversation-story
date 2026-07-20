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

We're building this app in Ruby. There are separate programs for Input Logs -> Intermediate Description, Intermediate -> Output HTML, and serving the HTML.

## North Star

A conversation with an agent is intelligible. I can display it, step through it, drill into it. I can explain what's happening to another person, and they can explore what happened too. Also, it's pretty.

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

