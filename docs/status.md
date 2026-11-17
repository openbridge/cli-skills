# Status and Verification

The evidence behind this repository: which harnesses are proven and to what depth,
what the test suite covers, how the generated files are kept honest, and the
harness-by-harness implementation notes.

Start with [README.md](../README.md) if you want to know what this repo *is*.
For the design rationale behind each harness format, see
[harness-support-matrix.md](harness-support-matrix.md).

---

## Status

**Phase 5 — authoring layer.** Thirteen harnesses ship across fifteen rows, in four delivery
mechanisms, with an offline test suite guarding them, and an authoring layer on top:
generated identity, a generated catalog, a scaffold, and trigger evals. The "one source, many
manifests" claim now holds across three different plugin formats rather than being
single-harness by construction. What it does not yet hold against is a live session
on eleven of the fifteen rows those harnesses occupy.

| Harness | Manifest | Bootstrap delivery | Verification |
|---|---|---|---|
| Claude Code | `.claude-plugin/plugin.json` + `hooks/hooks.json` | shell hook → `hooks/session-start` | `claude plugin validate --strict` passes (marketplace + plugin); steps 1–3 verified live, step 3 under a local-path install only |
| Codex App / CLI | `.codex-plugin/plugin.json` (declares empty `hooks`) + `.agents/plugins/marketplace.json` | native skill discovery, no hook | Installed on codex-cli 0.154.0; step 2 verified live |
| Factory Droid | *(none — reads `.claude-plugin/`)* | shell hook | Not run |
| GitHub Copilot CLI | *(none — reads `.claude-plugin/`)* | shell hook, top-level `additionalContext` | Hook branch tested; harness not run |
| Grok Build CLI | *(none — reads `.claude-plugin/`)* | shell hook | Not run |
| Antigravity CLI (`agy`) | *(none — `gemini-extension.json` is what it detects; it synthesizes a root `plugin.json` on install)* | none — native skill discovery; our hook is copied but never registered | Verified live 2026-09-28 on agy 1.2.12, **copied install**: steps 1–3 all pass, step 1 via agy's own skill registry rather than our hook — see [Antigravity CLI](#antigravity-cli-agy) |
| Antigravity IDE / 2.0 | *(unknown — presumed `.claude-plugin/`)* | presumed shell hook | Not run. The CLI result does not transfer: it is a different surface with a different customization root |
| Cursor | `.cursor-plugin/plugin.json` + `hooks/hooks-cursor.json` | shell hook, `additional_context` | Hook branch tested; harness not run |
| Devin CLI | `.devin-plugin/plugin.json` | none — Devin lists skills in its own system prompt | Not run |
| Kimi Code | `.kimi-plugin/plugin.json` | manifest `sessionStart.skill` | Not run |
| Gemini CLI | `gemini-extension.json` + `GEMINI.md` | `contextFileName` → `@`-includes | Includes resolve; harness not run |
| OpenCode | `.opencode/plugins/skills.js` | in-process: `config` + message transform | Hooks executed against a stub; harness not run |
| Pi | `.pi/extensions/skills.ts` | in-process: `resources_discover` + `context` | Lifecycle executed against a stub; harness not run |
| Hermes Agent — plugin | `.hermes-plugin/plugin.yaml` + `__init__.py` | in-process: `pre_llm_call` | `register()` + hook executed against a stub; **this adapter has never been loaded by Hermes** |
| Hermes Agent — working copy | *(none — `skills.external_dirs` in `config.yaml`)* | `SOUL.md`, maintained by hand | Verified live 2026-09-28: skills registered and `enabled`, resolved by bare name, and the bootstrap changed behaviour unprompted — see [hermes-local-dev-install.md](hermes-local-dev-install.md) |

**The rows are verified to very different depths — read the last column before
trusting any of them.**

