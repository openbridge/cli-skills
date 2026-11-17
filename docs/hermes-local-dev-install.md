# Installing skills into Hermes Agent for local development

The documented Hermes install is `hermes plugins install <owner>/<repo>`, which
git-clones from a remote. That is no use while you are still writing the skills:
there may be no published repository yet, and every change would mean a push and
a reinstall.

This is the route that works against a working copy on disk. It uses Hermes' own
skills subsystem — no plugin, no Python, nothing to keep in sync with a harness
API. **Verified against a live Hermes session on 2026-09-28.**

## Who this is for

You have a clone of this repository, you are editing skills in it, and you want
Hermes to load them from where they already are.

If you are shipping to other people, publish and use the plugin route instead.
This one asks each user to edit two files by hand, which is exactly what a plugin
exists to avoid.

## What this route does and does not give you

Hermes' `skills.external_dirs` setting registers a directory of skills with the
native loader. That is the whole of what it does.

| | Plugin route | This route |
|---|---|---|
| Skills registered and invocable | yes | yes |
| Picked up from a working copy | no — clones a remote | yes |
| Bootstrap injected each session | yes, via `pre_llm_call` | no — you add it to `SOUL.md` |
| Code to maintain | `.hermes-plugin/__init__.py` | none |

The bootstrap is the part worth understanding. Registering skills makes them
*available*; it does not make the agent *check for one before acting*. That
behaviour comes from the `using-skills` skill, and something has to put it in
front of the model at the start of every session. The plugin does that from a
hook. Here, `SOUL.md` does it.

## 1. Point Hermes at your skills directory

Hermes keeps its state in a data directory — `~/.hermes` by default. It holds
`config.yaml`, `SOUL.md`, and a `skills/` tree.

In `config.yaml`, find the `skills:` block and fill in `external_dirs`:

```yaml
skills:
  external_dirs:
    - /absolute/path/to/your-clone/skills
  template_vars: true
  inline_shell: false
```

Point it at the `skills/` directory inside your clone, not the clone root. Use an
absolute path.

## 2. Restart and confirm registration

Restart Hermes, then:

```bash
hermes skills list
```

The three skills in this collection should appear with source `local` and status
`enabled`:

```
│ delivery-check        │  │ local  │ local  │ enabled │
│ example-skill         │  │ local  │ local  │ enabled │
│ using-skills          │  │ local  │ local  │ enabled │
```

Two things to notice in that output, because both will look like faults
otherwise:

- **No namespace prefix.** Invoke by bare name — `skill_view("using-skills")`,
  not `skill_view("skills:using-skills")`.
- **Blank category.** Hermes groups skills by directory, and this collection is
  flat (`skills/<name>/SKILL.md`). Everything lands uncategorised, which means
  the agent's own summaries of its catalogue tend to skip them. Point
  `external_dirs` at a parent containing a category directory if you want
  grouping.

