# skills

Skills that teach a coding agent to drive **Openbridge** through the `obcmd` CLI —
authenticate, authorize a third-party account, provision a destination, create and
change subscriptions, resolve platform IDs, backfill history, and diagnose a broken
pipeline.

Ten skills, packaged for thirteen harnesses from a single source of truth.

---

## What is a skill?

**A skill is a note you leave for an AI agent.**

The note says "when *this* happens, do it *this* way." The agent reads the note
and follows it.

This repository holds those notes, plus the plumbing that gets them in front of the
agent — no matter which AI tool you happen to be using.

## The one big idea

> **Write the note once. Deliver it everywhere.**

A skill is a plain Markdown file with YAML frontmatter. It contains no code and
mentions no specific AI tool. So the *same file* works in Claude Code, Cursor,
Codex, Gemini, and ten others.

Each tool needs to be told "skills live over there" in its own particular way.
Those little "hey, look over there" files are called **manifests**, and this repo
has one per tool. That is why there are so many small JSON files lying around.

```
                       ┌─→ Claude Code  (reads .claude-plugin/plugin.json)
                       ├─→ Cursor       (reads .cursor-plugin/plugin.json)
   skills/  ───────────┼─→ Codex        (reads .codex-plugin/plugin.json)
   (the actual notes)  ├─→ Gemini       (reads gemini-extension.json)
                       └─→ …ten more
```

One folder of notes. Many thin pointers to it.

---

## The skills

Ten Openbridge skills. You do not name them — each declares the situation it
applies to, and the agent loads it when that situation arrives.

**Start here**

| Skill | Loads when |
|---|---|
| `using-obcmd` | any `obcmd` call is about to happen — discovery, exit codes, dry-run, output guarantees |
| `authenticating-obcmd` | exit 4, `not_authenticated`, `http_401`, `credential_in_argv`, or a 403 meaning the wrong account |

**Connecting an account**

| Skill | Loads when |
|---|---|
| `authorizing-remote-identities` | connecting or re-authorizing a third-party account (Amazon, Google, Facebook, Shopify, Snowflake…) |
| `inspecting-remote-identities` | you need a `remote_identity_id`, or need to know whether a credential went `invalid_identity` |

**Building a pipeline**

| Skill | Loads when |
|---|---|
| `provisioning-openbridge-destinations` | creating a Redshift/BigQuery/Snowflake/S3 destination, or finding a `storage_group_id` |
| `creating-openbridge-subscriptions` | connecting a source to a destination — resolving product, identity, storage and stage IDs in the order the API demands |
| `resolving-platform-ids` | a `product_parameters` field needs a platform-side ID (Amazon profile, SP-API marketplace, Google Ads customer, Campaign Manager profile…) |

**Running one**

| Skill | Loads when |
|---|---|
| `updating-openbridge-subscriptions` | changing, pausing, repointing or cancelling a subscription |
| `backfilling-openbridge-history` | backfilling or re-running history — the date flags are counter-intuitive |
| `diagnosing-openbridge-pipelines` | data stopped, arrived late, or a job/healthcheck reports an error |

