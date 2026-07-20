# TODO

## now

- make the HTML in messages display as HTML; but in the summary, make sure it doesn't truncate into something malformed.
- make tool calls look like the tool calls in the prototype
- when I click a tool call, result, or related system notification, the others in that causal chain light up too
- a mode where fewer of the details show
- why does episode-8-before:9 just say "Thinking..." ? That's boring.
- let's add the filename into Tool call: Read summaries
- actually none of the tool calls are showing me their arguments, uncool
- system messages are not from me, don't say they came from Jess.
- in an event like episode-8-before:63, the content contains XML and one of those fields is `<summary>` and that is what we wanna display in the summary
- I need a way to see the connection between queue and dequeue, they need to light up together

## later

- mark an intermediate story.yaml as hand-edited so `rake parse` won't overwrite
  it (e.g. a frontmatter flag or sidecar lock file the parse task checks). Note:
  rake's mtime rule already skips re-parsing when the story is newer than its
  log, but that's not an explicit "leave this alone" signal — we want one.