**On counting.** Fifteen rows for thirteen harnesses: Hermes occupies two,
because its plugin and its working-copy route are separate integrations with
separate evidence, and collapsing them would let the verified one vouch for the
unverified one. Antigravity occupies two for the same reason — the CLI has been
run and the IDE surface has not, and they do not share a customization root.
Earlier drafts reached fourteen by
counting Codex App and Codex CLI separately while the table kept them in one row
whose only evidence is a `codex-cli 0.154.0` install — which let the App read as
verified when nothing has been run against it. The Codex App is untested. If the
two are ever split into separate rows, the App's verification cell starts empty.

Four rows have been run against a real harness — Claude Code, Codex, Antigravity
CLI, and the Hermes working-copy route — and the Codex row covers the CLI only.
Claude Code has all three
steps run: the bootstrap arrived unprompted, the harness resolved and returned the
probe's body, and the relative reference resolved. Codex has step 2 proven — a fresh
session invoked the probe skill and returned its confirmation phrase — and steps 1
and 3 unrun. Antigravity CLI has all three run **from a copied install**, which
makes it the only row whose step 3 means what step 3 is supposed to mean.

The step numbers are `delivery-check`'s: step 1 is *the bootstrap arrived*, step 2 is
*the skill body was read*, step 3 is *relative references resolve*. They are separate
claims because a harness can pass one and fail another.

**Two limits on the Claude Code step 2/3 result, recorded because they narrow what it
proves.** The session that ran it had already read a working-notes file containing both
confirmation phrases, so *the agent emitting the phrases* is not evidence in that run;
what stands is the harness resolving the skill by name and returning its body, which
is the claim step 2 actually makes. And the plugin was installed from a local path, so
the plugin root *was* the source tree — step 3 shows a relative link resolving when
the skill directory is the repo, not that a copied install ships `references/`
alongside `SKILL.md`. A clean-machine install is what closes the second gap, and
it belongs to Phase 6 below. The Antigravity CLI run has since shown a copied
install delivering `references/` correctly — but that is evidence about agy, not
about Claude Code, and it does not retire this item.

The Hermes working-copy row is verified by a different route than the others, and
proves less about this repository's code: it uses no adapter at all. What it
establishes is that the `skills/` tree and `using-skills` work as intended once a
harness is pointed at them — and, separately, that a hand-maintained instructions
file can carry a bootstrap. It says nothing about `.hermes-plugin/`.

Everything else is **code-complete but unproven in situ.** "Executed
against a stub" means the plugin's hooks were driven directly with fabricated
harness input and behaved correctly — OpenCode's transform injects once and does not
stack on repeat passes, Pi's bootstrap lands after compaction summaries, Hermes
registers skills as `pathlib.Path` and injects only on the first turn. That
establishes the code does what it intends. It does **not** establish that the
harness loads the plugin, calls those hooks, or reads the field emitted. Only a live
session does that.

Qwen Code and Muse are out of scope: no upstream integration exists to port.

Planned phases:

1. Skill format + repository structure ✅
2. Session-start hook (harness detection, context injection, Windows wrapper) ✅
3. Harness adapters — all three plugin formats ✅
4. Consistency tooling — offline test suite ✅, live smoke tests ⬜
5. Authoring layer — identity ✅, catalog ✅, scaffold ✅, trigger evals ✅, registry descriptor ✅ ← *you are here*
6. Release — tag, published marketplace, clean-machine install check, and the
   [publishing checklist](publishing.md)

Phase 5 is what turns this from a delivery base into something a collection can be
built *on*: the four things a collection otherwise has to invent for itself before
it can write its second skill.

## Tests

```bash
bash tests/run-tests.sh
```

No dependencies beyond bash, `python3`, and `node` — matching the adapters, which
have none either. CI runs the suite on Linux and macOS.

