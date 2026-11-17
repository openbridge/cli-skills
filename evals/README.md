# Trigger evals

`tests/run-tests.sh` proves a skill is *delivered*. Nothing in it proves a skill
is *chosen*.

A skill's `description` is the only text an agent sees when deciding whether to
load it. Get it wrong and the skill sits on disk, perfectly installed, and never
fires — or worse, fires on prompts that belong to a different skill.
`docs/skill-format.md` tells authors to write the description as a trigger and
gives them no way to check. This is the way to check.

## The shape of the problem

At one skill, a description is either good or bad on its own. At sixteen, the
failure mode changes: two descriptions compete for the same prompts, and each
one looks fine in isolation.

So a case does not assert "this skill fired." It asserts **which skill won**,
with every skill in the collection offered as a candidate:

```json
{
  "query": "I want to write a new skill for our deployment workflow.",
  "should_trigger": false,
  "expect_skill": "example-skill",
  "note": "Collision guard. Both skills are about skills; only one is about authoring."
}
```

That case lives in `evals/delivery-check/trigger-cases.json` and names a
*different* skill. `should_trigger` is the portable field — a reader that
understands nothing else still gets a correct answer from it alone. `expect_skill`
and `note` are additive and safely ignorable.

A suite with no negative case is rejected by `scripts/eval.sh --check`: positives
prove only that a skill can fire, never that it stays out of the way. Carrying
both polarities is also the documented gate for `classification: certified`.

## Running them

```bash
scripts/eval.sh --check           # structure only — no model, no cost, runs in CI
scripts/eval.sh --dry-run         # print the prompts that would be sent
scripts/eval.sh --run             # actually run them  (SPENDS MONEY)
scripts/eval.sh --run delivery-check   # one suite     (SPENDS MONEY)
```

The model call is delegated to `SKILLS_EVAL_CMD`, which receives the prompt on
stdin and prints the answer on stdout. `scripts/bare-model.sh` is the one that
has actually been run:

```bash
SKILLS_EVAL_CMD=scripts/bare-model.sh scripts/eval.sh --run
```

**Do not point it at a bare `claude -p`.** A full agent carries its *own*
installed skills and answers from those rather than from the catalog it was
handed; the first exploratory run did exactly that, returning skills that exist
nowhere in this repository. On a machine where this collection is installed the
contamination is guaranteed rather than likely.

`scripts/bare-model.sh` is that same CLI with the contamination removed —
installed skills, hooks and MCP servers all off, no tools, one completion per
prompt. It reads the file header for the reasoning behind each flag. `claude
--bare` is the documented minimal mode and would be the obvious choice, but it
reads neither OAuth nor the keychain, so it needs an `ANTHROPIC_API_KEY`; the
wrapper works from an ordinary login.

The runner reports an answer naming a skill outside the catalog as off-catalog
rather than blaming a description — that count is the contamination check, and
it should be zero. A plugin prefix on an answer (`skills:using-obcmd`) is the
other tell.

`SKILLS_EVAL_CMD` defaults to `claude -p` when `claude` is on `PATH`, which is
the contaminated path. Set it.

## Why this is not in the offline suite

`tests/run-tests.sh` is offline, free, deterministic, and gates commits. This
calls a model: it costs money, it can disagree with itself between runs, and a
flaky check that blocks a commit gets disabled within a week. Only the
structural half (`--check`) is wired into CI.

## Recording a result

```bash
scripts/eval.sh --record     # --run, plus writes evals/results.json
```

`results.json` records what passed, under which model command. It is supporting
evidence rather than the gate — the gate is that both case polarities exist,
which is checked offline and for free.

A skill is recorded as passing only when all three hold: every case in its own
suite passed, no answer named a skill outside the catalog, and no *other*
suite's case was wrongly answered with it. That last one matters — firing on
somebody else's prompts is a defect even when your own cases are green.

**First recorded run: 2026-10-27.** 50 of 50 cases matched across 13 suites,
zero off-catalog answers, all 13 skills recorded as passing. `results.json`
holds the per-skill breakdown and the model command that produced it.

The first pass, earlier the same day, matched 48 of 51 and is the reason three
things changed:

- `authenticating-obcmd` and `diagnosing-openbridge-pipelines` both claimed
  `403` in their descriptions without saying which 403. The one that spelled
  `http_403` literally won every prompt, including `job list` returning 403 for
  a single subscription — which is the missing-`--subscription_ids` trap the
  diagnosis skill documents. Both descriptions now carry the discriminator:
  every command failing versus one subscription's call failing.
- A case in `provisioning-openbridge-destinations` named the wrong
  `expect_skill`. "Point the Brand X pipeline at our existing BigQuery
  destination" is repointing, so `updating-openbridge-subscriptions` is correct
  and the model was right. The case's own assertion — keep provisioning out of
  it — had passed all along.
- The `using-skills` case on first-turn work moved to
  [using-skills/host-behavior.md](using-skills/host-behavior.md). It had been
  failing since the exploratory run, and the note explaining it had already
  worked out why: a bootstrap is injected by the session-start hook, never
  selected from a catalog, so a selection eval cannot see the behaviour it
  claims.

Two of those three were defects in the evals rather than in the skills, which is
the normal result of a first run and the reason `note` is a required habit here.

## Reading a result

Two failure kinds, reported separately because they need opposite fixes:

- **Did not fire when it should have** — the description is too narrow, or
  written as a summary rather than a trigger.
- **Fired on prompts belonging elsewhere** — the description is too broad. This
  is the one that gets worse as the collection grows, and the one a per-skill
  eval cannot see.

A miss is not automatically a bug in the skill. It can equally mean the case is
wrong, which is why every case carries a `why`: a case whose purpose nobody
recorded gets deleted the first time it fails.

A bare `scripts/eval.sh`, or a suite name without a mode flag, exits 2 and
prints the modes. The mode is always required — there is no default that spends
money by accident.
