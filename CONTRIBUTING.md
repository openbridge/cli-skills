# Contributing

This repository is a **template**. Most people arriving here should fork it and
build their own collection rather than add skills to this one — see
[Renaming a fork](README.md#renaming-a-fork) in the README.

What follows applies whether you are contributing here or working in a fork.

## Before anything else

```bash
bash tests/run-tests.sh
```

Eleven offline suites, no dependencies beyond bash, `python3`, and `node`. They
cost nothing and run in about two seconds. Everything below assumes they pass
before you start, so a failure is yours rather than inherited.

## Adding a skill

```bash
scripts/new-skill.sh my-skill --trigger "the situation that should pull it in"
scripts/new-skill.sh my-skill --refs     # start in the multi-file shape
```

A skill is three files, and the scaffold writes all three because remembering
them by hand is how one gets skipped:

| File | What it is |
|---|---|
| `skills/<name>/SKILL.md` | the portable skill — Agent Skills spec fields only |
| `catalog/entries/<name>.json` | governance the skill cannot state about itself |
| `evals/<name>/trigger-cases.json` | does the description actually pull it in |

Then replace the placeholders. Three things are worth more care than the rest.

### The description is a trigger, not a summary

It is the **only** text an agent sees when deciding whether to load the skill.
Write it as a "Use when …" clause naming concrete situations. Where ordering
matters, say so — a "before …" clause is what stops an agent acting first and
consulting the skill afterwards.

Then name the nearest neighbouring case under *Not for*. At one skill a
description is either good or bad on its own; at sixteen, the failure mode is
two descriptions competing, and each looks fine in isolation.

### Skills name actions, never tools

Write "dispatch a subagent", "track each item as a task", "read a file" — not
`Task`, `TodoWrite`, `Read`. That is the entire reason one `skills/` directory
serves every harness here. Where a harness's tools differ, the translation goes
in `skills/using-skills/references/<harness>-tools.md`.

`tests/test-skill-integrity.sh` fails on a skill body naming a harness tool.

### Add a collision case

The scaffold seeds a positive and a negative. Add a third: a prompt that belongs
to the nearest neighbouring skill, with `"should_trigger": false` and
`"expect_skill": "<that-skill>"`.

A positive proves your skill can fire. A negative proves it stays quiet. Only a
collision case proves it is not stealing another skill's prompts.

## Frontmatter is the spec's, not ours

Six fields, two required, and **no others**:

| Field | Required | Constraint |
|---|---|---|
| `name` | yes | ≤64 chars, lowercase alphanumerics and single hyphens, no leading/trailing hyphen, no `--`, matches the directory |
| `description` | yes | ≤1024 chars |
| `license` | no | SPDX id or bundled licence file name |
| `compatibility` | no | ≤500 chars, environment requirements only |
| `metadata` | no | map of string keys to string values |
| `allowed-tools` | no | space-separated, experimental |

The [specification](https://agentskills.io/specification) directs
client-specific properties into `metadata`, so `scripts/catalog.sh` rejects any
other top-level key. This is deliberate: a collection that invents its own
fields teaches every fork downstream to invent different ones.

Governance — `classification`, `origin`, `maintainers`, `registries`, `source` —
never goes in frontmatter. See [catalog/README.md](catalog/README.md).

## Certification

`classification: certified` in a governance entry places the skill in a
"Certified" grouping in the public registry listing. The gate is that the skill
carries both positive **and** negative trigger cases; `scripts/catalog.sh`
refuses the claim otherwise.

Do not set it on your own contribution. It is a maintainer's statement that a
review happened.

## Things that cost money

`scripts/eval.sh --run` and `claude plugin eval` call real models and bill a real
account. They are behind explicit flags for that reason, and a bare
`scripts/eval.sh` does nothing but explain them.

**Do not run them without asking.** Authoring cases is free; executing them is
not. The current decision not to spend, with the numbers behind it, is recorded
in [docs/status.md](docs/status.md#decisions-to-revisit).

## Renaming a fork

```bash
scripts/identity.sh rename your-collection-name
scripts/identity.sh --check
scripts/identity.sh --audit
```

One command covers ten manifests, the bare-string literals in the in-process
plugins, and two filenames that `package.json` references by path. `--audit`
then greps for anything the declarative map did not know about.

If you add a harness, register its manifest in `.skills-identity.json` **in the
same commit** — `tests/test-identity.sh` fails on a manifest that exists in the
tree and is not registered, which is what stops the drift returning.

## Before opening a pull request

```bash
bash tests/run-tests.sh          # 12 suites
scripts/identity.sh --check      # manifests agree
scripts/identity.sh --audit      # no untracked copies of the name
scripts/catalog.sh --check       # catalog current
scripts/registry.sh --check      # registry listing current
scripts/eval.sh --check          # trigger cases well-formed
claude plugin validate . --strict
```

All free, all offline. CI runs the suite on Linux and macOS, and the generators
are checked there too — so a stale generated file fails the build rather than
landing quietly.

## Documentation is part of the change

If a change makes a document wrong, fix it in the same commit. A stale doc is
worse than a missing one because it is believed.