| Test | Covers |
|---|---|
| `test-hook-branches.sh` | the three session-start JSON shapes, the missing-bootstrap no-op, exec bits |
| `test-manifest-sync.sh` | `name`/`version`/URL agreement across ten manifests and the install docs; LICENSE and notice present |
| `test-identity.sh` | `scripts/identity.sh` itself: drift detection per field, audit sensitivity, and that a full `rename` leaves a tree that still passes this whole suite |
| `test-catalog.sh` | catalog staleness, governance entries against `catalog/schema.json`, the spec's own frontmatter constraints, and that `certified` cannot be self-declared |
| `test-registry.sh` | `skills.sh.json` against the published skills.sh schema, full skill coverage, and that `certified` cannot be self-declared |
| `test-scaffold.sh` | that a scaffolded skill passes the repo's own validators unmodified, in both single- and multi-file shape |
| `test-evals.sh` | trigger-case structure: schema conformance, every skill covered, both polarities present, collision cases exist; plus that `plugin-evals/*/case.yaml` are well-formed and do not hardcode a collection prefix |
| `test-skill-integrity.sh` | frontmatter contract, Platform Adaptation links ↔ `references/`, Gemini `@`-includes, and that no skill body names a harness tool |
| `test-opencode-plugin.mjs` | config registration idempotence, injection position, double-injection guard |
| `test-pi-extension.mjs` | arm/disarm lifecycle, insertion after compaction summaries |
| `test-hermes-plugin.py` | `pathlib.Path` registration, first-turn-only injection, loud failure on a missing skills tree |

The suite is mutation-tested: ten deliberate regressions — including reintroducing
the original Copilot CLI branch bug — were each confirmed to fail it. `identity.sh`
was caught by exactly this: `--audit` stripped the collection name before searching
for it, so it passed on every possible tree until a mutation check refused to fail.
A drift checker that has never rejected anything is indistinguishable from `exit 0`.

The same check caught the second version of that bug on 2026-10-27, from the
opposite direction. `--audit` searched with a plain `git grep`, which reads
tracked content only, so on a tree whose files were not committed yet it scanned
*nothing* and reported a clean result — the `exit 0` failure again, one layer
down. It now uses `git grep --no-index --exclude-standard`, which reads the
working tree and still honours `.gitignore`. Switching it on surfaced thirteen
untracked copies of the collection name in `docs/hermes-local-dev-install.md`,
a file added after the literal-rewrite list was last reviewed and therefore not
registered in `.skills-identity.json`; a fork renaming the collection would have
left all thirteen behind. Both the fix and the registration are in.

**What these prove and what they don't.** They prove the adapters behave as written
when their hooks are driven directly. They do **not** prove any harness loads the
plugin, calls those hooks, or reads the field emitted. Eleven of the fifteen rows
above are still unverified in a live session — including the Hermes plugin, whose
`test-hermes-plugin.py` passes while the adapter itself has never been loaded; see
[docs/live-smoke-tests.md](live-smoke-tests.md) for the checks only a real
session can make. Community verification is welcome — that document is written to be
run by someone with access to a harness we don't have.

## Tooling

