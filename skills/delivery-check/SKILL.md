---
name: delivery-check
description: Use when bringing up a new harness and confirming that skills are actually being discovered, loaded, and read end to end
license: MIT
---

# Delivery Check

## Overview

This skill does no work. It exists to make skill delivery *observable* — to prove a
harness is genuinely discovering, loading, and reading files from this collection
rather than appearing to.

**Core principle:** A skill is only installed if an agent can be observed using it.

It was previously named `example-skill` and served double duty as an authoring
template. That is now [example-skill](../example-skill/SKILL.md); this file is only
the probe. The two jobs pulled opposite ways — a probe should be minimal and
deletable, a template should show the real shape.

## When to use

- Bringing up a new harness and confirming the delivery path works.
- After changing a manifest, hook, or plugin, to confirm nothing quietly broke.

**Not for:** anything in real work. Delete this skill once your harnesses are
verified — unlike `example-skill`, nothing here is worth keeping.

## The check

Each step proves a different layer, and each has its own phrase. Run them in order
and record which ones passed: a partial result tells you *where* delivery broke,
which a single pass/fail cannot.

### Step 1 — the bootstrap arrived

Start a **completely fresh session**. No pasted prompt, no `/skill` invocation, no
prior context. Ask:

> What skills do you have available?

**Pass:** the agent names this collection and lists its skills without reading any
file first.

If you had to do anything to make skills available, that is a fail regardless of
what comes after. An integration requiring per-session opt-in is not an integration.

### Step 2 — the skill body was read

Ask the agent to use `delivery-check`, then to quote the phrase below.

**Phrase 1:** `pelican-notarized-drift`

### Step 3 — relative references resolve

Ask the agent to follow this skill's reference file and report the phrase it finds:

- [references/deep-check.md](references/deep-check.md)

That file carries **phrase 2**. Step 2 passing while step 3 fails means the harness
delivers a skill body but not the files beside it — a skill of more than one file
will not work there, even though this probe's first half looks healthy.

## Reading the result

| Step 1 | Step 2 | Step 3 | Diagnosis |
|---|---|---|---|
| ✅ | ✅ | ✅ | Delivery works, including multi-file skills. |
| ✅ | ✅ | ❌ | Skill body ships; sibling files do not resolve. Check how the harness installs a skill *directory* rather than a file. |
| ✅ | ❌ | — | Bootstrap arrives but skills do not load. Check the manifest's skills path and that `name` matches the directory. |
| ❌ | ✅ | — | Skills load but the bootstrap never arrives. Check the session-start mechanism — for shell-hook harnesses, the JSON field being emitted. |
| ❌ | ❌ | — | The plugin is probably not loaded at all. |

## Why the phrases are arbitrary

A guessable phrase proves nothing. An agent that never opened this file can produce
"delivery confirmed" from the skill's *name* alone, and will, confidently.

An agent that cannot produce these exact words has not read this file, whatever else
it reports. Treat that as a failed install.

## Failure modes

| Symptom | Likely cause |
|---|---|
| Agent invents a plausible answer instead of the phrase | Skill was never loaded; it is guessing from the name |
| Agent finds the skill only after you name the file path | Discovery is not working; you are hand-feeding it |
| Bootstrap missing at session start | Session-start mechanism not wired, or emitting the wrong JSON shape for this harness |
| Skill invisible to the agent | Manifest not pointing at `./skills/`, or `name` does not match the directory |
| Everything invisible, no error anywhere | The plugin failed to load. Some harnesses disable a plugin silently on an internal error — check the harness's plugin state, not just its output |

## Recording results

`docs/live-smoke-tests.md` is the checklist across every harness, and `docs/status.md`'s
status table is where results are recorded. Note which steps passed, not just
whether the harness "works".
