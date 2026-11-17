#!/usr/bin/env bash
# skills.sh.json is how a public skill registry groups and renders this
# collection. It conforms to somebody else's schema
# (https://skills.sh/schemas/skills.sh.schema.json), so the constraints checked
# here are theirs, not ours — getting them wrong means a listing that silently
# does not appear.
#
# skills.sh reads this file after someone installs a skill from the repo with the
# `skills` CLI and telemetry enabled — it configures the display of a page that
# already exists, and does not itself cause discovery. So the cost of getting it
# wrong is a repo page that renders wrong for whoever installs first, not a
# missed crawl. https://www.skills.sh/docs/customize
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "test-registry: skills.sh.json conformance and coverage"

fails=0
ok()  { echo "  ok  $1"; }
bad() { echo "FAIL: $1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$REPO_ROOT" "$WORK/pristine" 2>/dev/null
COPY="$WORK/repo"
reset_copy() { rm -rf "$COPY"; cp -R "$WORK/pristine" "$COPY" 2>/dev/null; }
reset_copy

# --- 1. checked-in descriptor is current ------------------------------------
if out="$(bash "$COPY/scripts/registry.sh" --check 2>&1)"; then
  ok "${out#registry --check  ok  }"
else
  bad "skills.sh.json is stale — run scripts/registry.sh"
fi

# --- 2. published-schema constraints ----------------------------------------
python3 - "$REPO_ROOT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
doc = json.loads((root / "skills.sh.json").read_text())
cat = json.loads((root / "catalog/skills.json").read_text())
errs = []

if doc.get("$schema") != "https://skills.sh/schemas/skills.sh.schema.json":
    errs.append("$schema is not the published skills.sh schema URL")
if doc.get("notGrouped") not in (None, "top", "bottom"):
    errs.append(f"notGrouped must be top or bottom, got {doc.get('notGrouped')!r}")
if set(doc) - {"$schema", "schema", "notGrouped", "groupings"}:
    errs.append("root has properties the schema does not allow (additionalProperties: false)")

groupings = doc.get("groupings")
if not isinstance(groupings, list) or not (1 <= len(groupings) <= 50):
    errs.append("groupings must be a list of 1-50 entries")
    groupings = []

listed = []
for g in groupings:
    if set(g) - {"title", "description", "skills"}:
        errs.append(f"grouping has disallowed properties: {sorted(set(g))}")
    if not (1 <= len(g.get("title", "")) <= 120):
        errs.append(f"title length out of range: {g.get('title')!r}")
    if len(g.get("description", "")) > 500:
        errs.append(f"description over 500 chars in {g.get('title')!r}")
    sk = g.get("skills")
    if not isinstance(sk, list) or not (1 <= len(sk) <= 500):
        errs.append(f"{g.get('title')!r}: skills must be a list of 1-500 entries")
        continue
    for n in sk:
        if not (1 <= len(n) <= 120):
            errs.append(f"skill name length out of range: {n!r}")
    listed += sk

# Coverage: a skill missing here is a skill the registry never lists, which
# looks identical to it not existing.
if len(listed) != len(set(listed)):
    errs.append("a skill appears in more than one grouping")
if set(listed) != {s["name"] for s in cat["skills"]}:
    missing = {s["name"] for s in cat["skills"]} - set(listed)
    extra = set(listed) - {s["name"] for s in cat["skills"]}
    if missing:
        errs.append(f"skills in the catalog but not the registry listing: {sorted(missing)}")
    if extra:
        errs.append(f"skills listed that are not in the catalog: {sorted(extra)}")
for e in errs:
    print(f"FAIL: {e}", file=sys.stderr)
raise SystemExit(1 if errs else 0)
PY
[ $? -eq 0 ] && ok "conforms to the published skills.sh schema and covers every skill" || bad "schema/coverage"

# --- 3. a new skill must reach the listing ----------------------------------
bash "$COPY/scripts/new-skill.sh" probe-registry --trigger "a registry probe runs" >/dev/null 2>&1
if bash "$COPY/scripts/registry.sh" --check >/dev/null 2>&1; then
  ok "scaffolding a skill also updates the registry listing"
else
  bad "a new skill did not reach skills.sh.json"
fi

# --- 4. certification cannot be self-declared -------------------------------
# classification drives a registry grouping titled "Certified". If an entry
# alone could grant it, that grouping would certify nothing. The documented gate
# is that the skill carries both positive and negative trigger cases.
reset_copy
python3 - "$COPY" <<'EOS'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
p = root / "catalog/entries/delivery-check.json"
e = json.loads(p.read_text()); e["classification"] = "certified"
p.write_text(json.dumps(e, indent=2) + "\n")
q = root / "evals/delivery-check/trigger-cases.json"
q.write_text(json.dumps([c for c in json.loads(q.read_text()) if c["should_trigger"]],
                        indent=2) + "\n")
EOS
bash "$COPY/scripts/catalog.sh" >/dev/null 2>&1 \
  && bad "an unearned 'certified' classification was accepted" \
  || ok "'certified' is refused without both trigger-case polarities"

# --- 5. certification renders a grouping when it is earned -----------------
reset_copy
python3 - "$COPY" <<'EOS'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / "catalog/entries/delivery-check.json"
e = json.loads(p.read_text()); e["classification"] = "certified"
p.write_text(json.dumps(e, indent=2) + "\n")
EOS
if bash "$COPY/scripts/catalog.sh" >/dev/null 2>&1 \
   && bash "$COPY/scripts/registry.sh" >/dev/null 2>&1 \
   && grep -q "Certified" "$COPY/skills.sh.json"; then
  ok "an earned classification creates the Certified grouping"
else
  bad "certification earned but no Certified grouping rendered"
fi

# --- 6. third-party origin lands in Community, not the first-party group ----
# Collapsing status and origin into one ladder would label uncertified
# first-party work as a community contribution. Prove they stay orthogonal.
reset_copy
python3 - "$COPY" <<'EOS'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / "catalog/entries/example-skill.json"
e = json.loads(p.read_text())
e["origin"] = "third-party"
e["source"] = {
    "repository": "https://github.com/example/repo",
    # A real-looking hash, not "0" * 40: the all-zero revision is the scaffold
    # placeholder and catalog.sh now rejects it. This fixture used it, which is
    # exactly the record-that-looks-reviewed the check exists to stop.
    "revision": "9f2c1ab7d4e60853bb19cf07a2d5e41c8f36b0da",
    "path": "skills/example-skill",
}
p.write_text(json.dumps(e, indent=2) + "\n")
EOS
if bash "$COPY/scripts/catalog.sh" >/dev/null 2>&1 \
   && bash "$COPY/scripts/registry.sh" >/dev/null 2>&1; then
  python3 - "$COPY" <<'EOS'
import json, sys
from pathlib import Path
doc = json.loads((Path(sys.argv[1]) / "skills.sh.json").read_text())
groups = {g["title"]: g["skills"] for g in doc["groupings"]}
community = next((v for k, v in groups.items() if k == "Community"), [])
errs = []
if "example-skill" not in community:
    errs.append(f"third-party skill not in Community; groupings were {list(groups)}")
for title, names in groups.items():
    if title != "Community" and "example-skill" in names:
        errs.append(f"third-party skill also listed under {title!r}")
for e in errs:
    print(f"FAIL: {e}", file=sys.stderr)
raise SystemExit(1 if errs else 0)
EOS
  [ $? -eq 0 ] && ok "third-party origin groups as Community, independent of status" \
                || bad "origin/status grouping"
else
  bad "a third-party entry with a valid source was rejected"
fi

[ "$fails" -eq 0 ] && echo "PASS: test-registry" || echo "FAILED: test-registry" >&2
exit $((fails > 0))
