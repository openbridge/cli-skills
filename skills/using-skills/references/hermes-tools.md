# Hermes Agent Tool Mapping

Skills speak in actions ("dispatch a subagent", "create a todo", "read a file").
On Hermes Agent those actions resolve to the tools below.

| Action a skill requests | Hermes tool |
|---|---|
| Read a file | `read_file` |
| Create a new file | `write_file` |
| Edit a file (targeted patch) | `patch` |
| Run a shell command | `terminal` |
| Search file contents | `search_files` |
| Find files by name | `terminal` with `find` |
| Fetch a URL / read a webpage | `web_extract(urls=[...])` |
| Search the web | `web_search(query=...)` |
| Dispatch a subagent | `delegate_task(goal=..., context=..., toolsets=[...], role="leaf")` |
| Track tasks | `todo` tool |
| Invoke a skill | `skill_view("skill-name")` |

## Invoking a skill

Hermes has a `skills` toolset with `skill_view` and `skills_list`. How a skill is
named depends on how the collection was installed, so check rather than guess:

```
skills_list
skill_view("delivery-check")            # registered via skills.external_dirs
skill_view("skills:delivery-check")  # registered by the plugin
```

`skills_list` shows the names that actually resolve. Use those.

If neither form is found, fall back to reading the file directly. The session
bootstrap prints the resolved absolute skills directory — use that path:

```
read_file(path="<skills-dir-from-the-bootstrap>/<skill-name>/SKILL.md")
```

A successful `read_file` where `skill_view` failed means delivery is fine and
only registration is broken. Say so rather than reporting the skill as missing.

## Subagent dispatch

Use `delegate_task` for isolated subagents:

```
delegate_task(goal="...", context="...", toolsets=[...], role="leaf")
```

If `delegate_task` is unavailable, do the work inline rather than inventing tool
calls.

## Task tracking

Use the `todo` tool within a session. For multi-agent task boards, the
`hermes kanban` CLI is available if installed.

## Instructions file

When a skill mentions "your instructions file," on Hermes that is **`AGENTS.md`**
in the project directory, or **`SOUL.md`** in Hermes' data directory (`~/.hermes`
by default; a different path when Hermes runs in a container).
