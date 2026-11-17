---
name: example-skill
description: Use when authoring a new skill in this collection, before writing any SKILL.md, to copy a correct structure
license: MIT
---

# Example Skill

## Overview

A correct, complete skill with nothing in it. The structure is the point.

**Do not copy this directory by hand.** A skill is three files, and `new-skill.sh`
writes all three; copying gets you one and leaves the collection inconsistent
until someone notices. Use the scaffold, then edit what it produced — this file
shows you what "edited well" looks like.

**Core principle:** the frontmatter `description` decides whether a skill is ever
loaded. Everything else only matters afterwards.

`docs/skill-format.md` is the contract this file obeys, and behind it the
[Agent Skills specification](https://agentskills.io/specification) is the
authority on frontmatter. This file is the worked example of both.

## When to use

- Starting a new skill and wanting a correct skeleton to edit.
- Checking the expected section order before a review.

**Not for:** verifying that a harness delivers skills — that is
[delivery-check](../delivery-check/SKILL.md), which carries the confirmation phrases.
This skill deliberately has none, so that finding it proves nothing.

**Also not for: reviewing the system you are documenting.** Reading a CLI, an API,
or its docs in order to write a skill about it is in scope and usually necessary.
Returning a verdict on what you read is not. A fact earns a place in the skill when
an agent following the skill needs it to succeed — "`--token` echoes into shell
history, use the env var" is a step; "this tool stores credentials insecurely" is a
finding. Security review, code review, performance analysis, and bug reports against
the documented system belong to other agents in other repositories. Notice one
anyway, write a line in `OBSERVATIONS.md` and carry on. The boundary and the reasons
behind it are in [AGENTS.md](../../AGENTS.md).

## The procedure

1. **Run the scaffold**, naming the skill for the *activity*, in lowercase
   kebab-case. Prefer a gerund — `verifying-a-pipeline`, not
   `pipeline-verification`. It has to read correctly in the sentence
   "Using *verifying-a-pipeline* to …".

   It writes three files, because a skill is not only its `SKILL.md`:

   | File | What it carries |
   |---|---|
   | `SKILL.md` | the portable skill — spec frontmatter fields only |
   | `catalog/entries/<name>.json` | governance the skill cannot state about itself |
   | `evals/<name>/trigger-cases.json` | whether the description actually pulls it in |

   Names obey the specification: at most 64 characters, lowercase alphanumerics
   and single hyphens, never starting or ending with a hyphen, never two hyphens
   in a row.

2. **Leave `name` matching the directory exactly.** A mismatch makes the skill
   invisible on most harnesses, with no error.

   Keep frontmatter to the six fields the specification defines. Anything else
   belongs under `metadata`, and the catalog generator rejects stray top-level
   keys rather than passing them through — including governance, which lives in
   the entry file so that nobody can certify their own work by editing it.

3. **Write `description` as a trigger, not a summary.** It is the only text an agent
   sees when deciding whether to load the skill, so it must describe the *situation*
   that should cause invocation:

   | Instead of | Write |
   |---|---|
   | `Guidance on our REST API` | `Use when calling the billing REST API, before constructing any request` |
   | `Helps with debugging` | `Use when a job fails or returns unexpected output, before proposing a fix` |

   Where order matters, say so with a "before …" clause. That clause is what stops an
   agent acting first and consulting the skill afterwards.

4. **Name actions, never tools.** Write "dispatch a subagent", "track each item as a
   task", "read a file" — never the literal name your harness gives that tool. This
   is what lets one `skills/` directory serve every harness: the todo tool is absent
   on one, the skill tool on another, and file edits are spelled differently on most.
   Translations belong in `skills/using-skills/references/`.

   CI enforces this, and it does not exempt this file — which is why the sentence
   above describes the forbidden names instead of listing them.

5. **Push long material into a supporting file.** Keep the decisions in `SKILL.md`
   and move flag tables, API surfaces, and worked examples beside it — see
   [references/supporting-file.md](references/supporting-file.md) for the shape.

6. **Write for an agent with no memory and no context on your systems.** Concrete
   commands, exact field names, real examples. If a step can be verified, say what
   output proves it worked.

7. **Add a collision case** to the seeded trigger cases: a prompt belonging to the
   nearest neighbouring skill, marked as not triggering this one and naming the
   skill that should win instead. The scaffold seeds a positive and a negative,
   which prove the skill can fire and can stay quiet. Only a collision case proves
   it is not taking prompts that belong elsewhere — and that is the failure that
   grows as a collection does, because each description still looks fine alone.

8. **Stop when the checks are green.** The skill is finished when the three files
   exist with `name` matching the directory, the offline tests pass, the eval
   structure check passes, and the trigger cases carry both polarities including a
   collision. Say so and stop.

   Unread source material does not make a finished skill unfinished — most of what
   can be read about a system is not needed in order to use it. No step above asks
   you to assess the system itself, and there is no step nine.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Skill never triggers | `description` summarises content instead of naming a situation | Rewrite as "Use when …" |
| Skill is invisible to the agent | `name` does not match the directory | Make them identical |
| Agent acts first, consults the skill after | No ordering clause in the trigger | Add "before …" |
| Skill works on one harness only | A tool name leaked into the body | Move it to a `references/` mapping |
| Skill is ignored as obvious | It documents what a linter or test already enforces | Delete it; skills are for judgment |
| Two skills fight over the same prompts | Neither description names the other's territory | Add a "Not for" line, and a collision case to both |
| Catalog generation rejects the skill | A non-specification key in frontmatter | Move it under `metadata`, or into the governance entry |
| The skill states a verdict where it should state a step | Source material got read as a subject for review | Turn the fact into a procedure step, or drop it |
| Authoring never ends; the response is half audit | No completion test, so every unread page looks like remaining work | Run step 8's checks — green means stop |
