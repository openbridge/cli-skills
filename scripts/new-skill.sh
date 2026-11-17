#!/usr/bin/env bash
# Scaffold a new skill: SKILL.md, a governance entry, and trigger cases.
#
#   new-skill.sh <name> [options]
#
#   --trigger "..."       the frontmatter trigger, minus the leading "Use when"
#   --refs                start in the multi-file shape (a references/ file, linked)
#   --classification X    certified | reference          (default: reference)
#   --origin X            first-party | third-party      (default: first-party)
#   --license X           SPDX id or bundled file name   (default: the collection's)
#   --source-repo URL     https URL the skill came from  (required: third-party)
#   --source-rev SHA      full commit hash               (required: third-party)
#
# Three files, because a skill is not only its SKILL.md:
#
#   skills/<name>/SKILL.md            the portable skill, Agent Skills spec fields only
#   catalog/entries/<name>.json       governance a skill cannot state about itself
#   evals/<name>/trigger-cases.json   does the description actually pull it in
#
# Whatever this emits must pass the repo's own validators unmodified. That is
# not a nicety: a scaffold whose output fails its own checks teaches the format
# wrong on day one, and tests/test-scaffold.sh asserts it.
#
# Dependencies: bash + python3.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

name="" trigger="" refs=0 classification="reference" origin="first-party" license=""
source_repo="" source_rev=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --trigger)        trigger="${2:-}"; shift 2 ;;
    --classification) classification="${2:-}"; shift 2 ;;
    --origin)         origin="${2:-}"; shift 2 ;;
    --license)        license="${2:-}"; shift 2 ;;
    --source-repo)    source_repo="${2:-}"; shift 2 ;;
    --source-rev)     source_rev="${2:-}"; shift 2 ;;
    --refs)           refs=1; shift ;;
    -*)               echo "unknown option $1" >&2; exit 2 ;;
    *)                [ -n "$name" ] && { echo "only one name, got $name and $1" >&2; exit 2; }
                      name="$1"; shift ;;
  esac
done

[ -n "$name" ] || { echo "usage: new-skill.sh <name> [--trigger \"...\"] [--refs] [--classification X] [--origin X]" >&2; exit 2; }

case "$classification" in
  certified|reference) ;;
  *) echo "classification must be certified or reference (got '$classification')" >&2; exit 2 ;;
esac
case "$origin" in
  first-party|third-party) ;;
  *) echo "origin must be first-party or third-party (got '$origin')" >&2; exit 2 ;;
esac

# Provenance is the author's to supply. The scaffold used to emit OWNER/REPO and
# forty zeros with a comment calling them "deliberately invalid" — but they
# satisfied every check, so an unfilled record shipped looking reviewed. A
# placeholder that cannot be generated cannot be forgotten.
if [ "$origin" = "third-party" ]; then
  if [ -z "$source_repo" ] || [ -z "$source_rev" ]; then
    echo "--origin third-party requires --source-repo <https url> and --source-rev <full commit hash>" >&2
    echo "These record what was reviewed. There is no placeholder for them." >&2
    exit 2
  fi
  case "$source_repo" in
    https://*) ;;
    *) echo "--source-repo must be an https URL (got '$source_repo')" >&2; exit 2 ;;
  esac
  if ! printf '%s' "$source_rev" | grep -Eq '^[0-9a-f]{40,64}$'; then
    echo "--source-rev must be a full lowercase commit hash (got '$source_rev')" >&2
    exit 2
  fi
  if printf '%s' "$source_rev" | grep -Eq '^0+$'; then
    echo "--source-rev is all zeros; that is not a commit" >&2
    exit 2
  fi
elif [ -n "$source_repo" ] || [ -n "$source_rev" ]; then
  echo "--source-repo/--source-rev only apply to --origin third-party" >&2
  exit 2
fi

# The Agent Skills specification's own name rules, not a looser approximation:
# max 64 characters, lowercase alphanumerics and single hyphens, no leading or
# trailing hyphen, no consecutive hyphens. https://agentskills.io/specification
if ! printf '%s' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
  echo "name must be lowercase letters, digits, and single hyphens, not starting or ending with one: '$name'" >&2
  exit 2
fi
if [ "${#name}" -gt 64 ]; then
  echo "name is ${#name} characters; the spec maximum is 64" >&2
  exit 2
fi

dir="$REPO_ROOT/skills/$name"
[ -e "$dir" ] && { echo "skills/$name already exists" >&2; exit 1; }

