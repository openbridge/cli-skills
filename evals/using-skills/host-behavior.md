# using-skills — host behaviour record

`using-skills` is not selected from a catalog. The session-start hook injects it
before the user's first message, so the question "did the agent choose this
skill?" has no answer for it — there is no choice to make. A trigger eval asks
exactly that question, which is why one of these cases kept failing while the
skill was working correctly in every live session.

What can be observed is whether the host **delivered** the bootstrap and whether
the agent then **acted** on it. That is host behaviour, and it needs a real
session rather than a completion. One row per observation; `not run` with a
reason is a more useful cell than a blank one.

The format is the sibling-collection one described in
[docs/live-smoke-tests.md](../../docs/live-smoke-tests.md#a-stronger-record-than-a-checklist):
client and version, install route, the prompt or event, expected versus
observed, status, and notes including cost.

## Rows

| Date | Client + version | Install route | Prompt or event | Expected | Observed | Status | Notes |
|---|---|---|---|---|---|---|---|
| 2026-10-27 | Claude Code 2.1.226 | local plugin, source tree | session start, before any user message | the bootstrap text arrives in context without the agent reading a file | arrived; `using-skills` body present at the first turn, no file read | pass | observed in an ordinary working session, not a scripted check — worth re-running as one |
| not run | — | — | first-turn ordinary work: "Help me figure out why this test started failing yesterday." | the agent checks for an applicable skill before its first action, per the skill's own rule | — | not run | **this is the claim that moved here from `trigger-cases.json`.** Needs a live session: the behaviour is "did the agent consult the list it was handed", which a one-shot selection prompt cannot see |
| 2026-10-27 | Claude Code 2.1.226, isolated via `scripts/bare-model.sh` | catalog pasted into the prompt | "Help me figure out why this test started failing yesterday." | — | `NONE` | n/a | kept as context for why the case moved. A bare completion is handed a catalog and asked to pick from it; a bootstrap is never in that position. The answer is correct for the question asked and tells us nothing about the skill |

## Why the last row is not a failure

The eval asks a model to choose the most specific applicable skill from a list.
`using-skills` is written to apply to almost everything, so in a selection
contest it either loses to a specific skill — which is the behaviour its own
negative case asserts — or wins over one, which would be the defect. `NONE` on
open-ended work is the consistent answer to that question.

The skill's actual claim is upstream of the contest: *a check happens at all*.
Testing it means watching a session, not scoring a completion.