Three more skills in `skills/` are scaffolding rather than Openbridge content —
see [The three scaffolding skills](#the-three-scaffolding-skills).

[docs/examples/README.md](docs/examples/README.md) has a starter prompt for every
one, paired with the skill it should pull in.

## Installing

The collection installs as **`skills`**, from `openbridge/skills` — which is
also this clone's `git remote`, and what `scripts/identity.sh --check` verifies
every manifest against. Forked it? See [Renaming a fork](#renaming-a-fork).

Harnesses that namespace skills prefix them with the collection name, so an
agent refers to one as `skills:using-obcmd`, not by bare name.

**Verified against a real session:**

| Harness | Install |
|---|---|
| Claude Code | `claude plugin marketplace add openbridge/skills`<br>`claude plugin install skills@openbridge-skills` |
| Codex CLI | `codex plugin marketplace add openbridge/skills`<br>`codex plugin add skills@openbridge-skills` |
| Antigravity CLI (`agy`) | `agy plugin install /path/to/skills` — a local directory, not a URL. It copies the tree and discovers skills natively; the session-start hook does not run and is not needed |
| Hermes Agent — from a working copy, no plugin | point `skills.external_dirs` at your clone's `skills/` and add the bootstrap to `SOUL.md` — see [docs/hermes-local-dev-install.md](docs/hermes-local-dev-install.md) |

**Code-complete, never run against the live harness** — these commands are
written from each harness's documentation, not from a session anybody has had.
Treat a failure as expected rather than surprising, and see
[docs/status.md](docs/status.md) for what each row's evidence actually is:

| Harness | Install |
|---|---|
| Factory Droid, Copilot CLI, Grok Build CLI | install the Claude Code plugin directly — no separate manifest |
| Cursor | `cursor plugin marketplace add openbridge/skills` |
| OpenCode | add `"skills@git+https://github.com/openbridge/skills.git"` to the `plugin` array in `opencode.json` — see [.opencode/INSTALL.md](.opencode/INSTALL.md) |
| Hermes Agent | `hermes plugins install openbridge/skills` — remote-only, so it needs the repository published first. For a working copy, use the verified route above instead. |
| Gemini CLI | `gemini extensions install /path/to/skills`. Installs and validates on 0.61.0, but no session has been run — and individual-account sign-in [was discontinued on 2026-06-18](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals), so it needs `GEMINI_API_KEY` |
| Devin CLI, Kimi Code, Pi, Antigravity IDE / 2.0 | install as that harness's extension/plugin from this repository |

### Via the skills registry

```bash
npx skills add openbridge/skills
```

Installing this way with telemetry enabled is also what creates the repository's
page on skills.sh — `skills.sh.json` configures how that page renders, and is
read on the default branch at install time. It does not cause discovery on its
own.

## The parts, in plain words

| Folder | What it really is |
|---|---|
| `skills/` | **The notes.** Ten Openbridge skills plus three scaffolding ones. The only thing here that matters to a user. |
| `hooks/` | The doorbell. Rings when a chat session starts, hands the agent the welcome note. |
| `scripts/` | Six helper commands you run yourself. See [The six commands](#the-six-commands). |
| `tests/` | Safety net. Run it; it tells you if you broke something. |
| `catalog/` | A list of every skill, plus who owns it and whether it's been reviewed. |
| `evals/` | Test questions that check whether a skill gets *picked* when it should. |
| `docs/` | These explanations. |
| `templates/` | Blank forms the scaffold command fills in. |
| `.*-plugin/` and `*-extension.json` | The "hey, look over there" pointers, one per AI tool. |

### The three scaffolding skills

`skills/` holds three skills that are not about Openbridge. They are machinery,
and each one is wired into something that breaks if you delete it.

- **`using-skills`** — the welcome note. Pushed into *every* session
  automatically; all it says is "you have skills, go check if one applies."
  Every harness adapter loads it **by name** — `hooks/session-start`, the Kimi
  manifest, the OpenCode, Pi and Hermes plugins. Without it, none of the ten
  Openbridge skills are ever discovered.
- **`delivery-check`** — the smoke alarm test button. It contains a secret
  phrase. If you ask an agent to run it and the phrase comes back, delivery
  works. Eleven of the fifteen harness rows have never been driven live, so this
  is the first thing to run on a new one. Named in `.codex-plugin/plugin.json`
  and asserted by three test suites.
- **`example-skill`** — a blank-but-correct note, kept as the worked example.
  `AGENTS.md` makes it the authoring procedure, and `tests/test-charter.sh`
  fails if it drifts from one.

They are each a real skill with a real trigger, so an agent can load them — but
only `using-skills` arrives unasked.

---

## What happens when you open a chat

1. You start a session in (say) Claude Code.
2. Claude Code sees `hooks/hooks.json` and runs `hooks/session-start`.
3. That script reads `skills/using-skills/SKILL.md` and prints it as JSON.
4. Claude Code pastes that text into the agent's context.
5. The agent now knows skills exist, and loads the ones it needs, when it needs them.

Try it yourself — this is exactly what the AI receives:

```bash
CLAUDE_PLUGIN_ROOT=x ./hooks/session-start
```

You'll see a blob of JSON with the welcome note inside it.

The script prints one of three JSON shapes, because each AI tool reads a
differently named field — and picking the wrong one makes the note vanish with no
error anywhere. The shapes and the ordering rule are in
[docs/status.md](docs/status.md#the-session-start-hooks-three-branches).

Some tools skip the doorbell entirely: Codex and Devin find skills by themselves,
Gemini reads `GEMINI.md`, and Kimi names the skill right in its manifest.

---

## How to write a new skill

**Do not copy a folder by hand.** A skill is *three* files, and copying gets you one.

```bash
scripts/new-skill.sh my-skill --trigger "a pipeline run finishes and you are about to report success"
```

That writes all three:

| File | Why |
|---|---|
| `skills/my-skill/SKILL.md` | the note itself |
| `catalog/entries/my-skill.json` | who owns it, whether it's reviewed |
| `evals/my-skill/trigger-cases.json` | questions that prove it fires at the right time |

Then open `SKILL.md` and fill in the placeholders.

### The two rules that matter most

**Rule 1 — the description is a trigger, not a summary.**

It is the *only* text the agent sees when deciding whether to open your skill.
Describe the *situation*, not the contents.

| ❌ Bad | ✅ Good |
|---|---|
| `Guidance on our REST API` | `Use when calling the billing REST API, before constructing any request` |
| `Helps with debugging` | `Use when a job fails or returns unexpected output, before proposing a fix` |

**Rule 2 — name actions, never tools.**

Write "dispatch a subagent", "read the file", "track each item as a task."
Never write `Task`, `Read`, `TodoWrite`.

Why: those are Claude Code's names. Gemini and Pi call them something else. The
moment a skill uses one, it stops being portable — and portability is the whole
point. `tests/test-skill-integrity.sh` fails the build if you do it.

If a tool really does need a translation, it goes in
`skills/using-skills/references/<tool>-tools.md`, never in the skill itself.

### Rule 3 — read the source system, do not review it

Writing a skill about `obcmd` means reading its help output, its docs, and its
error messages. Do that freely. But what comes back is **material for a
procedure**, not a verdict on the tool:

| In scope — changes what the skill says | Out of scope — a finding about obcmd |
|---|---|
| `--token` echoes into shell history; tell the agent to use the env var | this tool stores credentials insecurely |
| `--force` cannot be undone; require a dry run first | this tool has unsafe defaults |

Noticed something from the right column anyway? One line in
`OBSERVATIONS.md`, then back to the skill. Nothing in this repo acts on that
file; a human reads it when they choose to.

[AGENTS.md](AGENTS.md) is the full charter, including the definition of done.
`CLAUDE.md` and `GEMINI.md` both `@`-include it so every harness gets the same
one, and `tests/test-charter.sh` fails if they drift.

---

## The six commands

Five are free and offline, with no network. The sixth calls a model.

| Command | In plain words |
|---|---|
| `scripts/new-skill.sh <name>` | Make a new skill (all three files). |
| `scripts/catalog.sh` | Rebuild the skill list. Run after editing any skill. |
| `scripts/registry.sh` | Rebuild `skills.sh.json`, the file public skill directories read. |
| `scripts/identity.sh` | Rename the collection everywhere at once. See [Renaming a fork](#renaming-a-fork). |
| `scripts/eval.sh` | Check the trigger questions. **`--run` costs money.** See [What costs money](#what-costs-money). |
| `scripts/bare-model.sh` | The model call `eval.sh --run` uses. Not run on its own; see [Trigger evals](evals/README.md#running-them) for why it exists. |

Add `--check` to `catalog.sh`, `registry.sh`, `eval.sh`, or `identity.sh` and
they only *report* — they change nothing. That's what CI runs.

Every script has `--help`.

---

## Renaming a fork

The name `skills` is copied into **ten** manifest files, three source files,
two filenames, and assorted prose. Editing one and forgetting the rest used to be
the normal failure.

One command fixes all of them:

```bash
scripts/identity.sh rename your-new-name
scripts/identity.sh --check     # do all ten agree?
scripts/identity.sh --audit     # any stray copies nothing is tracking?
```

`--check` compares against the declared list in `.skills-identity.json`.
`--audit` greps the whole tree for leftovers the list never knew about — because
a list can't find a name buried in a sentence.

**`--audit`'s name sweep does not work on this collection, and says so.** The
name is `skills`, which is also the payload directory, two generated filenames,
and the most common word in this repository's prose — grep cannot tell an
identity copy from a path. `--audit` skips that sweep with a printed note rather
than emitting hundreds of occurrences nobody can act on; the version sweep still
runs, and `--check` still verifies all ten declared copies of the name. Rename to
something distinctive and the sweep comes back on its own.

The dev marketplace name is *derived*, not declared: `.skills-identity.json`
templates it as `openbridge-{name}`, which is why the install command reads
`skills@openbridge-skills` rather than repeating the collection name. `rename`
recomputes it; editing the template itself does not — write the new value into
both `marketplace.json` files by hand, and `--check` will confirm it.

**If you add support for a new AI tool, register its manifest in
`.skills-identity.json` in the same commit.** A test fails if you don't. That test
is the thing stopping the copy-paste drift from coming back.

Note: the *collection* name and the *repository* name are two different
identities. `rename` changes the collection and deliberately leaves the repo
URL alone — use `identity.sh set homepage <url>` for that.

This collection makes them the same string (`skills` in both), which has one
consequence: **`rename` refuses to run.** It protects install URLs by masking the
repository name before rewriting the collection name, and masking cannot tell two
identical strings apart. The way out is two steps, in this order:

```bash
scripts/identity.sh set homepage https://github.com/<owner>/<other-repo>
scripts/identity.sh set repository https://github.com/<owner>/<other-repo>
scripts/identity.sh rename your-new-name
```

Expect the rename's literal pass to report `rewrote literals in 0 file(s)` when
the old and new names share a substring — masking blocks it. Run
`git grep <old-name>` afterwards and fix what is left by hand.

---

## Before you commit

```bash
bash tests/run-tests.sh          # 12 suites, ~2 seconds
scripts/identity.sh --check
scripts/identity.sh --audit
scripts/catalog.sh --check
scripts/registry.sh --check
scripts/eval.sh --check
```

All free, all offline. If a generated file is stale, these fail — which is the
point. CI runs the same set on Linux and macOS.

---

## What costs money

Two things, and only these two:

- `scripts/eval.sh --run` — calls a real model, one short completion per question.
  It runs through `scripts/bare-model.sh`, which uses an ordinary Claude Code
  login rather than an API key, so on a machine that already has one the cost is
  session usage rather than a separate bill. The full suite is 50 short
  completions.
- `claude plugin eval` — much more expensive; a recorded three-case pass came to **$4.68**.

Both are behind explicit flags. A bare `scripts/eval.sh` does nothing but explain
this. **Ask before running either.**

Writing eval questions is free. Running them is not. The first recorded pass is
2026-10-27, in `evals/results.json`.

---

## Two kinds of testing, and why both exist

| Question | Answered by | Costs |
|---|---|---|
| Did the skill *arrive* in the session? | `tests/run-tests.sh` + `skills/delivery-check` | nothing |
| Did the agent *choose* the right skill? | `evals/` + `scripts/eval.sh --run` | money |

These are genuinely different failures. A skill can be delivered perfectly and
still never get picked, because its description was vague. The offline suite
can't catch that; only a model can.

---

## Status, in one paragraph

Fifteen harness rows — thirteen harnesses, since Hermes and Antigravity each
occupy two — are supported *in code*. Only **four** have been proven in a live
session: Claude Code, Codex CLI, Antigravity CLI, and the Hermes working copy.
The other eleven were tested by driving their plugin code with fabricated
harness input and confirming it behaved. That proves the code is right. It does
**not** prove the tool actually loads it.

**Those live runs are inherited from the upstream template, not performed on
this collection.** They are evidence that the adapter code works, which is why
they are quoted here. Nothing in this repository has been driven live under its
own name.

**[docs/status.md](docs/status.md) is the evidence**: the per-harness verification
table, what the offline suite covers, the harness-by-harness implementation notes,
and the decisions taken under constraint. Read the verification column there before
trusting any row.

## Layout

```
skills/                   # the payload — one directory per skill
  using-obcmd/            # the obcmd contract: discovery, exit codes, dry-run, output
  authenticating-obcmd/   # exit 4, 401, 403-wrong-account, first-time setup
  authorizing-remote-identities/    # connect or re-authorize a third-party account
  inspecting-remote-identities/     # find a remote_identity_id; spot invalid_identity
  provisioning-openbridge-destinations/  # create a destination; find storage_group_id
  creating-openbridge-subscriptions/     # source → destination, IDs in API order
  resolving-platform-ids/                # platform-side IDs for product_parameters
  updating-openbridge-subscriptions/     # change, pause, repoint, cancel
  backfilling-openbridge-history/        # history trigger and its date flags
  diagnosing-openbridge-pipelines/       # no data, late data, job/healthcheck errors
  using-skills/           # scaffolding — bootstrap; injected into every session
    SKILL.md
    references/           # per-harness tool mappings, linked from SKILL.md
  delivery-check/         # scaffolding — the probe; proves a harness delivers skills
  example-skill/          # scaffolding — authoring template; no confirmation phrase
hooks/                    # shell-hook harnesses only
  hooks.json              # SessionStart wiring (Claude Code and the harnesses reusing it)
  hooks-cursor.json       # Cursor's wiring — camelCase key, "version": 1
  session-start           # reads the bootstrap skill, emits the context injection
  run-hook.cmd            # polyglot cmd/bash wrapper for Windows
.claude-plugin/
  plugin.json             # Claude Code manifest (read at runtime by the hook)
  marketplace.json        # dev marketplace entry
.codex-plugin/plugin.json # Codex App + Codex CLI
.cursor-plugin/plugin.json
.devin-plugin/plugin.json
.kimi-plugin/plugin.json  # tool mapping inline, in skillInstructions
.agents/plugins/
  marketplace.json        # Codex dev marketplace entry
.opencode/
  plugins/skills.js    # in-process plugin
  INSTALL.md
.pi/extensions/skills.ts
.hermes-plugin/
  plugin.yaml
  __init__.py
gemini-extension.json     # Gemini manifest, declares contextFileName
GEMINI.md                 # the declared context file — @-includes the bootstrap
package.json              # main → OpenCode plugin; pi fields → Pi extension
AGENTS.md                 # the charter — what authoring a skill is, and is not
CLAUDE.md                 # one line; @-includes AGENTS.md
OBSERVATIONS.md           # the drain: things noticed about obcmd that are not skill content
CONTRIBUTING.md           # how to add a skill, and what not to run
LICENSE                   # MIT
THIRD_PARTY_NOTICES.md    # required upstream notice; ships with any fork
.gitattributes            # LF enforcement — CRLF breaks the shell hook
.github/workflows/        # CI: the offline suite on Linux and macOS
docs/
  examples/README.md         # starter prompts — what to say to trigger each skill
  status.md                  # what is proven, what is not, and the harness notes
  skill-format.md            # the SKILL.md contract
  harness-support-matrix.md  # what each harness actually needs, and why
  live-smoke-tests.md        # the checks only a real session can make
  hermes-local-dev-install.md # the verified Hermes working-copy route
  publishing.md              # what must be right before the repo goes public
scripts/
  bare-model.sh           # the isolated model call eval.sh --run needs (no API key)
  identity.sh             # name/version/URL across every manifest; check, set, rename, audit
  catalog.sh              # generate catalog/skills.json from frontmatter
  new-skill.sh            # scaffold a skill from templates/
  eval.sh                 # run the trigger evals (needs a model)
.skills-identity.json     # the map identity.sh reads — register new manifests here
skills.sh.json            # generated; the descriptor public registries read
catalog/
  README.md               # the two sources, and why governance is hand-written
  schema.json             # governance entry contract (classification, origin, source)
  entries/<skill>.json    # hand-written governance, one per skill
  skills.json             # generated from frontmatter + entries; never hand-edited
templates/
  SKILL.md.tmpl
  reference.md.tmpl
evals/
  schema.json                      # the trigger-case format
  README.md                        # why triggers need their own check
  <skill>/trigger-cases.json       # [{query, should_trigger}] (+ expect_skill, note)
plugin-evals/
  README.md                        # how these differ from evals/, and what they cost
  <case>/case.yaml                 # official `claude plugin eval` routing cases
```

## Where to go next

| You want to… | Read |
|---|---|
| Start using the skills | [docs/examples/README.md](docs/examples/README.md) |
| Write a skill | [docs/skill-format.md](docs/skill-format.md) |
| Know the scope boundary before authoring | [AGENTS.md](AGENTS.md) |
| See what is actually proven | [docs/status.md](docs/status.md) |
| Know what each AI tool needs, and why | [docs/harness-support-matrix.md](docs/harness-support-matrix.md) |
| Verify a tool really works | [docs/live-smoke-tests.md](docs/live-smoke-tests.md) |
| Make the repo public | [docs/publishing.md](docs/publishing.md) |
| Contribute a change | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Understand governance fields | [catalog/README.md](catalog/README.md) |

## Glossary

| Word used here | Means |
|---|---|
| **skill** | A Markdown note telling an agent how to handle a situation. |
| **harness** | Any AI coding tool — Claude Code, Cursor, Codex, Gemini, etc. |
| **manifest** | A small JSON file telling one harness where the skills live. |
| **hook** | A script the harness runs automatically at session start. |
| **bootstrap** | The `using-skills` note, pushed into every session. |
| **trigger** | The "Use when…" sentence that decides if a skill gets loaded. |
| **eval** | A test question checking whether the trigger actually works. |
| **catalog** | The generated list of every skill and its governance facts. |
| **governance** | Who owns a skill, where it came from, whether it's been reviewed. |
| **drift** | When copies of the same fact stop agreeing with each other. |

## License

MIT — see [LICENSE](LICENSE).

The harness adapters are adapted from
[obra/superpowers](https://github.com/obra/superpowers) (MIT, © 2025 Jesse Vincent):
the session-start hook's branch logic and polyglot Windows wrapper, the OpenCode, Pi,
and Hermes plugins, the Gemini extension, and the per-harness tool mappings. Manifest
identity fields, skill names, and cross-references to skills this collection does not
contain were rewritten rather than copied. The skills in `skills/` are original.

[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) carries the required copyright and
permission notice, plus a file-by-file table of what was derived from what. **If you
fork this repository, that file ships with it** — MIT requires the notice to
accompany substantial portions, and a manifest `"license": "MIT"` field is not a
substitute for the text.