# A newline in a CLI value is not a long trigger, it is a second frontmatter
# line. `--trigger $'doing work\nbogus: injected'` used to add a `bogus` key to
# the generated skill, and the scaffold reported success afterwards.
for pair in "trigger:$trigger" "license:$license"; do
  field="${pair%%:*}"; value="${pair#*:}"
  case "$value" in
    *$'\n'*|*$'\r'*)
      echo "--$field may not contain a newline; frontmatter values are single-line" >&2
      exit 2 ;;
  esac
done

REPO_ROOT="$REPO_ROOT" SKILL_NAME="$name" SKILL_TRIGGER="$trigger" \
SKILL_CLASSIFICATION="$classification" SKILL_ORIGIN="$origin" \
SKILL_LICENSE="$license" SKILL_REFS="$refs" \
SKILL_SOURCE_REPO="$source_repo" SKILL_SOURCE_REV="$source_rev" python3 <<'PY'
import json
import os
import re
from pathlib import Path

root = Path(os.environ["REPO_ROOT"])
name = os.environ["SKILL_NAME"]
classification = os.environ["SKILL_CLASSIFICATION"]
origin = os.environ["SKILL_ORIGIN"]
refs = os.environ["SKILL_REFS"] == "1"
trigger = os.environ["SKILL_TRIGGER"].strip()

pkg = json.loads((root / "package.json").read_text())
license_id = os.environ["SKILL_LICENSE"].strip() or pkg.get("license", "MIT")
maintainer = (pkg.get("author") or {}).get("name") or pkg["name"]

if not trigger:
    trigger = f"TODO: the situation that should pull in {name}, phrased as a trigger"
# "Use when" is prepended, so a trigger that repeats it reads as a stutter while
# still satisfying a prefix check — silently wrong.
trigger = re.sub(r"^use when\s+", "", trigger, flags=re.I)

title = " ".join(w.capitalize() for w in name.split("-"))


def render(tmpl_name, **kw):
    text = (root / "templates" / tmpl_name).read_text()
    for key, value in kw.items():
        text = text.replace("{{" + key + "}}", value)
    return text


def yaml_scalar(value):
    """Render a string so a conformant YAML parser reads back exactly it.

    The template interpolates this straight into `description: Use when {{...}}`.
    Interpolating raw meant a trigger like "reviewing code: before merge"
    produced a line PyYAML rejects, which the repo's own parser then accepted —
    so the defect shipped looking like a working skill.
    """
    probe = "Use when " + value
    risky = (probe[0] in "-?:,[]{}#&*!|>'\"%@`"
             or re.search(r":(?:\s|$)| #", probe)
             or probe != probe.strip())
    if not risky:
        return probe
    # json.dumps is a strict subset of YAML's double-quoted scalar: same
    # escapes, same delimiters. Safe to emit, and decodes identically.
    return json.dumps(probe, ensure_ascii=False)


body = render("SKILL.md.tmpl", name=name, description=yaml_scalar(trigger),
              title=title, license=license_id)

d = root / "skills" / name
d.mkdir(parents=True)

if refs:
    (d / "references").mkdir()
    (d / "references" / "detail.md").write_text(
        render("reference.md.tmpl", name=name, title=title))
    body = body.replace(
        "Delete this section if the skill is a single file. Otherwise link every file in\n"
        "`references/` — a reference nothing links is a file no agent will ever read, and\n"
        "the integrity test fails on it in both directions.",
        "- [references/detail.md](references/detail.md) — the long-form material this\n"
        "  procedure points at.\n\n"
        "Every file in `references/` must be linked from here. A reference nothing links\n"
        "is a file no agent will ever read, and the integrity test fails on it in both\n"
        "directions.")
else:
    body = re.sub(r"\n## Supporting files\n.*$", "\n", body, flags=re.S)

(d / "SKILL.md").write_text(body)
print(f"created skills/{name}/SKILL.md")
if refs:
    print(f"created skills/{name}/references/detail.md")

# --- governance record ------------------------------------------------------
# Hand-written facts a skill cannot state about itself. Third-party skills need
# a source, and it comes from the command line: there is no placeholder to
# forget, and scripts/catalog.sh rejects the old ones if they reappear.
entry = {
    "name": name,
    "classification": classification,
    "origin": origin,
    "maintainers": [maintainer],
    "license": license_id,
    "registries": {},
}
if origin == "third-party":
    entry["source"] = {
        "repository": os.environ["SKILL_SOURCE_REPO"],
        "revision": os.environ["SKILL_SOURCE_REV"],
        "path": f"skills/{name}",
    }
entries = root / "catalog" / "entries"
entries.mkdir(parents=True, exist_ok=True)
(entries / f"{name}.json").write_text(json.dumps(entry, indent=2, ensure_ascii=False) + "\n")
print(f"created catalog/entries/{name}.json")

