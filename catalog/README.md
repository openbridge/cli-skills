# Skill catalog

`skills.json` is the machine-readable index of this collection. It is
**generated** — never hand-edited — and `scripts/catalog.sh --check` fails if it
drifts from the tree.

```bash
scripts/catalog.sh          # regenerate
scripts/catalog.sh --check  # CI gate
```

## Two sources, and why they are separate

| Source | Written by | Carries |
|---|---|---|
| `skills/<name>/SKILL.md` frontmatter | the skill author | the [Agent Skills specification](https://agentskills.io/specification)'s discovery fields |
| `entries/<name>.json` | a maintainer | governance |

The specification's fields — `name`, `description`, `license`,
`compatibility`, `metadata`, `allowed-tools` — describe what the skill *is*, and
the skill states them about itself. Those are generated from, never copied.

Governance is the set of facts a skill **cannot** state about itself: whether it
has been certified, who maintains it, what licence actually governs it, which
registries carry it, and — for a contributed skill — the exact revision that was
reviewed. A contributor can edit their own `SKILL.md`, so anything self-declared
there certifies nothing.

That is why `entries/` is hand-written and is not duplication. Nothing in it is
derivable from frontmatter, so there is nothing for it to drift from.

## classification and origin are orthogonal

```
                first-party        third-party
certified       earned, in-house   earned, contributed
reference       not yet certified  not yet certified, contributed
```

`classification` is a quality statement. `origin` is a provenance statement.
Collapsing them into a single ladder is a real mistake with two visible
symptoms: first-party work that simply has not been certified yet gets labelled
a community contribution, and a certified third-party skill becomes
inexpressible.

The public registry listing groups on both — see `scripts/registry.sh`.

## certified is earned, not declared

The gate is that the skill carries **both** positive and negative trigger cases
in `evals/<name>/trigger-cases.json`. `scripts/catalog.sh` refuses the claim
otherwise, and `tests/test-registry.sh` proves the refusal works.

Positives alone prove only that a skill can fire. Whether it stays out of other
skills' way is the half that decays as a collection grows, and it is the half
that matters once two descriptions start competing for the same prompts.

`evals/results.json`, written by `scripts/eval.sh --record`, records what
actually passed. It is supporting evidence rather than the gate — producing it
costs money, and gating on it would make certification unreachable while that
budget is zero. See the decision in [docs/status.md](../docs/status.md#decisions-to-revisit).

## Third-party entries need a source

```json
{
  "name": "example-skill",
  "classification": "reference",
  "origin": "third-party",
  "maintainers": ["Someone Else"],
  "license": "Apache-2.0",
  "registries": {},
  "source": {
    "repository": "https://github.com/owner/repo",
    "revision": "<full commit hash>",
    "path": "skills/example-skill"
  }
}
```

`revision` must be a full commit hash, not a branch or tag. Without an immutable
revision there is no statement of *what was reviewed* — a tag can move, and a
branch certainly will.

## Adding a skill

`scripts/new-skill.sh <name>` writes the `SKILL.md`, the governance entry, and a
seeded `trigger-cases.json` in one step, then regenerates this catalog. Doing it
by hand means remembering all three.
