# Installing skills for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed

## Installation

Add `skills` to the `plugin` array in your `opencode.json` (global or
project-level):

```json
{
  "plugin": ["skills@git+https://github.com/openbridge/skills.git"]
}
```

Restart OpenCode. The plugin installs through OpenCode's plugin manager and
registers the skills directory — no symlinks, no `skills.paths` edit.

Verify by asking: "What skills do you have available?"

OpenCode uses its own plugin install. If you also use Claude Code, Codex, or
another harness, install skills separately for each one.

To pin a version:

```json
{
  "plugin": ["skills@git+https://github.com/openbridge/skills.git#v0.1.0"]
}
```

## Updating

OpenCode installs through a git-backed package spec, and some OpenCode and Bun
versions pin that resolved git dependency in a lockfile or cache. A restart may
not pick up the newest commit. If updates don't appear, clear OpenCode's package
cache or reinstall the plugin.

## Troubleshooting

### Plugin not loading

1. Check the logs: `opencode run --print-logs "hello" 2>&1 | grep -i skills`
2. Verify the plugin line in your `opencode.json`
3. Confirm you're on a recent OpenCode build

### Skills not found

1. Use the `skill` tool to list what was discovered
2. Check that the plugin is loading (above) — skill registration happens in the
   plugin's `config` hook, so a plugin that didn't load registers nothing

### Windows install issues

Some Windows OpenCode builds have upstream installer problems with git-backed
plugin specs — cache paths for `git+https` URLs, and Bun failing to find
`git.exe` even when it works in a normal terminal. If OpenCode can't install the
plugin, install with system npm and point OpenCode at the local package:

```powershell
npm install skills@git+https://github.com/openbridge/skills.git --prefix "$HOME\.config\opencode"
```

Then reference the installed path in `opencode.json`:

```json
{
  "plugin": ["~/.config/opencode/node_modules/skills"]
}
```

## Tool mapping

Skills name actions, not tools. On OpenCode those actions resolve to:

| Action a skill requests | OpenCode tool |
|---|---|
| Invoke a skill | native `skill` tool |
| Track tasks ("create a todo", "mark complete") | `todowrite` |
| Dispatch a subagent | `task` with `subagent_type: "general"` (or `"explore"` for read-only exploration) |
| Read a file | `read` |
| Create, edit, or delete a file | `apply_patch` |
| Run a shell command | `bash` |
| Search file contents / find files by name | `grep`, `glob` |
| Fetch a URL | `webfetch` |

This same mapping is injected into the session bootstrap by
`.opencode/plugins/skills.js`, so the agent has it without reading this file.
