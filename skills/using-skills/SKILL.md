---
name: using-skills
description: Use when starting any conversation - establishes how to find and invoke skills, and requires checking for an applicable skill before any other response or action
license: MIT
---

# Using Skills

<SUBAGENT-NOTE>
If you were dispatched as a subagent with a specific, fully-specified task, follow
that task. This skill governs how you pick up work, not how you finish it.
</SUBAGENT-NOTE>

## The rule

**Check for an applicable skill before your first response or action** — before
asking clarifying questions, before reading files, before running commands.

If a skill plausibly applies, invoke it. The cost of loading one that turns out to be
wrong is a few seconds; the cost of skipping one that applied is a whole task done the
wrong way. When in doubt, load it.

Once you've invoked a skill, say `Using [skill] to [purpose]` and follow it as written.
If it contains a checklist, track each item as a task.

## Ordering

When several skills apply, process skills run first — they decide the approach — and
domain skills carry it out.

- "Let's build X" → the planning skill first, then whatever domain skills the plan needs.
- "This is broken" → the debugging skill first, then domain skills.

## Rationalizations

These thoughts mean you are about to skip the check. Stop and check.

| Thought | Reality |
|---|---|
| "This is just a quick question" | Answering is a task. Check first. |
| "I need context before I can choose" | The skill tells you which context to gather. |
| "Let me look at the code first" | Skills tell you how to look. Check first. |
| "I already know this one" | Skills change. Read the current version. |
| "This is too small to need a skill" | Small tasks are where process quietly lapses. |
| "I'll check after this one step" | The step is the task. Check before it. |

## Platform Adaptation

Skills name actions, not tools — "dispatch a subagent", "track each item as a task"
— so that one skills directory serves every harness. Where your harness's tools
don't match those names, a reference file maps them. If yours is listed, read it
before following a skill that asks for one of those actions.

- Antigravity: `references/antigravity-tools.md`
- Codex: `references/codex-tools.md`
- Gemini CLI: `references/gemini-tools.md`
- Hermes Agent: `references/hermes-tools.md`
- Pi: `references/pi-tools.md`

OpenCode's mapping is injected with its bootstrap rather than kept here. Kimi
Code's ships inside its plugin manifest, and Devin CLI documents its own tools in
its system prompt. Every remaining harness exposes a Claude Code–compatible tool
surface — take the action names literally there.

## Precedence

Direct user instructions and repository instruction files (`CLAUDE.md`, `AGENTS.md`)
outrank skills. Skills outrank your defaults. Skip a skill's procedure only when the
user has told you to.
