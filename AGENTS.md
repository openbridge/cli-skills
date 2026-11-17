# Working in this repository

This repository produces skills. A skill is three files: `SKILL.md`, a catalog
entry, and an eval case. Everything else here — manifests, hooks, per-harness
shims, tests — exists to deliver those files to an agent.

Authoring one is the whole job. `skills/example-skill/SKILL.md` is the
procedure; `docs/skill-format.md` is the format.

## Reading a source system is in scope. Judging it is not.

Writing a skill about a CLI, an API, or a service means reading it — help
output, docs, error messages, sometimes source. Do that freely and thoroughly.

What comes back is **source material for a skill**, not a subject for review. A
fact about the source earns a place in the skill when an agent following that
skill needs it to succeed:

| In scope — changes what the skill says | Out of scope — a verdict on the system |
|---|---|
| `--token` echoes into shell history; tell the agent to use the env var | this tool stores credentials insecurely |
| `--force` skips confirmation and cannot be undone; require a dry run first | this tool has unsafe defaults |
| pagination truncates at 100 with no error; tell the agent to follow the cursor | this API has a correctness bug |

The left column is a step in a procedure. The right column is a finding. This
repository ships the left column.

## Not this repository's job

- Security review, threat modelling, credential-exposure or vulnerability reports
- Code review, refactor proposals, performance analysis
- Bug reports against the system being documented
- Fixing, patching, or hardening anything outside this repository

Other agents do that work, in other repositories, where someone asked for it. An
unreviewed system is not a loose end in this task.

## When you notice one anyway

Append one line to `OBSERVATIONS.md` — what you saw, and where — then carry on
with the skill. Do not expand on it in your response, do not investigate it
further, do not open an issue, and do not reshape the skill to work around it.

That file is a drain, not a backlog. Nothing here acts on it; a human reads it
when they choose to.

## Done

A skill is finished when all of these hold:

- the three files exist, and `name` matches the directory exactly
- `tests/run-tests.sh` passes
- `scripts/eval.sh --check` passes
- the trigger cases carry both polarities, including one collision case

Nothing else is part of the task. **Unread source material does not make a
finished skill unfinished** — most of what can be read about a system is not
needed in order to use it. When that list is green, stop and say so.
