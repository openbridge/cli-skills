# Plugin evals

End-to-end routing cases for the official `claude plugin eval` harness.

## How these differ from `evals/`

| | `evals/<skill>/trigger-cases.json` | `plugin-evals/<case>/case.yaml` |
|---|---|---|
| Question | Given the catalog, which description wins? | Does the installed plugin actually load the skill? |
| Runner | `scripts/eval.sh` | `claude plugin eval` |
| Path | A single completion against a list of descriptions | A real multi-turn agent session with the plugin installed |
| Cost | Cents | Dollars |

The first can be wrong about the real world: it proves a description
discriminates in isolation, not that the harness surfaced it, that the `Skill`
tool fired, or that the bootstrap reached the session. The second proves the
whole path and costs accordingly.

## These have never been run

**So their grammar is unverified.** `tests/test-evals.sh` checks the structure
these files obviously need — `schema_version`, a `name`, an `execution.prompt`,
and graders carrying a `name` and `type` — which catches a typo or a missing
key. It cannot check them against the real `claude plugin eval` schema, because
only that tool knows it. Treat a first run as debugging the cases as much as
the routing.

Authoring them is free; running them is not. A recorded pass over three cases
with `--ablation with-without --runs 3` came to **$4.68**, because each case
becomes six full agent sessions plus grader calls.

The decision not to run them is recorded in [docs/status.md](../docs/status.md#decisions-to-revisit),
with the numbers, so it can be revisited against evidence rather than memory.

When it is revisited, start small and cap it:

```bash
claude plugin eval plugin-evals/delivery-check-routing/case.yaml \
  --ablation none --runs 1 --threshold 1.0 --max-cost-usd 1 --no-publish
```

`--ablation none --runs 1` is one session per case. The with/without ablation is
what multiplies cost, and it answers a different question — whether the plugin
*caused* the routing — which is worth paying for once, not every run.

## Grader notes

Two graders per case, because they fail independently:

- `tool_used` — the `Skill` tool fired with the right skill. The regex tolerates
  an optional `<collection>:` prefix, since the namespace changes when a fork
  renames the collection.
- `regex` on the trace — the selection was announced. `using-skills` instructs
  the agent to say `Using [skill] to [purpose]`, and an agent can route
  correctly while ignoring that instruction. Tom's run hit exactly this: correct
  leaf in 9/9 runs, announcement grader failed on a paraphrase. Worth keeping
  separate so a paraphrase is not read as a routing defect.