If nothing appears, see [Troubleshooting](#troubleshooting).

## 3. Add the bootstrap to SOUL.md

`SOUL.md` is Hermes' global persona file. It is read fresh on every message, so
edits need no restart.

Append the `using-skills` body and the Hermes tool mapping to it. Run this from
the root of your clone, with `SKILLS_DIR` set to the same absolute path you put
in `config.yaml`:

```bash
SKILLS_DIR=/absolute/path/to/your-clone/skills
SOUL=~/.hermes/SOUL.md

{
  echo
  echo '<EXTREMELY_IMPORTANT>'
  echo 'skills:using-skills bootstrap for hermes'
  echo
  echo 'You have skills.'
  echo
  echo 'The using-skills content below is already loaded for this Hermes session.'
  echo 'Follow it now. Do not try to load using-skills again.'
  echo
  awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm' \
    skills/using-skills/SKILL.md
  echo
  echo '## Loading skills on Hermes'
  echo
  echo "Skills are registered through skills.external_dirs from \`$SKILLS_DIR\`."
  echo 'Invoke one by bare name, for example `skill_view("delivery-check")`. List'
  echo 'them with `skills_list`. If a lookup returns not-found, read the file'
  echo "directly: \`read_file(\"$SKILLS_DIR/<skill-name>/SKILL.md\")\`."
  echo
  cat skills/using-skills/references/hermes-tools.md
  echo '</EXTREMELY_IMPORTANT>'
} >> "$SOUL"
```

Re-run it after changing `using-skills` or `references/hermes-tools.md` upstream,
replacing the old block rather than appending a second one. This copy is
hand-maintained: nothing detects that it has gone stale.

The `awk` strips YAML frontmatter, and leaves a file that has none untouched —
BSD and GNU `sed` disagree about the terser one-liner, so `awk` is the portable
choice here. The body it keeps still contains the Platform
Adaptation section listing every harness's reference file — that is fine, because
the Hermes mapping is appended directly below it, and the plugin's own bootstrap
behaves the same way.

## 4. Verify it behaves

Registration and behaviour are different claims. Check both, in this order, so a
failure tells you which one broke.

**Is `SOUL.md` reaching the model?** Ask:

> Quote the skills bootstrap line from your SOUL.md.

If it cannot, nothing below matters.

**Does the bare name resolve?** Ask:

> Run skill_view on using-skills.

It should load `<your-skills-dir>/using-skills/SKILL.md`.

**Does the rule fire unprompted?** This is the only check that tests the
bootstrap rather than the plumbing. Give it a task, not a question:

> The kanban worker keeps dropping tasks, figure out why.

A working bootstrap makes it name a skill before it acts — `Using
systematic-debugging to ...` — and get the ordering right: a process skill first,
domain skills after. If it simply starts investigating, skills are registered but
the bootstrap is not carrying weight.

A natural trigger test is worth running too, since it exercises the skill
*descriptions* rather than the delivery:

> I just set up skills in this Hermes install. How do I know it's actually working?

That is the core positive case from `evals/delivery-check/trigger-cases.json`.
`delivery-check` should win it. If it does not, the description is the bug.

## Living with it

**Editing a skill.** `skill_view` reads `SKILL.md` from disk, so body edits should
be visible without a restart. Not verified — if a change does not appear,
restart before concluding anything.

**Adding or removing a skill.** Registration happens at start-up. Restart.

**Hermes writes to skill files.** This is the one that matters. Hermes has a
`skill_manage` tool and runs "self-improvement review" passes that patch
`SKILL.md` files unannounced — observed mid-session, at the end of an unrelated
debugging task, editing a builtin. Your clone is a writable directory like any
other.

Two defences, and use both:

- Keep a scratch branch checked out, not the branch you care about. Then
  `git status` after any session shows what happened and `git checkout .` undoes
  it.
- Check `git status` after *any* Hermes session that touched skills, not only
  after ones where you expected writes.

Making the directory read-only is the stronger option, but it also stops Hermes
running anything in the repo that writes — the test suite included.

**The curator.** `config.yaml` ships `curator.enabled: true` with
`stale_after_days`, `archive_after_days`, and `prune_builtins`. On paper it can
archive skills unattended. Not observed running in the session behind this
document — `interval_hours: 168` and a `min_idle_hours` gate make it rare. Set
`curator.enabled: false` if you would rather not think about it.

## Troubleshooting

**No skills entries in `hermes skills list`.** Confirm the path is absolute
and points at `skills/`, not the clone root. If the directory is right and they
still do not appear, try the parent directory instead — `external_dirs` semantics
for nested layouts are not documented, and `skills/` worked in the verified case.
Then confirm Hermes actually restarted.

**`skill_view` returns not found.** Use the bare name. If that fails, fall back
to `read_file` with the absolute path — if that works, delivery is fine and only
registration is broken.

**Bootstrap not firing.** Ask it to quote the line from `SOUL.md`. If it can and
still does not check for skills, the content is loading but not carrying weight;
`SOUL.md` is documented as a persona file, and whether Hermes gives it the
standing of a plugin-injected bootstrap is not something this route can control.

**`config.yaml` looks rewritten.** Hermes rewrites it and leaves a
`config.yaml.bak-<timestamp>`. `external_dirs` survived a rewrite in the verified
case, but re-check after a restart rather than assuming.

## If Hermes runs in a container

Everything above still applies. Two things change.

**The data directory is a mount, so paths differ inside and out.** A typical
compose file maps the host's `./.hermes` to `/opt/data` in the container. Every
path in `config.yaml` and `SOUL.md` is read *inside* the container, so it must be
a container path — `/opt/data/...`, not `~/.hermes/...`.

**Your clone has to be mounted in too**, or `external_dirs` has nothing to point
at:

```yaml
    volumes:
      - ./.hermes:/opt/data
      - /host/path/to/your-clone:/opt/clone
```

Then `external_dirs` takes the container path:

```yaml
skills:
  external_dirs:
    - /opt/clone/skills
```

Adding `:ro` to the clone's mount protects it from `skill_manage` writes. It also
blocks anything Hermes runs that writes into the repo, including this
repository's test suite. Either drop `:ro` and rely on a scratch branch, or keep
it and have Hermes copy the repo to a writable path before running tests.

Restart with `docker compose up -d` after changing the compose file or
`config.yaml`. A plain `restart` will not pick up a new volume.

Verify from the host without opening a session:

```bash
docker exec <container> hermes skills list
docker exec <container> ls /opt/clone/skills
```

The second one distinguishes a broken mount from a broken `external_dirs` —
worth knowing which before changing anything.
