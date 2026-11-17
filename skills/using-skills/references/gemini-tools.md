# Gemini CLI Tool Mapping

Skills speak in actions ("dispatch a subagent", "create a todo", "read a file").
On Gemini CLI those actions resolve to the tools below.

| Action a skill requests | Gemini CLI equivalent |
|---|---|
| Read a file | `read_file` |
| Read several files at once | `read_many_files` |
| Create a new file | `write_file` |
| Edit a file | `replace` |
| Run a shell command | `run_shell_command` |
| Search file contents | `grep_search` |
| Find files by name | `glob` |
| List a directory | `list_directory` |
| Fetch a URL | `web_fetch` |
| Search the web | `google_web_search` |
| Invoke a skill | `activate_skill` |
| Dispatch a subagent | `invoke_agent` with `agent_name: "generalist"` |
| Several dispatches in parallel | multiple `invoke_agent` calls in one response |
| Track tasks ("create a todo", "mark complete") | `write_todos` — statuses: pending, in_progress, completed, cancelled, blocked |
| Ask your human partner a structured question | `ask_user` (text / single-select / multi-select) |

## Subagent dispatch

`invoke_agent` takes `agent_name` and `prompt`. The same dispatch is also
surfaced as chat syntax: typing `@generalist <prompt>` is equivalent to
`invoke_agent` with `agent_name: "generalist"`.

Built-in agent names include `generalist`, `cli_help`, `codebase_investigator`,
and — with browser tooling enabled — `browser_agent`. Use `generalist` unless a
skill names a more specific one.

When a skill provides a prompt template with placeholders, fill every placeholder
before passing the complete prompt to `invoke_agent`. The template carries the
subagent's role and expected output format; it does the work of configuring the
child.

Gemini CLI supports parallel dispatch — issue several `invoke_agent` calls in the
same response for independent work. Keep dependent tasks sequential, but don't
serialize independent ones just to keep a simpler history.

## Instructions file

When a skill mentions "your instructions file," on Gemini CLI that is
**`GEMINI.md`**. Gemini loads it hierarchically: global at `~/.gemini/GEMINI.md`,
project-level files in workspace directories and their ancestors, and
sub-directory `GEMINI.md` files when a tool touches files in those directories.

## Personal skills directory

User-level skills live at **`~/.gemini/skills/`**, with **`~/.agents/skills/`**
as a cross-runtime alias shared with Codex and Copilot CLI. When both exist at
the same scope, `.agents/skills/` takes precedence. Each skill is a subdirectory
containing a `SKILL.md` with `name` and `description` frontmatter.

## Other Gemini CLI tools

| Tool | Purpose |
|---|---|
| `enter_plan_mode` / `exit_plan_mode` | Switch into and out of read-only plan mode |
| `complete_task` | Signal a subagent has finished and return its result to the parent |
| `tracker_create_task`, `tracker_update_task`, `tracker_get_task`, `tracker_list_tasks`, `tracker_add_dependency`, `tracker_visualize` | Task tracker with dependency and visualization support |
| `save_memory` | Persist facts across sessions (legacy; when `experimental.memoryV2 = false`) |
| `get_internal_docs` | Look up Gemini CLI's bundled documentation |
| `read_mcp_resource`, `list_mcp_resources` | MCP resource access |
