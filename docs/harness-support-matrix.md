# Harness Support Matrix

What it actually costs to support each AI coding agent, sorted by whose plugin
format it eats.

Derived from the `superpowers` checkout in this repo — **v6.3.0, dated
2026-09-16**. Harness plugin formats churn; re-verify against upstream before
committing to any row.

---

## The one-paragraph version

There is no such thing as "16 integrations." There is **one dominant format**
(Claude Code's `.claude-plugin/` + `skills/` + `hooks/`) that five harnesses
consume with zero repo-side work, **four near-clones** that need a ~20-line
manifest each, and **four genuinely different runtimes** that need real code.
Two names on the list have no upstream implementation at all.

The cost is not evenly distributed. Roughly: 5 harnesses for free, 4 for an hour
each, 4 for a day each, 2 unknown.

---

## Bucket 1 — Eats the Claude Code plugin format

These read `.claude-plugin/plugin.json`, auto-discover the sibling `skills/`
directory, and run `hooks/hooks.json`'s `SessionStart` hook. **They require zero
new config files in your repo.**

| Harness | Install command | Repo files needed | Notes |
|---|---|---|---|
| **Claude Code** | `/plugin install <name>@<marketplace>` | — (native) | Native `Skill` tool. No tool mapping needed. |
| **Factory Droid** | `droid plugin marketplace add <repo-url>`<br>`droid plugin install <name>@<name>` | **none** | Consumes the Claude Code plugin as-is. Upstream's own porting guide calls this out: *"A port that adds nothing to this repo but a paragraph in the README is a perfectly good outcome."* |
| **GitHub Copilot CLI** | `copilot plugin marketplace add <owner>/<marketplace-repo>`<br>`copilot plugin install <name>@<marketplace>` | **none** | One caveat, see below. |
| **Grok Build CLI** | `grok plugin install <name>@xai-official --trust` | **none** | Distribution-only. Install path resolves to *xAI's* official marketplace repo. |
*(Antigravity was listed in this bucket until 2026-09-28. A live run showed it
does not belong here — it matches `gemini-extension.json`, not `.claude-plugin/`,
and has no `SessionStart` hook event. It is now in Bucket 3 below.)*

### The Copilot CLI caveat

Same files, but the session-start hook must emit a **different JSON shape**.
`hooks/session-start` already branches three ways:

```bash
if [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
  printf '{\n  "additional_context": "%s"\n}\n' "$session_context"           # Cursor (snake_case)
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -z "${COPILOT_CLI:-}" ]; then
  printf '{\n  "hookSpecificOutput": { ... "additionalContext": "%s" }\n}\n'  # Claude Code (nested)
else
  printf '{\n  "additionalContext": "%s"\n}\n' "$session_context"            # Copilot CLI + SDK standard
fi
```

Copilot CLI sets `COPILOT_CLI=1` and reads top-level `additionalContext`. Claude
Code reads **both** `additional_context` and `hookSpecificOutput` *without
deduplicating*, so emitting both double-injects. Get the branch wrong and you
get silent failure or a doubled bootstrap.

**Bucket 1 total cost: 1 hook branch you already have.**

The real work for this bucket is **distribution, not code** — each of these
resolves to a vendor-controlled marketplace you must submit to:

| Harness | Marketplace you must get into |
|---|---|
| Claude Code | Anthropic's official marketplace, or your own `<name>-marketplace` repo |
| Factory Droid | your own repo (`droid plugin marketplace add <url>`) |
| Copilot CLI | your own marketplace repo |
| Grok Build CLI | `xai-org/plugin-marketplace` — **approval you don't control** |

---

## Bucket 2 — Eats a Claude-derived format (own manifest, shared skills + hook)

Near-clones. Same `skills/` tree, same (or no) hook script, but each wants its
own manifest directory with a few harness-specific fields.

| Harness | Manifest | Bootstrap mechanism | Tool mapping | Distinctive fields |
|---|---|---|---|---|
| **Cursor** | `.cursor-plugin/plugin.json` + `hooks/hooks-cursor.json` | shell hook → `additional_context` | none (Claude-compatible tools) | Must declare `"skills": "./skills/"` and `"hooks": "./hooks/hooks-cursor.json"` explicitly — no auto-discovery. Hook config key is `sessionStart` (camelCase) with `"version": 1`, not Claude's `SessionStart` matcher block. |
| **Devin CLI** | `.devin-plugin/plugin.json` | **none** — Devin surfaces every installed skill's name + description in its own system prompt | none | Plainest manifest in the set. No `skills` field, no `hooks` field; auto-discovers `skills/`. Its system prompt already documents subagent profiles, todos, and question prompts. |
| **Codex App**<br>**Codex CLI** | `.codex-plugin/plugin.json` (shared — one dir serves both) | **none** — native skill discovery | `references/codex-tools.md` | `"hooks": {}` — an *empty object on purpose*, to suppress Codex's `hooks/hooks.json` auto-discovery. Plus a large `interface` block (displayName, brandColor, logo, privacyPolicyURL, defaultPrompt) for app-store listing. |
| **Kimi Code** | `.kimi-plugin/plugin.json` | `"sessionStart": { "skill": "using-skills" }` — declarative, no hook script | inline `skillInstructions` string in the manifest | Tool mapping lives *in the manifest*, not a separate file. ~1.5KB of prose mapping `AskUserQuestion`, `TodoList`, `Agent` + `subagent_type: "coder"/"explore"/"plan"`, `FetchURL`. |

**Do not copy `.codex-plugin/plugin.json` as your Cursor template.** The empty
`hooks: {}` means the opposite of what Cursor needs. Upstream's porting guide
flags this explicitly.

**Bucket 2 total cost: 4 manifests (~20–60 lines each), 1 extra hook config
(Cursor), 2 tool mappings (Codex file, Kimi inline).**

---

## Bucket 3 — Needs its own format (real code)

Different runtime model entirely. These are the ones that cost real engineering
and real maintenance.

The **Upstream entry point** column names the file as `superpowers` v6.3.0 ships
it. This collection ships the same files under its own name —
`.opencode/plugins/skills.js`, `.pi/extensions/skills.ts` — because the
filename carries the collection's identity and `scripts/identity.sh rename`
rewrites it. Do not "correct" the upstream column to the local names; the point
of the column is what upstream has.

| Harness | Upstream entry point | Language | Mechanism | Tool mapping |
|---|---|---|---|---|
| **Gemini CLI** | `gemini-extension.json` + `GEMINI.md` | — (declarative) | `contextFileName` points at a `GEMINI.md` the extension ships; that file `@`-includes the bootstrap skill and the tool mapping | `references/gemini-tools.md` |
| **Antigravity CLI** (`agy`) | `gemini-extension.json` | — (declarative, by accident) | Detects the Gemini manifest, synthesizes a root `plugin.json`, copies `skills/` into `~/.gemini/config/plugins/`, and discovers them natively. **No bootstrap**: its `hooks.json` has no `SessionStart` event, so ours is copied and inert | `references/antigravity-tools.md` — **unconfirmed against agy 1.2.12** |
| **OpenCode** | `.opencode/plugins/superpowers.js` | JavaScript | In-process. `config` hook registers the skills dir; `experimental.chat.messages.transform` injects the bootstrap as a user message | inline in the `.js` |
| **Pi** | `.pi/extensions/superpowers.ts` | TypeScript | In-process. `resources_discover` registers skills; `context` event injects; lifecycle-flag + compaction-aware | `piToolMapping()` inline **and** `references/pi-tools.md` |
| **Hermes Agent** | `.hermes-plugin/plugin.yaml` + `__init__.py` | Python | In-process. `provides_hooks: [pre_llm_call]` | `references/hermes-tools.md` |

### What makes each expensive

**Gemini CLI** is cheap to write, risky to trust. `@./path` includes are *not
guaranteed inline expansion* — a Gemini-derived harness may treat `@` as a hint
the model may choose to act on, emitting a file-read tool call instead. Upstream's
guidance: run a unique-marker test, and if the marker isn't in context *without*
a tool call, inline the content instead of `@`-including it. There are no tests
for Gemini upstream.

**OpenCode and Pi** both declare themselves through the **repo-root
`package.json`** — `main` points at the OpenCode plugin; a `pi` field
(`pi.extensions`, `pi.skills`) plus a `pi-package` keyword declare the Pi
extension. One shared file, two harnesses, easy to break.

**Pi** additionally has **no native skill tool** — the model reaches skills by
plain file-read of `SKILL.md`. It's the reference to copy for any harness in
that shape. It also runs the `.ts` source directly with no build step and no
declared dependency for `import type { ExtensionAPI }`; that works only because
nothing type-checks the file in CI. If your CI does, it breaks.

**Hermes** is the only Python surface. `__init__.py` has to resolve two
different install layouts (git-clone, where `.hermes-plugin/` and `skills/` are
siblings; flattened, where `skills/` is next to the module) and raises loudly
when neither matches — because *a bootstrap that silently skips is how a broken
install masquerades as a working one*. Has real pytest coverage upstream
(`tests/hermes/`).

**Bucket 3 total cost: ~4 real implementations in 3 languages + 3 tool-mapping
files + shared root `package.json` ownership.**

---

## Bucket 4 — No implementation exists

| Harness | Status |
|---|---|
| **Qwen Code** | Not in superpowers v6.3.0. The only occurrence of "Qwen" in the tree is a code comment in `.opencode/plugins/superpowers.js:118` about *"Multiple system messages breaking Qwen and other models (#894)"* — a model bug, not an integration. No manifest, no README section, no tests. |
| **Muse** | Zero occurrences anywhere in the tree. |

Either upstream added them after 2026-09-16, or the list is aspirational. Nothing
to copy today.

---

## The cross-runtime `.agents/` convention

Worth knowing before you design anything: an emerging vendor-neutral standard is
already in play.

- **`~/.agents/skills/`** is recognized as a cross-runtime alias for user-level
  skills by **Codex, Copilot CLI, and Gemini CLI**. When both
  `~/.gemini/skills/` and `~/.agents/skills/` exist at the same scope,
  `.agents/skills/` **takes precedence**.
- **`.agents/plugins/marketplace.json`** is a repo-level marketplace manifest —
  upstream ships one, and it's validated by `tests/codex/test-marketplace-manifest.sh`.

If you're building a base to last, this is the direction to bet on rather than
N vendor dotdirs.

---

## Summary table — all 16

| # | Harness | Bucket | Repo artifacts required |
|---|---|---|---|
| 1 | Claude Code | 1 — Claude format | `.claude-plugin/` + `hooks/` + `skills/` (the base) |
| 2 | Factory Droid | 1 — Claude format | none |
| 3 | GitHub Copilot CLI | 1 — Claude format | none (hook branch already exists) |
| 4 | Grok Build CLI | 1 — Claude format | none |
| 5 | Antigravity CLI (`agy`) | 3 — own format | `gemini-extension.json` (what it detects), `references/antigravity-tools.md` (mapping unconfirmed against agy 1.2.12) |
| 6 | Cursor | 2 — Claude-derived | `.cursor-plugin/plugin.json`, `hooks/hooks-cursor.json` |
| 7 | Devin CLI | 2 — Claude-derived | `.devin-plugin/plugin.json` |
| 8 | Codex App | 2 — Claude-derived | `.codex-plugin/plugin.json`, `references/codex-tools.md` |
| 9 | Codex CLI | 2 — Claude-derived | *(same files as Codex App)* |
| 10 | Kimi Code | 2 — Claude-derived | `.kimi-plugin/plugin.json` (mapping inline) |
| 11 | Gemini CLI | 3 — own format | `gemini-extension.json`, `GEMINI.md`, `references/gemini-tools.md` |
| 12 | OpenCode | 3 — own format | `.opencode/plugins/*.js`, root `package.json` `main` |
| 13 | Pi | 3 — own format | `.pi/extensions/*.ts`, root `package.json` `pi` fields, `references/pi-tools.md` |
| 14 | Hermes Agent | 3 — own format | `.hermes-plugin/plugin.yaml` + `__init__.py`, `references/hermes-tools.md` |
| 15 | Qwen Code | 4 — unknown | nothing upstream |
| 16 | Muse | 4 — unknown | nothing upstream |

**Distinct config surfaces for 14 supportable harnesses: 10.**

---

## What skills has today

| Surface | Status |
|---|---|
| `.claude-plugin/plugin.json` + `marketplace.json` | ✅ present |
| `.codex-plugin/plugin.json` | ✅ present |
| `.agents/plugins/marketplace.json` | ✅ present |
| `hooks/session-start` + `run-hook.cmd` + `hooks.json` | ✅ present |
| `skills/using-skills/SKILL.md` | ✅ present |
| `.cursor-plugin/` + `hooks/hooks-cursor.json` | ✅ present |
| `.devin-plugin/` | ✅ present |
| `.kimi-plugin/` | ✅ present (tool mapping inline) |
| `gemini-extension.json` + `GEMINI.md` | ✅ present |
| `.opencode/plugins/skills.js` + `INSTALL.md` | ✅ present |
| `.pi/extensions/skills.ts` | ✅ present |
| `.hermes-plugin/plugin.yaml` + `__init__.py` | ✅ present |
| root `package.json` | ✅ present (`main` → OpenCode, `pi` fields → Pi) |
| `references/*-tools.md` | ✅ present — antigravity, codex, gemini, hermes, pi |

**All three buckets are complete — 14 of 14 supportable harnesses.** Qwen Code
and Muse remain out of scope; nothing upstream exists to port.

OpenCode's tool mapping is injected by its plugin rather than kept as a
reference file, and Kimi's ships inline in its manifest. Cursor, Devin, Copilot
CLI, Factory Droid, and Claude Code expose Claude Code–compatible tool surfaces
and need no mapping.

Tool mappings are covered for every harness in those buckets that needs one:
`references/antigravity-tools.md` and `references/codex-tools.md` exist and are
linked from `using-skills/SKILL.md`'s Platform Adaptation section. Kimi ships its
mapping inline in its manifest. Cursor, Devin, Copilot CLI, and Factory Droid
expose Claude Code–compatible tool surfaces and need none.

### Beyond delivery: the authoring layer

Everything above is about getting a skill *to* an agent. A collection also has
to be authored, governed, and published, and those surfaces are not
harness-specific at all:

| Surface | Status |
|---|---|
| `.skills-identity.json` + `scripts/identity.sh` | ✅ check / audit / set / rename across every manifest, literal, and filename |
| `catalog/schema.json` + `catalog/entries/*.json` | ✅ governance: classification, origin, maintainers, licence, registries, source |
| `catalog/skills.json` + `scripts/catalog.sh` | ✅ generated from frontmatter + entries; enforces the Agent Skills spec |
| `skills.sh.json` + `scripts/registry.sh` | ✅ the descriptor public skill registries read |
| `templates/` + `scripts/new-skill.sh` | ✅ scaffolds SKILL.md, a governance entry, and trigger cases |
| `evals/<skill>/trigger-cases.json` + `scripts/eval.sh` | ✅ authored; never run (costs money) |
| `plugin-evals/*/case.yaml` | ✅ authored; never run (costs more) |
| `skills-lock.json` | ⬜ not generated — the `skills` CLI writes it, see `docs/publishing.md` |

The format authority for all of this is the
[Agent Skills specification](https://agentskills.io/specification), not this
repository. Where the two disagree the specification wins, and
`scripts/catalog.sh` enforces its constraints directly.

One thing still outstanding, which does not block the code:

- **Distribution.** The manifests exist, but nothing is published. Grok in
  particular requires acceptance into `xai-org/plugin-marketplace`.

---

## Two invariants that hold regardless of harness

From upstream's porting guide, and they're the load-bearing rules:

1. **Skills name actions, not tools.** Skill bodies say "dispatch a subagent",
   "create a todo", "read a file" — never `Task`, never `TodoWrite`. That is the
   entire reason one skills tree runs everywhere. Per-harness work is *only* a
   tool-mapping reference plus a bootstrap injector.

2. **Everything ships through the harness's own install mechanism. Never edit
   the user's files.** No writing to `~/.gemini/config/`, `settings.json`,
   `trustedFolders.json`, or `~/.bashrc`. If the install mechanism can't carry
   the bootstrap, that's a limitation to document — not license to hand-edit.

And the hard gate: **a harness is supportable only if it can inject context at
session start with no per-session opt-in.** If the user has to paste a prompt or
run a command each session, it isn't supported — the skills sit on disk, inert.

---

## Licensing

superpowers is MIT (© 2025 Jesse Vincent). Copying is permitted with no
obligation to contribute back. The license text and copyright notice must ship
with any substantial portion you copy.

Manifests carry no meaningful copyright — they're ~20 lines that are 90%
identity fields you must rewrite anyway. The things worth attributing are the
real code: `hooks/session-start`, `hooks/run-hook.cmd`, the OpenCode/Pi/Hermes
adapters, the tool-mapping references, and upstream's own
`docs/porting-to-a-new-harness.md` (an upstream file — this repo does not ship it).
