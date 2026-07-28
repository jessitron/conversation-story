# Session 19 — what the log *cannot* tell you, and the content hiding in the hooks

This started as an off-topic experiment: another session's agent reported it had
been told *"Do not call the AgentTool unless the user requested it"* and *"Do not
use workflows or deep-research unless the user requested it."* Jess asked whether
this session had the same instruction (it does), where it comes from, and then
the question that actually matters here: **does it ever get written to the log?**

It does not. Neither does any other part of the system prompt. That's a limit on
what this project can ever show, so it's worth writing down — along with the
thing we found while looking, which is that some genuinely interesting content
*is* in the log and we're currently rendering it as blank cards.

## The system prompt is not in the log

Grepping every log in `~/.claude/projects` for `Do not call the AgentTool`
matched exactly two files — the session that reported it and this one, i.e. the
two sessions that *talked about* it. In the other session the lone hit is
`message.content[0].text`: the agent's own prose. In this one all 13 hits are my
prose, my `Bash` commands, or the **stdout of my own greps**.

That is the self-referential-fixture trap from session 16 again, and it is worth
naming as a recurring hazard: *in this project, investigating a string puts that
string in the log.* Any grep for prompt text has to check which field matched
before it means anything. `scratchpad/inspect-hits.rb` in that session walked
each record and reported the dotted path of the matching field, which is what
made the answer unambiguous.

Against the five `examples/*.jsonl` fixtures, cleanly: **zero** hits for the
instruction, zero for `You are Claude Code, Anthropic's official CLI`, zero for
the security paragraph, zero for `Codebase and user instructions are shown
below`.

A record-type survey confirms there's nowhere it could hide. This session's log
holds 11 types, and the only `system` records are `subtype: turn_duration`
timing:

```
assistant/assistant 82   user/user 42   attachment 12   last-prompt 10
mode 10   permission-mode 10   ai-title 9   file-history-snapshot 4
system 2 (turn_duration)   queue-operation 2   file-history-delta 2
```

**The dividing line is the conversation channel.** Anything delivered as a turn
is logged — prompts, assistant messages, tool calls and results, and
`attachment` records. Anything baked into the system prompt is invisible.

**CLAUDE.md lands on the invisible side**, which is the sharpest way to say it:
`"I am so happy to be working with you"` — the first line of Jess's global
CLAUDE.md — appears **0 times** in this session's log. It reaches the agent
through the system prompt's `claudeMd` block, not as an attachment. A story page
can never show that Jess's instructions were in play at all.

There's a pointed asymmetry in that. `agent_listing_delta` *is* logged, so a
story can show that the agent was told which subagents exist — but not the
instruction telling it not to use them. **The reader sees the capability and
never the constraint.** If Jess narrates "why didn't it delegate here?", the log
has no answer in it; the answer was in a prompt no log retains. Worth saying out
loud during a talk, because a page that looks this complete implies otherwise.

### Where the instruction actually comes from (aside)

Not from any local config — not `~/.claude/settings.json`, not either
`CLAUDE.md`, not the project's `.claude/`, not env, not managed settings. It's
**hardcoded in the Claude Code binary and gated on the model**:

```js
// two string constants, joined
["Do not call the AgentTool unless the user requested it",
 "Do not use workflows or deep-research unless the user requested it"].join("\n")

// used as the fallback of a remote-config string
let r = Ke("tengu_heron_brook", "")
if (r.trim() !== "") return r          // server-side override wins
if (tXn(e)) return <the two lines>     // else the hardcoded pair
return null

function tXn(e) {                      // e is the model
  if (e === undefined) return false
  if (LN(model(e), "opus_5_prompt_bundle") !== true) return false
  return !Ke("tengu_fennel_godwit", false)   // remote kill-switch
}
```

`claude-opus-5` carries `opus_5_prompt_bundle` in its capability list. So it's
**model-gated, not effort-gated** — the medium-effort session and this
high-effort one get identical text. Two consequences: the wording can change
server-side without a binary update, and it could differ between Jess's machines.
Variable names are minifier output and the control flow is read from a stripped
257 MB bundle; the two literals, the capability gate and the `tengu_heron_brook`
override are directly visible and solid.

## The find: `hook_additional_context` is real content, and its siblings are blank cards

Chasing "what *is* logged" turned up the attachment subtypes, and here the
project has an actual defect.

Hook output arrives as a **pair**, mirroring the `tool_call` / `tool_result`
shape:

- **`hook_success`** — the mechanism. `command`, `exitCode`, `durationMs`,
  `stderr`, and a `stdout` holding the raw JSON envelope. Already in
  `HIDDEN_ATTACHMENT_TYPES`, correctly: it's plumbing.
- **`hook_additional_context`** — *what landed in the conversation.* A `content`
  array of text blocks holding the injected text itself. Not hidden, and
  `attachment_detail_text` reads `content`, so **this one already works**:
  `mode-switches:5` has `detail_len=3276` — the whole SessionStart superpowers
  injection, on the page today.

That's the card Jess wants to show. It's the one place the log reveals
instructions the agent was operating under.

The problem is its neighbours. `attachment_detail_text` only knows `prompt` and
`content`; every other visible subtype stores its payload under different keys
and therefore renders an **empty detail pane under a raw-subtype summary**.
Measured on the shipped `out/mode-switches/story.yaml`:

| ref | subtype | detail_len |
|---|---|---|
| `mode-switches:5` | `hook_additional_context` | **3276** ✅ |
| `mode-switches:9` | `agent_listing_delta` | 0 (payload in `addedLines`) |
| `:104` `:137` `:301` `:331` | `edited_text_file` | 0 ×4 (payload in `filename` + `snippet`) |
| `:183` `:387` | `plan_mode_exit` | 0 (`planFilePath`, `planExists`) |
| `:375` | `plan_mode` | 0 (`planFilePath`, `reminderType`, …) |

**Eight visible cards on one page whose summary is a machine subtype string and
whose body is empty.** `mtg-tabletop-plan` adds `command_permissions`
(`allowedTools`).

And the hidden list is *inverted* on one pair: `skill_listing` is hidden despite
carrying `detail_len=8185` of real content, while `agent_listing_delta` is
visible with nothing to show. Whatever we decide, those two should be decided
together.

`edited_text_file` deserves its own thought — it fires when Jess edits a file
mid-session (it fired 4× in `mode-switches`, and once in *this* session when
Jess edited `CLAUDE.md` while I was working). "Jess changed the instructions
underneath me" is a real story beat, and it currently shows as a blank card.

Follow-up is in `TODO.md` under Mount Complete.

## Reusable scripts

Three throwaway-but-useful scripts, left in the session scratchpad rather than
committed (they're log-forensics tools, not part of the build):

- `inspect-hits.rb <needle> <log…>` — every record containing a string, with the
  **dotted field path** that matched. The antidote to self-referential greps.
- `survey-types.rb <log>` — record-type census plus attachment-subtype counts.
- `show-attachments.rb <log> [subtype]` — every attachment's keys and a preview
  of each field. This is what exposed the missing-`content` problem.

If log spelunking keeps recurring, `survey-types.rb` is the one worth promoting
to `bin/`.

## Loose thread

This log carries **both** a `mode` type (10 records) and a `permission-mode`
type (10). `parser.rb:25` and `:259` already know both lie about the mode a
prompt was sent in, so session 16's finding stands — but the pairing hadn't been
noticed as two distinct record types and may be worth a look.
