# SKILL.md format

This follows the [Agent Skills specification](https://agentskills.io/specification).
That document is the authority on frontmatter and layout; this one covers the
conventions this collection adds on top, and the reasons for them. Where the two
disagree, the specification wins — `scripts/catalog.sh` enforces its constraints
directly, including the ones a looser reading would let through.

The skill is the only unit of content in this project. Everything else — manifests,
hooks, per-harness shims — exists to deliver skills to an agent. A skill is plain
Markdown with YAML frontmatter and carries no harness-specific syntax, so the same
file ships unchanged to every harness we support.

**Skills name actions, never tools.** Write "dispatch a subagent", "track each item
as a task", "read a file" — not `Task`, `TodoWrite`, `Read`. Tool names are the one
piece of harness-specific syntax that looks harmless, and it is what breaks the
single-source promise: Antigravity has no todo tool, Pi has no skill tool, and every
harness spells file edits differently. Where the translation is needed it lives in
`skills/using-skills/references/<harness>-tools.md`, never in a skill body.

## Layout

```
skills/
  <skill-name>/
    SKILL.md              # required
    references/           # optional: documentation loaded on demand
      <topic>.md
    scripts/              # optional per the spec; see the caveat below
    assets/               # optional per the spec: templates, data, images
```

`references/`, `scripts/`, and `assets/` are the specification's own conventions.
`scripts/` carries a caveat here that is ours, not the spec's: a skill has no
portable way to refer to its own directory. Claude Code exposes
`${CLAUDE_PLUGIN_ROOT}`; most harnesses expose no equivalent and each installs to
a different absolute path. So a script can ship, but nothing in this collection
can promise an agent will be able to *run* it — see
`skills/delivery-check/references/deep-check.md`.

One directory per skill. The directory name is the skill's identity: it must match
the `name` field in frontmatter exactly, and it is what an agent types to invoke the
skill. Use lowercase kebab-case, no version suffixes.

Supporting files keep `SKILL.md` short. Put the decision-making in `SKILL.md` and
push long reference material — API surfaces, flag tables, worked examples — into
sibling files linked with relative paths.

## Frontmatter

The specification defines six fields. Two are required; the rest are optional and
**no others are permitted** — the spec directs client-specific properties into
`metadata`, and `scripts/catalog.sh` rejects any top-level key outside this set so
that a fork does not learn to invent its own.

| Field | Required | Constraint |
|---|---|---|
| `name` | yes | ≤64 chars, lowercase alphanumerics and single hyphens, no leading/trailing hyphen, no `--`, matches the directory |
| `description` | yes | ≤1024 chars, non-empty |
| `license` | no | SPDX identifier or the name of a bundled licence file |
| `compatibility` | no | ≤500 chars; environment requirements only |
| `metadata` | no | map of string keys to string values |
| `allowed-tools` | no | space-separated tool list (experimental) |

```yaml
---
name: verifying-a-data-pipeline
description: Use when a pipeline run finishes and you are about to report success, before writing any summary
license: MIT
---
```

### The supported YAML subset

`scripts/catalog.sh` parses frontmatter without a YAML library, because the
adapters do not have one either — the session-start hook and the Hermes plugin
both read frontmatter with regexes, and a format only one of the three can read
is not the format this collection ships.

So the subset is deliberately narrow, and everything outside it is **rejected
rather than half-read**:

| Supported | Not supported |
|---|---|
| Plain scalars | Multi-line block scalars (`\|`, `>`) |
| Single- and double-quoted scalars | Anchors and aliases (`&`, `*`) |
| Inline lists (`[a, b]`) and block lists | Maps nested more than one level |
| One level of nested map (`metadata:`) | Duplicate keys |

Two plain-scalar rules are worth stating because they are the ones authors hit:

- A plain scalar may not contain `: ` or ` #`. YAML reads the first as a nested
  mapping and the second as a comment.
- A plain scalar may not begin with a YAML indicator character
  (`- ? : , [ ] { } # & * ! | > ' " % @ \``).

**Quote the value** in either case, and both forms decode correctly:

```yaml
description: "Use when reviewing code: before merge"
description: 'Use when a run finishes # including partial runs'
```

An unquoted version of either was previously accepted here and rejected by any
conformant parser — the generator certifying a file the specification it cites
cannot read.

**Governance does not live here.** Whether a skill is certified, who maintains it,
what registries carry it, and where a contributed skill came from are recorded in
`catalog/entries/<name>.json`. Those are facts a skill cannot state about itself,
and putting them in frontmatter would let any contributor declare their own work
certified.

### `name`

Must equal the containing directory name, and satisfy the spec's rules above. Note
the two that a naive "lowercase and hyphens" check misses: a trailing hyphen and a
consecutive `--` are both invalid. Prefer a gerund phrase describing the activity (`writing-plans`,
`verifying-a-data-pipeline`) over a noun (`plans`, `pipeline-verification`) — it reads
correctly in the sentence "Using *writing-plans* to …".

### `description`

**This is a trigger, not a summary.** It is the only part of the skill an agent sees
when deciding whether to load the full document, so it must describe the *situation*
that should cause invocation, not the content of the skill.

Write it as a "Use when …" clause naming concrete conditions. Where ordering matters,
say so explicitly with a "before …" clause — this is what stops an agent from acting
first and consulting the skill afterwards.

| Bad | Why | Good |
|---|---|---|
| `Guidance on our REST API` | Describes content, names no trigger | `Use when calling the billing REST API, before constructing any request` |
| `Helps with debugging` | Vague, matches everything and nothing | `Use when a job fails or returns unexpected output, before proposing a fix` |
| `Pipeline docs` | Not a sentence, no situation | `Use when creating or modifying a pipeline definition` |

Keep it to one sentence. If the trigger genuinely needs more than one clause, use a
quoted string so YAML parses the commas and colons safely.

## Body

No required structure, but skills stay usable when they follow roughly this shape:

1. **Title** — `# Title Case Name`, matching the skill's subject.
2. **Overview** — two or three lines. What this covers and the single core principle
   behind it.
3. **When to use / when not to** — sharpen the frontmatter trigger with edge cases.
4. **The procedure** — numbered steps, or a table of situation → action. This is the
   part the agent follows, so make it imperative and specific.
5. **Failure modes** — the rationalizations and mistakes this skill exists to prevent,
   paired with what to do instead. A table works well.

Write for an agent that is competent but has no context on our systems and no memory
of previous sessions. Prefer concrete commands, exact field names, and real examples
over principles. If a step can be verified, say what output proves it worked.

## Scope

A skill earns its place when the technique is reusable, non-obvious, and a matter of
judgment. Anything enforceable by a linter, schema, or test belongs in that tool
instead — documentation is for decisions a machine cannot make.

Keep project-specific conventions in the relevant repository's instructions file.
Skills in this collection should apply across the projects that use them.

## Two skills that are not content

`skills/example-skill/` is the authoring template — a complete, correct skill whose
only job is to be copied. `skills/delivery-check/` is the probe that proves a harness
really delivers skills, and carries the confirmation phrases the live smoke tests
look for.

They are deliberately separate. A template that doubled as a probe could not be
freely edited without breaking verification; a probe that doubled as a template could
not be deleted once harnesses were verified.

## The bootstrap skill

`skills/using-skills/` is special. It is delivered into every session rather than
being loaded on demand, and its job is to make the agent consult the rest of the
collection. It is the only skill whose content is guaranteed to be in context, so
keep it short — every line costs tokens in every session, on every harness.

How it gets there varies. The shell-hook harnesses inject the file including its
frontmatter; the in-process plugins (OpenCode, Pi, Hermes) strip frontmatter first;
Gemini `@`-includes it from a context file; Kimi names it in its manifest; Codex and
Devin surface skills natively and inject nothing at all. Anything you add to this
skill must therefore read correctly with *or* without frontmatter, and must not
assume a hook ran. See [status.md](status.md)'s table for which harness does which.

Because it is always in context, `using-skills` is also where the per-harness tool
mappings are indexed — its Platform Adaptation section links
`references/<harness>-tools.md`. A mapping that nothing links is a mapping nothing
reads.