The six scripts are listed in [the README](../README.md#the-six-commands).
What follows is why two of them exist at all, and what they are generating for.

### The catalog

`catalog/skills.json` is generated from two sources, and the split is the point:

- **`SKILL.md` frontmatter** carries the [Agent Skills
  specification](https://agentskills.io/specification)'s discovery fields —
  `name`, `description`, `license`, `compatibility`, `metadata`,
  `allowed-tools`. Generated from, never duplicated. `scripts/catalog.sh`
  enforces the spec's own constraints and rejects any top-level key outside that
  set, because the spec directs client-specific properties into `metadata`.
- **`catalog/entries/<name>.json`** carries governance: `classification`,
  `origin`, `maintainers`, `license`, `registries`, and — for a third-party
  skill — the `source` repository, revision, and path. These are hand-written
  because none of them is derivable from a skill describing itself. That is not
  duplication; it is a different kind of fact.

`classification` (`certified` / `reference`) and `origin` (`first-party` /
`third-party`) are deliberately **orthogonal**. Collapsing them into one ladder
would label first-party work that simply has not been certified yet as a
community contribution, and would make a certified third-party skill
inexpressible.

`certified` is not self-declarable: the gate is that the skill carries both
positive and negative trigger cases, and `scripts/catalog.sh` refuses the claim
without them.

### Trigger evals

The offline suite proves a skill is *delivered*. Nothing in it proves a skill is
*chosen* — and `description` is the only text an agent sees when deciding.

`evals/<skill>/trigger-cases.json` is a flat array of `{query, should_trigger}`
— the shape used across sibling collections, so anything that can read one can
read the other. Two additive keys a plain reader ignores: `expect_skill` names
which skill should win instead (a boolean cannot express a collision, and
collisions are the failure that grows with a collection), and `note` records
what the case protects, so it is not deleted the first time it fails.

`scripts/eval.sh --check` rejects a suite with no negative case.

**Running costs money and is behind an explicit flag.** `--check` and
`--dry-run` are free; a bare invocation refuses and says why.

**They have now been run.** The first recorded pass is 2026-10-27, through
`scripts/bare-model.sh` — the logged-in CLI with installed skills, hooks and MCP
disabled, which is the isolation the runner needs and which `claude --bare`
cannot provide without an API key. `evals/results.json` holds the per-skill
result and the command that produced it. See the resolved decision at the bottom
of this file for what the run changed.

`using-skills` is the one skill with no selection result, by design: a bootstrap
is injected by the session-start hook and never chosen from a catalog, so its
claim is recorded in `evals/using-skills/host-behavior.md` instead.

`plugin-evals/<case>/case.yaml` holds end-to-end routing cases for the official
`claude plugin eval` harness — a different and more expensive question: did the
installed plugin actually fire the `Skill` tool. Authored, never run; the cheap
runner answers the description question, not this one.

It is not part of `tests/run-tests.sh` and should not be: that suite is offline,
free, and deterministic, and a flaky model-backed check that blocks a commit
gets disabled within a week. Only the structural half runs in CI. See
[evals/README.md](../evals/README.md).

### Publishing and discoverability

`skills.sh.json` in the repository root is **display configuration for a
repository page that already exists**, not a descriptor that causes discovery.
skills.sh reads it after a skill from this repository is installed through the
`skills` CLI with telemetry enabled, and re-checks it on the default branch on
later installs. It is generated by `scripts/registry.sh` from the catalog and
validated against
[the published skills.sh schema](https://skills.sh/schemas/skills.sh.schema.json)
by `tests/test-registry.sh`, because violating someone else's schema produces a
page that renders wrong rather than an error.

*(Corrected 2026-09-25. This section previously described registries crawling
public repositories on their own schedule. See
[publishing.md](publishing.md) for what replaced that premise.)*

`classification: certified` in a governance entry drives a "Certified" grouping
in that listing, so it is not self-declarable: the gate is that the skill
carries both positive and negative trigger cases, and `scripts/catalog.sh`
refuses the claim without them. `origin: third-party` groups as Community
independently, so an uncertified first-party skill is never mislabelled as a
community contribution.

**Still worth doing before going public, for a narrower reason than previously
stated here:** the first person to install a skill is the one whose install
reads this file, and they should not be the one who finds it malformed. See
[publishing.md](publishing.md) for the full checklist, including the repository
topics to set and why the history should be re-baselined before the repo goes
public.

## Harness notes

See [docs/harness-support-matrix.md](harness-support-matrix.md) for the full
breakdown of which harness consumes which plugin format, and what each one costs.

### The three formats

- **Claude Code format, no new files.** Factory Droid, Copilot CLI, and Grok Build
  CLI all install `.claude-plugin/` directly. Adding them cost nothing
  but a README line; the work is distribution, not code. Antigravity was listed
  here until 2026-09-28; the live run showed it is not in this bucket.
- **Claude-derived.** Cursor, Devin, Codex, and Kimi each want their own manifest
  directory with a few harness-specific fields, over the same `skills/` tree.
- **Own runtime.** Gemini, OpenCode, Pi, and Hermes need real code.

### Claude Code

Auto-discovers `skills/` and `hooks/hooks.json` next to `.claude-plugin/plugin.json`;
the manifest declares neither. The `SessionStart` hook injects `using-skills` so the
agent starts every session knowing the collection exists.

### The session-start hook's three branches

`hooks/session-start` emits one of three JSON shapes, chosen by environment, because
each harness reads a different field and Claude Code reads two of them without
deduplicating:

| Environment | Field emitted |
|---|---|
| `CURSOR_PLUGIN_ROOT` set | `additional_context` |
| `CLAUDE_PLUGIN_ROOT` set, `COPILOT_CLI` unset | `hookSpecificOutput.additionalContext` |
| otherwise (Copilot CLI, SDK standard) | `additionalContext` |

**Order matters and is load-bearing.** Cursor and Copilot CLI both run the Claude
Code plugin and may set `CLAUDE_PLUGIN_ROOT` as well, so testing for it first
swallows them both and emits a field neither reads — a bootstrap that vanishes with
no error anywhere. Most-specific branch first.

### Codex

**Install (local dev):**

```bash
codex plugin marketplace add /path/to/skills  # registers .agents/plugins/marketplace.json
codex plugin list                             # skills@openbridge-skills should appear
codex plugin add skills@openbridge-skills
```

Then start a Codex session — skills are surfaced natively, nothing is injected.
To remove: `codex plugin remove skills`, then
`codex plugin marketplace remove openbridge-skills`.

Codex surfaces skills natively, so there is no session-start hook and nothing to
inject. Consequences for the manifest:

- `"skills": "./skills/"` is **explicit** — Codex reads the path from the manifest
  rather than discovering it by convention.
- `"hooks": {}` is **load-bearing, not decoration.** Codex would otherwise
  auto-discover `hooks/hooks.json`, which exists in this repo for Claude Code and
  would fire a session-start hook Codex has no use for. The empty object suppresses
  that discovery. Do not copy this manifest to a harness that *does* want the hook.
- The marketplace manifest lives at `.agents/plugins/marketplace.json` and uses a
  different schema from Claude's: each plugin carries a `source` object, a `policy`,
  and a `category`. This repo declares `{"source": "url", "url": "./"}`.

  **That form no longer matches the documented one, and has not been migrated.**
  Current OpenAI documentation gives four source types — `local` (with `path`),
  `url` (a GitHub repository), `git-subdir` (`url` + `path`), and `npm` — and a
  local marketplace entry is the `local` form:

  ```json
  { "source": "local", "path": "./plugins/my-plugin" }
  ```

  What is checked in still installed successfully on codex-cli 0.154.0, which is
  where this repo's only Codex evidence comes from. Documentation drift is not
  proof of breakage, and replacing a manifest that works with one that has never
  been run here would trade evidence for currency. The migration is gated on
  installing both forms against a current Codex CLI and App and recording install,
  discovery, reference-file resolution, and hook suppression separately. Until
  that runs, this row's verification claim covers the old form only.
- `interface{}` carries store metadata (display name, category, capabilities,
  default prompts) with no Claude Code equivalent. `composerIcon`, `logo`,
  `brandColor`, and the privacy/ToS URLs are omitted until this repo ships an
  `assets/` directory — a manifest pointing at missing files is worse than one
  leaving the fields out.

Codex publishing goes through the public Plugins Directory shared by ChatGPT and
Codex; there is a submission flow rather than a pull request against OpenAI's
plugins repo. Nothing here is wired up for it yet.

*(This corrects an earlier statement in this document that Codex had no
self-publish path. Verified against
<https://developers.openai.com/plugins/deploy/submission> on 2026-09-25.)*

One further divergence worth recording before any packaging work: OpenAI now
describes a root `plugin.json` carrying OpenAI-specific settings under
`extensions.com.openai` as the going-forward layout, with `.codex-plugin/plugin.json`
"supported as a compatibility fallback." The two are **not merged** — defining
`extensions.com.openai` replaces the `.codex-plugin` overlay entirely. This repo is
on the fallback, deliberately, until the A/B install test above says otherwise.

Codex also gates subagent dispatch behind `multi_agent = true` in
`~/.codex/config.toml` — see `skills/using-skills/references/codex-tools.md`.

### Cursor

Declares `"skills"` and `"hooks"` explicitly; there is no auto-discovery. Its hook
config is `hooks/hooks-cursor.json`, whose schema differs from Claude's — a
`"version": 1` field and a `sessionStart` camelCase key, not a `SessionStart` matcher
block.

### Devin CLI

The plainest manifest in the repo: no `skills` field, no `hooks` field, no tool
mapping. Devin auto-discovers `skills/`, lists every installed skill's name and
description in its own system prompt, and documents its own subagent and todo tools
there. Nothing to inject.

### Kimi Code

Bootstraps declaratively — `"sessionStart": {"skill": "using-skills"}` — with no hook
script. Its tool mapping lives inline in the manifest as `skillInstructions` rather
than in `references/`.

### Gemini CLI

**Sunsetting for individual accounts.** As of 2026-06-18 the Gemini CLI stopped
serving Gemini Code Assist for individuals, Google AI Pro, and Google AI Ultra;
OAuth sign-in fails with a message directing users to Antigravity. API-key auth
(`GEMINI_API_KEY`) and Enterprise Code Assist licences are unaffected, so the row
is still testable — but it is no longer the one to fix first, and the Antigravity
CLI row above is its successor. Verified against
<https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals>
on 2026-09-28.

The extension itself installs and validates cleanly on gemini 0.61.0
(`gemini extensions install <path>`, `gemini extensions validate <path>`), and
the install copies whole skill directories including `references/`. No session has
been run.

`gemini-extension.json` declares `contextFileName: "GEMINI.md"`, and that file
`@`-includes the bootstrap skill and the Gemini tool mapping. This works only because
the file ships *inside the installed extension* — never edit a user's global
`GEMINI.md` to achieve the same thing.

**Unverified risk:** an `@`-include is not guaranteed inline expansion. A
Gemini-derived harness can accept `@./path` syntax but treat it as a hint the model
may choose to act on, emitting a file-read tool call instead. If a unique-marker test
shows the marker absent from context *without* a tool call, inline the content into
`GEMINI.md` rather than `@`-including it.

### OpenCode and Pi

Both declare themselves through the repo-root `package.json` — `main` points at the
OpenCode plugin, and the `pi` field plus the `pi-package` keyword declare the Pi
extension. One shared file, two harnesses.

OpenCode injects into the first *user* message, not a system message: system messages
repeat every turn, and more than one breaks some models. The transform hook fires on
every agent step rather than every turn, so it carries a marker guard against stacking
copies.

Pi has native skill *discovery* but no `Skill` tool — skills are reached by plain
file read. Its extension re-arms injection on `session_start` and `session_compact`,
and inserts the bootstrap after any compaction-summary messages. Pi runs the `.ts`
source directly with no build step; the `import type { ExtensionAPI }` is undeclared
and works only because nothing type-checks the file. Adding CI type-checking breaks it.

### Antigravity CLI (`agy`)

Recorded against **agy 1.2.12 on 2026-09-28**, the first live run of this row.
It is the successor Google names for the Gemini CLI, which
[stopped serving individual accounts on 2026-06-18](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/).

**Install is a local directory — no marketplace, no remote:**

```bash
agy plugin install /path/to/skills   # copies into ~/.gemini/config/plugins/<name>/
agy plugin list                          # JSON; records the detected source
```

Antigravity shares `~/.gemini/` with the Gemini CLI but keeps its own state under
`~/.gemini/antigravity-cli/`. Remove with `agy plugin uninstall skills`.

Four things the run established that no offline test could:

- **It detects this repo as a Gemini CLI extension.** `agy plugin list` reports
  `"source": "gemini-cli"` — the root `gemini-extension.json` is what it matched,
  not `.claude-plugin/`. The previous claim in this document, that Antigravity
  installs the Claude Code plugin directly, was wrong.
- **It synthesizes a root `plugin.json`** from the Gemini manifest's `name`,
  `version`, and `description`. That is also why `agy plugin validate .` fails
  against this tree: validate expects `plugin.json` at the plugin root, and only
  install creates it.
- **Our session-start hook never runs.** Antigravity's `hooks.json` is a different
  schema — top-level keys are hook *names*, and the events are `PreToolUse`,
  `PostToolUse`, `PreInvocation`, `PostInvocation`, and `Stop`. There is **no
  `SessionStart`**. Install copies `hooks/hooks.json` to the plugin root verbatim,
  where its top-level `"hooks"` key reads as a hook named `hooks` with no
  recognized event; the command also still interpolates `${CLAUDE_PLUGIN_ROOT}`,
  which agy does not set. `✔ hooks : 1 processed` on install means *copied*, not
  *registered*. Corroborated in the session: the agent read `using-skills/SKILL.md`
  before answering, which it would not need to do if the bootstrap — which contains
  that file's whole text — had been injected.
- **Skills are discovered natively anyway**, alongside agy's own builtins
  (`agy-customizations`, `antigravity_guide`, `plugin`, `automation`, and others).
  A fresh session listed all three of this collection's skills with their
  descriptions before reading any file, and `using-skills` fired and was followed
  rather than merely listed. This row therefore belongs with Codex and Devin: no
  hook is needed, and step 1 is carried by the harness's own registry.

If a bootstrap is ever wanted here, `PreInvocation` is the only injection point —
and it fires before *every* model call, so it would need a duplicate guard of the
kind `.opencode/` already carries.

**Open, and cheap to settle:** `skills/using-skills/references/antigravity-tools.md`
maps actions to `write_to_file`, `replace_file_content`,
`multi_replace_file_content`, and `invoke_subagent`. agy 1.2.12's builtin skills
reference `run_command`, `read_file`, `write_to_file`, `view_file`, and `edit_file`
— and none of the other three. That is suggestive, not conclusive, because builtin
skill text is not a tool registry. The mapping was likely written against the
Antigravity IDE. Confirm with one prompt (`agy -p "List your available tools by
exact name."`) before trusting it.

### Hermes Agent

`register()` walks `skills/` and registers each with Hermes' native loader.
`register_skill` requires a `pathlib.Path` — passing a `str` raises `AttributeError`
and Hermes responds by silently disabling the whole plugin. Injection uses
`pre_llm_call` returning `{"context": ...}`; `on_session_start` return values are
ignored and `ctx.inject_message` refuses from that hook.

## Manifest drift

`name`, `version`, and the repository URL are duplicated across every manifest —
`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`,
`.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json`,
`.devin-plugin/plugin.json`, `.kimi-plugin/plugin.json`,
`.agents/plugins/marketplace.json`, `.hermes-plugin/plugin.yaml`,
`gemini-extension.json`, and `package.json`. Ten files, more as harnesses are
added. The collection name additionally appears as a bare string in
`.opencode/plugins/<name>.js`, `.pi/extensions/<name>.ts`,
`.hermes-plugin/__init__.py`, and several docs — and in two filenames that
`package.json` references by path.

None of that has gone away. What changed is that it is now **generated and
audited rather than maintained by hand**:

- `.skills-identity.json` declares every target. `scripts/identity.sh` writes
  them all in one operation and `--check` fails when any disagrees.
- `--audit` greps for occurrences the declarative map does not know about. That
  is not redundant with `--check`: a declarative list structurally cannot find a
  name embedded in prose, in a duplicate-guard marker, or in a filename. On its
  first run it found four, including a tool-mapping reference telling agents to
  call `skill_view("skills:...")` — which a rename would have broken silently.
- `tests/test-identity.sh` fails if a manifest exists in the tree and is not
  registered in the map, so adding a harness cannot reintroduce the drift.

Two things the tooling deliberately does not do. It does not treat `description`
as a synced field — the manifests carry genuinely different descriptions by
design, and forcing them into agreement would be worse than the drift. And
`rename` does not touch the **repository** name, which is a separate identity
that merely looks similar; `set homepage` handles that, and rewrites the install
commands that embed it.

## Decisions to revisit

Choices made deliberately, recorded here because they were judgement calls made
under a particular constraint rather than facts about the format. Each should be
re-examined when the constraint changes.

### Model-backed evals are not run (2026-09-24) — resolved 2026-10-27

**Resolution.** The cheap runner has been run and recorded; see
`evals/results.json`. What follows is the original decision, kept because the
cost reasoning still governs the *expensive* harness, which remains unrun. The
resolution itself is written up under
[Trigger evals are now recorded](#trigger-evals-are-now-recorded-2026-10-27).

**Decision.** Trigger evals are authored but not executed. `scripts/eval.sh`
requires an explicit `--run` or `--record`; a bare invocation refuses and
explains why. The official `claude plugin eval` harness is not run at all.

**Why.** Running costs real money on the account whose model command is
configured, and we chose not to spend it for now.

The numbers, from a recorded pass in a comparable repository:

| Run | Cost |
|---|---|
| 3 cases, `--ablation with-without --runs 3` | $3.54 |
| 1 diagnostic run with retained trace | $0.23 |
| 3 cases, focused, `--runs 1` | $0.78 |
| Live lifecycle session | $0.14 |
| **One full evaluation pass** | **$4.68** |

The multiplier is that each case runs a real multi-turn agent, and a
with/without ablation at three runs each turns three cases into eighteen
sessions plus grader calls. `scripts/eval.sh` is far cheaper — one short
completion per case — but not free.

**What it costs us.** `classification: certified` can still be earned, because
the documented gate is that a skill carries both positive and negative trigger
cases, and that is checked offline for free. But nobody has watched those cases
*pass*. Certification therefore rests on the cases existing and having been
thought about, not on a run anyone can point at. That is weaker than intended,
and it is the main thing to fix when this is revisited.

It also means the trigger evals are unverified as a body of work: the one
exploratory run was contaminated by the host agent's own skills, so the single
finding it produced — `using-skills` not firing on ordinary first-turn work — is
provisional.

**Revisit when** there is a budget for it, or before publishing certified skills
to a public registry, whichever comes first. Start with a
`--max-cost-usd` ceiling. The cheap runner first, against a bare model call
rather than an agent harness; the official plugin evals only if end-to-end
routing evidence is actually needed.

### Trigger evals are now recorded (2026-10-27)

**What happened.** The cheap runner was pointed at `scripts/bare-model.sh` — the
installed Claude Code CLI with `--disable-slash-commands`, `disableAllHooks`,
`--strict-mcp-config` and no tools — and the full suite was recorded. The
isolation holds: zero off-catalog answers and no plugin-prefixed names across
the run, which is what the contamination that spoiled the exploratory run looked
like.

`claude --bare` is the documented minimal mode and would have been the obvious
choice, but it reads neither OAuth nor the keychain, so it needs an
`ANTHROPIC_API_KEY`. The flag combination in `scripts/bare-model.sh` reaches the
same isolation from an ordinary login, which is why the run cost nothing beyond
ordinary session usage. That removes the budget constraint the 2026-09-24
decision was made under, for this harness.

**What it changed.** Two of the three failures in the first pass were defects in
the evals, not the skills:

- Two descriptions both claimed `403` without saying which. `authenticating-obcmd`
  spelled `http_403` literally and therefore won every 403 prompt, including the
  `job list` case that belongs to `diagnosing-openbridge-pipelines`, where a
  missing `--subscription_ids` is reported as a permission error. Both now name
  the discriminator — every command failing versus one subscription's call
  failing — which is the distinction both skill bodies already documented.
- One collision guard named the wrong `expect_skill`; the model's answer was
  correct and the hint was not.
- The long-failing `using-skills` case moved to
  `evals/using-skills/host-behavior.md`. Its own note had already diagnosed it:
  a hook-injected bootstrap is never selected from a catalog, so a selection
  eval is the wrong instrument. This is the `host-behavior.md` adoption that
  [live-smoke-tests.md](live-smoke-tests.md#a-stronger-record-than-a-checklist)
  calls for, started with the one skill that needed it.

**What is still unproven.** The official `claude plugin eval` harness, which
answers a different question — whether an installed plugin fires the `Skill`
tool end to end — remains unrun, and the cost table above still applies to it.
A recorded selection pass is also a single run of a non-deterministic check: it
says these descriptions resolved correctly once, not that they always will.
