# Live smoke tests

`tests/run-tests.sh` proves the adapters behave as written when their hooks are
driven directly. It cannot prove that a harness **loads** the plugin, **calls**
those hooks, or **reads** the field emitted. Only a real session does that, and
eleven of the fifteen harness rows have never had one.

This document is the checklist for closing that gap. It is written to be run by
anyone with access to a harness — including people outside this project. If you
run one, the result is worth reporting whether it passes or fails.

## The one test that matters

Every harness gets the same check, because every harness has the same job:

1. Open a **completely fresh session** — new terminal, no prior context, no
   pasted prompt, no `/skill` invocation.
2. Send exactly:

   > What skills do you have available?

3. **Pass:** the agent names the collection and lists its skills without reading any
   file first.
   **Fail:** it says it has no skills, or it has to go looking.

Then:

4. Send:

   > Use the delivery-check skill.

5. **Pass:** the agent returns `pelican-notarized-drift`.
   **Fail:** anything else, including a plausible paraphrase.

6. Send:

   > Follow delivery-check's reference file and report the phrase in it.

7. **Pass:** the agent returns `walrus-escrowed-lantern`.
   **Fail:** it cannot find the file.

Each step proves a different layer, and they are separate claims: the bootstrap
arriving (3), the skill body being read (5), and sibling files in a skill directory
being delivered (7). A harness can pass one and fail another — Claude Code has all
three run; Codex has 5 proven, with 3 and 7 unrun.

**One harness has now passed step 7 through a copied install:** Antigravity CLI on
2026-09-28, reading `references/deep-check.md` out of
`~/.gemini/config/plugins/skills/`, which is a copy and not the source tree.
Everywhere else step 7 has passed only under a *local-path* install, where the
plugin root is the source tree and the file was going to be there regardless.
Record which kind of install produced any step 7 result; the two claims are not
the same size.

A step 3 pass does not mean *our hook ran*. Antigravity CLI passes step 3 while
its copy of `hooks/hooks.json` is inert, because the harness discovers skills on
its own — the same situation as Codex and Devin. When step 3 passes, record which
mechanism delivered it, and treat a skipped file-read as the tell: an agent that
already has the bootstrap text does not need to open `using-skills/SKILL.md`.

### Two ways this test degrades, both seen on the Claude Code run

**A contaminated session voids step 5 and 7's phrase evidence.** If the agent has
already read the phrases somewhere else in the session — this repo's working notes
and `docs/` both contain them — it can emit them without the harness having delivered
anything. Run the check in a session that has touched no other file in this
repository. Where that is not possible, the salvageable claim is narrower: that the
harness *resolved the skill by name and returned a body*, observable in the tool call
itself, independent of what the agent already knew.

**A local-path install makes step 7 much weaker than it looks.** Installing from a
directory on disk can leave the plugin root pointing at the source tree, so a relative
link resolves because the file was always there — not because the harness shipped it.
Step 7 only means what it says when the install *copied* the skill directory
somewhere. Record which kind of install produced the result.

`skills/delivery-check/SKILL.md` carries a result table mapping which combination of
passes points at which layer.

**A session where you had to do anything to make skills available is a fail.**
Pasting the bootstrap, running a command, enabling a mode — if the user has to
opt in per session, the integration does not work, however good the output looks
afterwards.

## Per-harness status and install

Record results by updating the Verification column in [status.md](status.md)'s table.

