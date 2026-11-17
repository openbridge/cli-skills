# Antigravity CLI (`agy`) Tool Mapping

Skills speak in actions ("dispatch a subagent", "create a todo", "read a file").
On the Antigravity CLI (`agy`) those actions resolve to the tools below.

| Action a skill requests | Antigravity CLI equivalent |
|---|---|
| Write a file | `write_to_file` |
| Edit a file | `replace_file_content`, or `multi_replace_file_content` for several edits at once |
| Dispatch a subagent | `invoke_subagent` with a built-in `TypeName` — `self` for full-capability work, `research` for read-only |
| Track tasks ("create a todo", "mark it complete") | a **task artifact** — see below. **Not** `manage_task`. |

## Task tracking

Antigravity has **no todo tool**. `manage_task` looks like one and is not: it
manages background processes (`list` / `kill` / `status` / `send_input`). Reaching
for it when a skill says "track each item as a task" produces nothing resembling a
checklist.

Instead, maintain a **task artifact** — a markdown checklist saved with
`write_to_file` using:

- `IsArtifact: true`
- `ArtifactMetadata.ArtifactType: "task"`

Edit it with `replace_file_content` / `multi_replace_file_content` as you go.

At the start of any multi-step task, create the task artifact listing every step of
your plan. Mark each step done (`- [x]`) as you complete it, and update the list
when the plan changes. It is your source of truth for what remains — once the
conversation gets long, re-read it before starting each step.

## Read-only subagents

`invoke_subagent` with `TypeName: research` has no command access. If a skill asks
a subagent to run something and verify the output, either dispatch it as `self`, or
have the `research` subagent name the command it would run and report that instead
of pretending to have run it.
