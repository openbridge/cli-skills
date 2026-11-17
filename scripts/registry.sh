#!/usr/bin/env bash
# Generate skills.sh.json — the registry descriptor public skill registries read.
#
#   registry.sh            regenerate skills.sh.json
#   registry.sh --check    fail if it is stale (for CI)
#
# Why this exists separately from catalog/skills.json: the catalog is this
# project's own format and serves its own consumers. skills.sh.json is somebody
# else's schema (https://skills.sh/schemas/skills.sh.schema.json) and is how a
# registry groups and renders the collection. Both are generated from the same
# frontmatter, so neither is hand-maintained.
#
# This file does NOT cause discovery, and an earlier version of this comment said
# it did. skills.sh reads it after someone installs a skill from the repository
# with the `skills` CLI and telemetry enabled, and it only changes how an already
# listed repository page renders: "This file only changes the display on
# skills.sh." Each install re-checks it on the default branch.
# https://www.skills.sh/docs/customize
#
# So a stale or invalid descriptor is not a missed crawl, it is a bad first
# impression for whoever installs first. Generated rather than hand-written for
# that reason, and validated against the published schema in CI.
#
# NOT generated here: skills-lock.json. That file carries a `computedHash` per
# skill which the `skills` CLI produces; it is not a plain sha256 of SKILL.md
# (verified against a published lockfile, which matches none of the obvious
# normalisations). Writing one with invented hashes would be worse than shipping
# none, so it is left to `npx skills add` to create.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

python3 - "$@" <<'PY'
import json
import os
import sys
from pathlib import Path

ROOT = Path(os.environ["REPO_ROOT"])
OUT = ROOT / "skills.sh.json"
CATALOG = ROOT / "catalog" / "skills.json"

if not CATALOG.exists():
    print("catalog/skills.json missing — run scripts/catalog.sh", file=sys.stderr)
    raise SystemExit(2)

catalog = json.loads(CATALOG.read_text())
pkg = json.loads((ROOT / "package.json").read_text())
author = (pkg.get("author") or {}).get("name") or pkg["name"]

# Groupings render the catalog's governance model, which is two orthogonal
# fields rather than one enum:
#
#   status  certified | reference   has it passed the review bar
#   origin  first-party | third-party   who maintains it
#
# Collapsing those into a single ladder would label first-party work that is
# merely uncertified as a "community" contribution, which is false and is the
# specific mistake the split exists to prevent.
def group_of(skill):
    if skill.get("origin") == "third-party":
        return "community"
    return "certified" if skill.get("status") == "certified" else "reference"


GROUPS = [
    ("certified", f"{author} Certified",
     f"Skills that carry both positive and negative trigger cases and have passed {author}'s review."),
    ("reference", f"{author} Reference Skills",
     f"First-party skills maintained by {author}, not yet certified."),
    ("community", "Community",
     "Third-party contributions. Each records the repository and revision it came from."),
]

groupings = []
for key, title, description in GROUPS:
    names = sorted(s["name"] for s in catalog["skills"] if group_of(s) == key)
    if not names:
        continue                 # the schema requires minItems 1 per grouping
    groupings.append({"title": title, "description": description, "skills": names})

if not groupings:
    print("no skills to publish", file=sys.stderr)
    raise SystemExit(1)

doc = {
    "$schema": "https://skills.sh/schemas/skills.sh.schema.json",
    "notGrouped": "bottom",
    "groupings": groupings,
}
rendered = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"

# --- conformance, against the published schema's constraints ----------------
errs = []
if not (1 <= len(groupings) <= 50):
    errs.append(f"groupings must hold 1-50 entries, got {len(groupings)}")
for g in groupings:
    if not (1 <= len(g["title"]) <= 120):
        errs.append(f"title out of range: {g['title']!r}")
    if len(g.get("description", "")) > 500:
        errs.append(f"description over 500 chars in {g['title']!r}")
    if not (1 <= len(g["skills"]) <= 500):
        errs.append(f"{g['title']!r}: skills must hold 1-500 entries")
    for n in g["skills"]:
        if not (1 <= len(n) <= 120):
            errs.append(f"{g['title']!r}: skill name length out of range: {n!r}")
listed = [n for g in groupings for n in g["skills"]]
if len(listed) != len(set(listed)):
    errs.append("a skill appears in more than one grouping")
if set(listed) != {s["name"] for s in catalog["skills"]}:
    errs.append("groupings do not cover exactly the catalog's skills")
for e in errs:
    print(f"FAIL: {e}", file=sys.stderr)
if errs:
    raise SystemExit(1)

if sys.argv[1:2] == ["--check"]:
    if not OUT.exists():
        print("FAIL: skills.sh.json missing — run scripts/registry.sh", file=sys.stderr)
        raise SystemExit(1)
    if OUT.read_text() != rendered:
        print("FAIL: skills.sh.json is stale — run scripts/registry.sh", file=sys.stderr)
        raise SystemExit(1)
    print(f"registry --check  ok  {len(listed)} skills in {len(groupings)} grouping(s)")
    raise SystemExit(0)

OUT.write_text(rendered)
print(f"wrote skills.sh.json  ({len(listed)} skills in {len(groupings)} grouping(s))")
for g in groupings:
    print(f"  {g['title']}: {', '.join(g['skills'])}")
PY
