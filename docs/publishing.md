# Publishing

Everything that has to be right **before** the repository is made public, and
why after is too late.

## The constraint that drives all of this

**Corrected 2026-09-25.** This document previously said public registries
discover collections by crawling public repositories on their own schedule, and
built an urgency argument on top of it. That is not how skills.sh works, and the
urgency argument went with it.

What the [skills.sh documentation](https://www.skills.sh/docs/customize)
actually says:

> skills.sh picks up `skills.sh.json` after the repository is installed with the
> `skills` CLI with telemetry enabled.

> Each install checks the file on your default branch in the background.
> Visiting the repo page does not trigger a GitHub check.

So the mechanism is **reactive, not exploratory**. Nothing indexes this
repository because it exists. A repository page appears once someone installs a
skill from it through the CLI with telemetry on, and `skills.sh.json` is read on
the default branch at that point and on later installs.

Two consequences, and they point in opposite directions from the old ones:

- **There is no crawler to miss.** Being unready on a particular day costs
  nothing, because no scheduled pass is going to look and give up. The file is
  re-read on the next install.
- **Nothing happens without a first install.** The listing is downstream of
  adoption, so the work that actually surfaces a collection is the install path
  in the README — not the descriptor.

The checklist below is still worth doing before going public. The reason is
narrower: the first person to install should not be the one who discovers the
descriptor is malformed.

## 1. The registry descriptor

`skills.sh.json` in the repository root is the listing: how the collection is
grouped and rendered. It is generated:

```bash
scripts/registry.sh          # regenerate
scripts/registry.sh --check  # CI gate
```

It conforms to `https://skills.sh/schemas/skills.sh.schema.json`, which is not
our schema — `tests/test-registry.sh` enforces its constraints (grouping and
name length limits, `additionalProperties: false`, 1–50 groupings) because
violating someone else's schema produces a listing that silently does not
appear rather than an error.

Groupings come from each skill's `classification` and `origin`, so the listing
is a view of the catalog rather than a second place to maintain the same facts.

### skills-lock.json is deliberately not generated here

A published lockfile carries a `computedHash` per skill. That hash is **not** a
plain sha256 of `SKILL.md` — checked against a real one, it matches neither the
raw bytes, the frontmatter-stripped body, the trimmed text, nor a line-ending
normalisation. It is produced by the `skills` CLI (`npx skills add`).

Generating one with invented hashes would produce a file that looks correct and
is worthless, which is worse than shipping none. Leave it to the CLI.

## 2. Certification has to mean something

`classification: certified` in `catalog/entries/<name>.json` drives a registry
grouping titled "Certified". If an entry alone could grant it, that grouping
would certify nothing.

The gate is that the skill carries **both positive and negative trigger cases**
in `evals/<name>/trigger-cases.json`. `scripts/catalog.sh` refuses the claim
otherwise, and `tests/test-registry.sh` proves the refusal works. Positives
alone prove only that a skill can fire; whether it stays out of other skills'
way is the half that decays as a collection grows.

Governance lives in the entry, never in frontmatter, for the same reason: a
contributor can edit their own `SKILL.md`, so a classification declared there
would certify nothing.

`scripts/eval.sh --record` additionally writes `evals/results.json` recording
what actually passed. That is supporting evidence, not the gate — and it costs
money to produce, which is why certification lags in practice. Expect it to.

### origin is not a quality ladder

`origin` (`first-party` / `third-party`) is tracked separately from
`classification`. A first-party skill that has not been certified yet is not a
community contribution, and a third-party skill can be certified. A third-party
entry must record the repository, an immutable revision, and the path — without
a revision there is no statement of what was reviewed.

## 3. Repository discoverability

Beyond the descriptor, the repo itself is the search surface:

- **Topics.** The tags a scanner reads to classify the repo. Set them before
  publishing:
  ```bash
  gh repo edit <owner>/<repo> \
    --add-topic agent-skills --add-topic claude-code --add-topic skills \
    --add-topic ai-agents --add-topic mcp
  ```
- **Description.** One line naming what the collection does, not what it is
  built with.
- **README above the fold.** What the skills do and how to install, before any
  discussion of architecture.

## 4. Re-baseline the history first

The usual sequence is: private repo to get the work off a laptop, then make it
public. The history written while private was not written to be read.

Squash to a single initial commit before flipping visibility. Not for
tidiness — anything removed along the way is still recoverable from an earlier
commit by anyone who looks, and a public first impression of fifty
work-in-progress commits is a different artifact from a first release.

**This is a destructive, history-rewriting operation on a shared branch.** Read
the whole section before running any of it.

**What it does and does not remove.** Locally it removes nothing. The old
commits stay reachable through the reflog, through any other branch or tag that
points at them, and through every existing clone. Until the remote is force-
updated and re-packed, they are reachable there too, and a fork or an open pull
request can keep them alive indefinitely. Treat this as *changing what the
default branch shows*, not as redaction. **If a secret was ever committed, this
does not remove it — rotate the credential.**

```bash
# 1. Back up. A branch and a tag, so neither a branch delete nor a reflog
#    expiry is the single point of failure.
git branch pre-release-backup
git tag    pre-release-backup-$(date -u +%Y%m%dT%H%M%SZ)
git push origin pre-release-backup --tags

# 2. Confirm the tree is exactly what should be public, BEFORE rewriting.
git status --short          # must be clean
git ls-files | less         # every path here becomes public
bash tests/run-tests.sh

# 3. Build the new history on an orphan branch.
git checkout --orphan release
git add -A
git commit -m "Initial release"

# 4. Compare against the branch it replaces. An empty diff means the rewrite
#    changed history without changing content, which is the intent.
git diff --stat main release

# 5. Move it into place locally.
git branch -M release main
```

Pushing it is a separate decision:

```bash
# Branch protection will reject a force-push; lift it, push, restore it.
gh api -X DELETE repos/:owner/:repo/branches/main/protection   # if protected
git push --force-with-lease origin main
```

`--force-with-lease`, never `--force`: it refuses if the remote moved since you
last fetched, which is the difference between replacing your own history and
silently discarding a collaborator's.

**Afterwards, verify rather than assume:**

```bash
git log --oneline origin/main        # one commit
git ls-remote --heads origin         # no stray branches carrying old history
```

Then delete the backup refs only once the public history has been checked, and
re-run `gh repo view` to confirm the default branch is what you expect. Anyone
with an existing clone still has the old history and will need to re-clone.

## Pre-publication checklist

- [ ] `bash tests/run-tests.sh` passes
- [ ] `scripts/identity.sh --check` passes with no origin warning
- [ ] `scripts/identity.sh --audit` clean
- [ ] `scripts/registry.sh --check` passes
- [ ] `scripts/eval.sh --record` run against a bare model call, results committed
- [ ] Repository topics and description set
- [ ] History re-baselined to a single initial commit
- [ ] LICENSE and THIRD_PARTY_NOTICES.md present and accurate
- [ ] `docs/live-smoke-tests.md` reflects what has actually been verified live