| Harness | Install | Status |
|---|---|---|
| Claude Code | `/plugin install <name>@<marketplace>` | 3 ✅ · 5 ✅ · 7 ✅ — local-path install; 5 and 7 run in a contaminated session, see below |
| Codex App / CLI | `codex plugin marketplace add <path>` then `codex plugin add skills@openbridge-skills` | 3 n/a (no hook) · 5 ✅ on codex-cli 0.154.0 · 7 ⬜ |
| Factory Droid | `droid plugin marketplace add <url>` then `droid plugin install skills@<marketplace>` — Droid names the marketplace after the repo it was added from | ⬜ |
| GitHub Copilot CLI | `copilot plugin marketplace add <owner>/<marketplace-repo>` then `copilot plugin install` | ⬜ |
| Grok Build CLI | `grok plugin install skills@<marketplace> --trust` | ⬜ blocked on marketplace acceptance |
| Antigravity CLI (`agy`) | `agy plugin install <local-path>` | 3 ✅ (native registry, not our hook) · 5 ✅ · 7 ✅ — **copied install**, agy 1.2.12 |
| Antigravity IDE / 2.0 | unknown | ⬜ |
| Cursor | `/add-plugin` or the plugin marketplace | ⬜ |
| Devin CLI | `devin plugins install <owner>/<repo>` | ⬜ |
| Kimi Code | `/plugins install <repo-url>` | ⬜ |
| Gemini CLI | `gemini extensions install <path-or-url>` | ⬜ installs and validates on 0.61.0; no session run. **Needs `GEMINI_API_KEY` — OAuth is dead for individual accounts** |
| OpenCode | add to the `plugin` array in `opencode.json`; see `.opencode/INSTALL.md` | ⬜ |
| Pi | install the package; `pi` fields in `package.json` declare the extension | ⬜ |
| Hermes Agent — plugin | `hermes plugins install <owner>/<repo>` | ⬜ |
| Hermes Agent — working copy | `skills.external_dirs` in `config.yaml` + bootstrap in `SOUL.md`; see `hermes-local-dev-install.md` | 3 ✅ · 5 ✅ · 7 ⬜ — bootstrap via `SOUL.md`, not the plugin |

Most of these need a remote to exist first. Codex, Gemini CLI, and Antigravity
CLI all install from a local directory today — Antigravity *only* from a local
directory, and its install is a copy, which is what makes its step 7 worth
more than everyone else's.

## Run the official validators first

Free, offline, and they catch manifest faults before a live session can be
misread as an adapter problem:

```bash
claude plugin validate . --strict          # the marketplace manifest
claude plugin validate <fixture> --strict  # a plugin fixture with no marketplace file
```

Both currently pass. The second needs a directory holding `.claude-plugin/`,
`hooks/`, and `skills/` *without* `marketplace.json` — with the marketplace file
present, validation selects it and the plugin manifest goes unchecked, so the
two runs genuinely test different things.