# --- trigger cases ----------------------------------------------------------
# Seeded with both polarities: a positive proves the skill can fire, a negative
# proves it stays out of the way, and carrying both is the documented gate for
# `certified`. A scaffold that emitted positives only would make every new skill
# uncertifiable by construction.
cases = [
    {
        "query": f"TODO: a prompt that should load {name}",
        "should_trigger": True,
        "note": "The core trigger. Write what a user would actually type, not a restatement of the description.",
    },
    {
        "query": "TODO: a prompt that should load nothing at all",
        "should_trigger": False,
        "note": "Negative. Without one, nothing tests that this skill stays quiet.",
    },
]
# A collision case IS seeded, and it names a real neighbouring skill, because a
# collision case is now required per skill rather than counted across the tree.
# The neighbour is a stand-in chosen alphabetically: it makes the suite valid
# immediately, and the closing note tells the author to point it at the skill
# this one could actually be confused with. A seeded-but-wrong neighbour is
# visible and editable; no case at all was invisible and passed.
neighbours = sorted(d.name for d in (root / "skills").iterdir()
                    if d.is_dir() and d.name != name)
if neighbours:
    cases.append({
        "query": f"TODO: a prompt that belongs to {neighbours[0]}, not to {name}",
        "should_trigger": False,
        "expect_skill": neighbours[0],
        "note": ("Collision case. Replace " + neighbours[0] + " with the skill "
                 "this one is most likely to be confused with — the stand-in is "
                 "alphabetical, not considered."),
    })
ev = root / "evals" / name
ev.mkdir(parents=True, exist_ok=True)
(ev / "trigger-cases.json").write_text(json.dumps(cases, indent=2, ensure_ascii=False) + "\n")
print(f"created evals/{name}/trigger-cases.json")
PY
rc=$?
[ $rc -eq 0 ] || exit $rc

# Everything past this point either completes or removes what it created. The
# scaffold previously announced success after catalog.sh had printed FAIL,
# leaving an invalid skill on disk for the next person to trip over: `&& echo`
# swallows the status of the command it guards.
created=("skills/$name" "catalog/entries/$name.json" "evals/$name")

rollback() {
  echo "rolling back — nothing was left behind" >&2
  for path in "${created[@]}"; do rm -rf "${REPO_ROOT:?}/$path"; done
  # The generators ran against the half-made skill; put them back in step with
  # the tree that actually exists now.
  bash "$REPO_ROOT/scripts/catalog.sh"  >/dev/null 2>&1 || true
  bash "$REPO_ROOT/scripts/registry.sh" >/dev/null 2>&1 || true
}

# Generated files must not be left stale by a command that changed their inputs.
for gen in catalog.sh registry.sh; do
  [ -x "$REPO_ROOT/scripts/$gen" ] || continue
  if out="$(bash "$REPO_ROOT/scripts/$gen" 2>&1)"; then
    echo "regenerated via scripts/$gen"
  else
    echo "scripts/$gen rejected the scaffolded skill:" >&2
    printf '%s\n' "$out" | grep '^FAIL' >&2 || printf '%s\n' "$out" >&2
    rollback
    exit 1
  fi
done

if bash "$REPO_ROOT/tests/test-skill-integrity.sh" >/dev/null 2>&1; then
  echo "tests/test-skill-integrity.sh passes"
else
  echo "tests/test-skill-integrity.sh FAILS on the scaffolded skill" >&2
  bash "$REPO_ROOT/tests/test-skill-integrity.sh" 2>&1 | grep '^FAIL' >&2
  rollback
  exit 1
fi

if out="$(bash "$REPO_ROOT/scripts/eval.sh" --check 2>&1)"; then
  :
else
  echo "scripts/eval.sh --check rejected the seeded trigger cases:" >&2
  printf '%s\n' "$out" | grep -i 'fail' >&2 || printf '%s\n' "$out" >&2
  rollback
  exit 1
fi

cat <<EOF

Next, replace the placeholders:

  skills/$name/SKILL.md            the procedure, and the frontmatter trigger
  evals/$name/trigger-cases.json   two TODO queries

A collision case was seeded pointing at an alphabetically-chosen neighbour.
Repoint its "expect_skill" at the skill this one is actually most likely to be
confused with. A positive and a negative prove this skill fires and stays quiet;
only a collision case proves two descriptions are not competing for the same
prompts, and it only proves it against the skill it names.

The description is the only text an agent sees when deciding whether to load
this skill — write it as a trigger ("Use when ..."), not a summary, and name the
nearest neighbouring case under "Not for" so two skills do not compete for the
same prompts.

Trigger cases are authored here but not run: scripts/eval.sh --run calls a model
and costs money. See the decision recorded in docs/status.md.
EOF
