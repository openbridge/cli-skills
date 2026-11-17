# Codex Tool Mapping

Skills speak in actions ("dispatch a subagent", "wait for it to finish"). On Codex
those actions resolve to the multi-agent tools below — but only once multi-agent
support is switched on.

## Subagent dispatch requires multi-agent support

Add to `~/.codex/config.toml`:

```toml
[features]
multi_agent = true
```

Without this, no subagent tools exist at all, and a skill that says "dispatch a
subagent" has no target. Exactly which tools appear depends on what your model
preset selects, so read your tool list rather than assuming the set below is
complete.

**Trust your actual tool list and your current developer instructions over this
file whenever they disagree.** This mapping is checked into a skills collection
and loaded into every Codex session; the harness ships on its own schedule. It
describes stable action-to-tool correspondences, and deliberately avoids pinning
behaviour that moves between releases — where a detail here has aged, the tool
schema in front of you is right and this file is wrong.

## Spawning

| Action a skill requests | Codex equivalent |
|---|---|
| Dispatch a subagent | `spawn_agent` |
| Send a follow-up to a running subagent | `followup_task` |
| Wait for subagents to finish | `wait_agent` |
| See what's running | `list_agents` |

- **Give children a clean context:** `spawn_agent {fork_turns: "none"}`. The default
  `"all"` copies your entire transcript into the child.
- **Fix rounds:** if `followup_task` is in your tool list, resume the existing
  implementer with it — it delivers your message, triggers a turn, and
  transparently reloads a child the harness evicted. Do not dispatch a fresh
  subagent on the theory that a spawned agent cannot be messaged again.
- **Lifecycle:** if your tool list has no `close_agent`, finished children are
  evicted automatically when slots are needed and leaving them unclosed costs
  nothing. If it does, close them. Check the list rather than assuming a version.
- **Model names:** never copy a model name out of a skill, a table, or an old
  session into `spawn_agent`. Take it from your current spawn allowlist, which is
  the only thing that knows what this runtime accepts.

## Model routing on spawns

**Default to omitting `model` and `reasoning_effort`** so a child inherits the
parent's. Set them when the task genuinely calls for a different tier — a cheap
mechanical fan-out, or one stage that needs more depth than the rest — and not as
a blanket policy.

Two things to know when you do set them:

- Setting `model` alone can reset the child's effort to that model's default
  rather than carrying yours over. If you override one, decide about the other.
- Your spawn allowlist is the authority on what is accepted.

If a fan-out should default to a cheaper tier than the session model, that belongs
in configuration rather than in every call site:

```toml
[agents]
default_subagent_model = "<a mid-tier model from your spawn allowlist>"
default_subagent_reasoning_effort = "medium"
```

## Waiting on children

`wait_agent` is an **event subscription, not a poll**. A long wait wakes the moment
a child produces mailbox activity, with the same latency as a short one. Short
polling buys nothing and costs a tool call — and a context rebill — every time.

- While you still have local work, **do not wait at all.** A completed child's final
  answer is pushed to your mailbox and arrives with your next turn.
- When you are genuinely idle with children outstanding, wait in bounded stretches:
  `wait_agent` with `timeout_ms` of 300000–600000 (5–10 minutes). After each stretch
  — wake or timeout — post one status line, run `list_agents`, and chase any child
  that finished without reporting.
- Never stack polls shorter than five minutes. A stretch that times out with no
  activity is your cue to reconcile, not to shorten the next one.

## Environment detection (Codex App)

The Codex App sandbox can run you in an externally managed worktree on a detached
HEAD, where branch and push operations are blocked. Skills that create branches or
worktrees should check first, with read-only git commands:

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

- `GIT_DIR != GIT_COMMON` → already in a linked worktree; skip worktree creation
- `BRANCH` empty → detached HEAD; you cannot branch, push, or open a PR

When branch/push is blocked, commit the work and hand off to the App's native
controls — **Create branch**, or **Hand off to local**. You can still run tests,
stage files, and output a suggested branch name, commit message, and PR description
for your human partner to use.