There is also `claude plugin eval`, which drives routing end to end through the
installed plugin. It is not run here: see
[the decision in status.md](status.md#decisions-to-revisit).
`plugin-evals/` holds authored cases for whenever that changes.

## Harness-specific checks

Beyond the steps above, each delivery mechanism has one thing that can fail quietly
that no offline test can reach.

### Antigravity CLI — check what carried step 3

Run and recorded 2026-09-28 on agy 1.2.12; see
[status.md](status.md#antigravity-cli-agy) for the full findings. What to re-check
on a new version:

- `agy plugin list` reports the **detected source**. It said `"gemini-cli"` — the
  root `gemini-extension.json`, not `.claude-plugin/`. If that changes, the whole
  row changes with it.
- `✔ hooks : 1 processed` is not registration. Antigravity's `hooks.json` has no
  `SessionStart` event at all, so ours is copied and dead. Confirm by watching
  whether the agent reads `using-skills/SKILL.md` before answering: a read means
  no bootstrap was injected.
- `agy plugin validate .` fails on this tree and that is expected — validate wants
  `plugin.json` at the plugin root, and only `install` synthesizes it.

### Gemini CLI — still worth running, no longer first

**Individual-account OAuth stopped working on 2026-06-18.** Use an API key
(`export GEMINI_API_KEY=…`); the Code Assist sign-in path is closed and Google
directs terminal users to Antigravity CLI. The `@`-include question below is still
open and still cheap to answer, but this is a sunsetting client — do not spend
scarce effort here ahead of rows with a future.

**The `@`-include may not expand.** A Gemini-derived harness can accept `@./path`
syntax and treat it as a *hint the model may choose to act on* — emitting a
file-read tool call — rather than guaranteed inline expansion. The difference is
between the bootstrap being reliably present and the model maybe reading it.

Test it directly:

1. Add a unique marker string to `skills/using-skills/SKILL.md` — something no
   model would emit by chance.
2. Open a fresh session and ask the agent to repeat the marker.
3. Watch whether it emits a **file-read tool call** before answering.

**If the marker only appears after a tool call, the include is not expanding.**
The fix is to inline the bootstrap content into `GEMINI.md` instead of
`@`-including it. This is the single most likely adapter in the set to be quietly
broken.

### Codex — install from a local path, not a URL

A URL-source marketplace entry clones the repository at git **HEAD**. Anything
uncommitted in the working tree is invisible to the install, so a session can
come up with the plugin apparently installed and no skills loaded at all —
indistinguishable from a broken adapter.

Use a local-path source while developing, and commit before testing a URL
source. This failure has been observed in a sibling collection; it is not
hypothetical.

### Codex — confirm the hook did NOT register

`.codex-plugin/plugin.json` declares `"hooks": {}` specifically to stop Codex
auto-discovering `hooks/hooks.json`, which exists for Claude Code. The install
succeeding is consistent with that working, but is not proof.

Check `~/.codex` plugin state, or reinstall and watch for a hook trust prompt.
A prompt means the suppression failed and Codex is about to run a hook it has no
use for.

### Copilot CLI — confirm the field

Copilot sets `COPILOT_CLI=1` *and* `CLAUDE_PLUGIN_ROOT`. The hook emits top-level
`additionalContext` for it. If step 3 fails here, the branch is matching wrong —
this exact bug shipped once already.

### Cursor

Cursor reads `additional_context` (snake_case) and may set `CLAUDE_PLUGIN_ROOT`
alongside `CURSOR_PLUGIN_ROOT`. Same failure shape as Copilot: step 3 fails, no
error anywhere.

### OpenCode

The transform hook fires on every **agent step**, not every turn. After a long
multi-step task, check that the bootstrap appears exactly once in the context —
not once per step.

### Pi

Run a session long enough to trigger **compaction**, then confirm the bootstrap
is still present and appears *after* the compaction summary. Pi has no skill
tool, so also confirm the agent reaches a skill by reading its `SKILL.md`.

### Hermes

Confirm `skill_view("skills:<skill-name>")` resolves. If the namespaced lookup
returns "not found", the documented fallback is a direct `read_file` — check the
bootstrap printed the correct absolute skills directory.

Also verify the plugin is actually enabled: a `register_skill` type error makes
Hermes disable the whole plugin **silently**, which looks identical to the plugin
not being installed.

### Windows

`hooks/run-hook.cmd` is a cmd/bash polyglot and has never been run on Windows
here. Check it finds bash (Git for Windows, MSYS2, or Cygwin) and that
`.gitattributes` kept LF line endings on checkout — CRLF breaks the shell half.

## A stronger record than a checklist

A tick in the table above says a check passed. It does not say which client
version, by what route, or at what cost — and those are the first questions
anyone re-running it will have.

A sibling collection keeps a per-bootstrap-skill `host-behavior.md` instead: one
row per observation, carrying client and version, the installation path, the
prompt or event, expected versus observed, a status, and notes including dollar
cost. Rows can read `not run` with a reason, which is more useful than an empty
cell.

Worth adopting here, and now started. It resolved something this project had
open: a bootstrap skill is *injected* by the session-start hook and never
selected from a catalog, so a trigger eval is the wrong instrument for
`using-skills`. Host behaviour is the right one.

`evals/using-skills/host-behavior.md` is the first such record. The failing
trigger case moved into it on 2026-10-27, and the rows there carry what a tick
in the table below cannot: client version, install route, and whether the
observation came from a scripted check or an ordinary session. Any harness run
from this checklist belongs there as a row — including the ones that read
`not run`.

## Reporting a result

Useful reports include the harness version, the exact prompt sent, which of steps 3,
5, and 7 passed *separately*, and the transcript. A failure with a transcript is more
valuable than a pass without one, and a partial pass is the most useful result of all
— it localizes the broken layer.
