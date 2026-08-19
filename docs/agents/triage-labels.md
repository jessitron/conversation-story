# Triage Labels

The skills speak in terms of five canonical triage roles, plus one this repo adds. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| --------------------------- | --------------------- | ----------------------------------------- |
| `needs-triage`               | `needs-triage`         | Maintainer needs to evaluate this issue   |
| `needs-info`                 | `needs-info`           | Waiting on reporter for more information  |
| `ready-for-agent`            | `ready-for-agent`      | Fully specified, ready for an AFK agent   |
| `ready-for-human`            | `ready-for-human`      | Requires human implementation             |
| `wontfix`                    | `wontfix`              | Will not be actioned                      |
| _(none — local addition)_    | `done`                 | Actioned and finished; no longer open     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

## `done` is ours, not the skills'

The five canonical roles are all *open* states — they say what an issue is waiting
on. They assume a tracker with its own notion of closed (GitHub closes an issue;
the label vocabulary never has to). This repo's tracker is markdown files under
`.scratch/`, where nothing closes on its own, so a finished issue would sit in
`ready-for-agent` forever and keep showing up on the frontier.

`done` is the closed state: set `Status: done` when the work is actually shipped.
`/wayfinder` uses `resolved` for its own child tickets — that's the same idea in
the wayfinding vocabulary, and the two don't need merging. No skill will ever ask
for `done` by name, so applying it is a judgement call at the end of the work,
not something a skill instructs.

Edit the right-hand column to match whatever vocabulary you actually use.
