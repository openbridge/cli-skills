# Deep Check

This file exists to prove one thing: that a harness delivers the **whole skill
directory**, not just `SKILL.md`, and that an agent can follow a relative link out
of a skill body to reach a sibling file.

**Phrase 2:** `walrus-escrowed-lantern`

## Why this is a separate check

A skill of one flat markdown file is the easy case, and every harness handles it.
Real skills carry supporting files — that is the shape `docs/skill-format.md`
describes and the shape `example-skill` demonstrates.

Harnesses install skills in genuinely different ways: some copy a directory, some
read from a registered path, some pass only the file they were asked for. A harness
can deliver `SKILL.md` perfectly and never ship this file at all, and nothing about
step 2 would reveal it.

If an agent reports phrase 1 but cannot reach phrase 2, multi-file skills do not
work on that harness. Record it as a partial pass, and expect any real skill with
references to fail there.

## What this does not prove

That a skill can ship an **executable script** and run it. That needs a third check,
and it depends on an unanswered question: how a skill refers to its own directory.
Claude Code exposes `${CLAUDE_PLUGIN_ROOT}`; most harnesses expose no equivalent, and
each installs skills to a different absolute path. Until that is answered per
harness, scripts in skills are unsupported here rather than untested.
