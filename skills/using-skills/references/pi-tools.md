# Pi Tool Mapping

Skills speak in actions ("invoke a skill", "dispatch a subagent", "read a file").
On Pi those actions resolve to the tools below.

| Action a skill requests | Pi equivalent |
|---|---|
| Read a file | `read` |
| Create a file | `write` |
| Edit a file | `edit` |
| Run a shell command | `bash` |
| Search file contents | `grep` (optional — may not be installed) |
| Find files by name | `find` (optional) |
| List a directory | `ls` (optional) |
| Invoke a skill | **no skill tool** — see below |
| Dispatch a subagent | **no standard tool** — see below |
| Track tasks | **no standard tool** — see below |

Pi's built-in tools are lowercase. Do not reach for `Read`, `Write`, `Bash`.

## Invoking a skill

Pi has native skill *discovery* but does not expose Claude Code's `Skill` tool.
There is nothing to call. When a skill says to invoke another skill:

- `read` that skill's `SKILL.md` directly, or
- let your human partner invoke `/skill:name` explicitly.

The extension registers this collection's skills directory through
`resources_discover`, so the files are discoverable — reading one is the
sanctioned path, not a workaround.

## Subagent dispatch

Pi ships no standard subagent tool. If one is installed — `subagent` from
`pi-subagents`, for example — use it when a skill says to dispatch a subagent.

If none is available, either do the work inline in this session or tell your
human partner the capability is missing. **Never invent a `Task` call.** A
hallucinated dispatch looks like delegated work that silently never happened.

## Task tracking

Pi ships no standard task-list tool. If an installed todo tool is available, use
it. Otherwise keep the checklist in a plan file or a repo-local `TODO.md`, and
update it as you go — a skill that says "track each item as a task" wants the
tracking to exist somewhere durable, not the specific tool.
