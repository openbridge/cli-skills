#!/usr/bin/env bash
# The catalog has two sources and the split is the thing worth protecting:
# SKILL.md frontmatter carries the Agent Skills specification's discovery fields
# and is generated from; catalog/entries/*.json carries governance a skill
# cannot state about itself and is written by hand.
#
# So the risks are: the generated half going stale, the spec's own constraints
# being enforced more loosely than the spec states them, and `certified` being
# claimable without the evidence that makes it mean anything.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "test-catalog: spec conformance, governance, staleness"

fails=0
ok()  { echo "  ok  $1"; }
bad() { echo "FAIL: $1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$REPO_ROOT" "$WORK/pristine" 2>/dev/null
COPY="$WORK/repo"
reset_copy() { rm -rf "$COPY"; cp -R "$WORK/pristine" "$COPY" 2>/dev/null; }
reset_copy

# --- 1. the checked-in catalog is current ----------------------------------
bash "$COPY/scripts/catalog.sh" --check >/dev/null 2>&1 \
  && ok "checked-in catalog matches the skills tree" \
  || bad "catalog/skills.json is stale — run scripts/catalog.sh"

# --- 2. governance entries conform to catalog/schema.json ------------------
python3 - "$COPY" <<'EOS'
import json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
schema = json.loads((root / "catalog/schema.json").read_text())
props, required = schema["properties"], schema["required"]
errs = []
for f in sorted((root / "catalog/entries").glob("*.json")):
    rel, e = f.relative_to(root), json.loads(f.read_text())
    for key in required:
        if key not in e:
            errs.append(f"{rel}: missing required {key!r}")
    undeclared = set(e) - set(props)
    if undeclared:
        errs.append(f"{rel}: undeclared keys {sorted(undeclared)}")
    if e.get("classification") not in props["classification"]["enum"]:
        errs.append(f"{rel}: classification {e.get('classification')!r} not in enum")
    if e.get("origin") not in props["origin"]["enum"]:
        errs.append(f"{rel}: origin {e.get('origin')!r} not in enum")
    if e.get("name") != f.stem:
        errs.append(f"{rel}: name does not match the filename")
    if not re.fullmatch(props["name"]["pattern"], e.get("name", "")):
        errs.append(f"{rel}: name does not match the spec pattern")
    # Without an immutable revision there is no statement of what was reviewed.
    if e.get("origin") == "third-party" and "source" not in e:
        errs.append(f"{rel}: third-party entry with no source")
for e in errs:
    print(f"FAIL: {e}", file=sys.stderr)
raise SystemExit(1 if errs else 0)
EOS
[ $? -eq 0 ] && ok "governance entries conform to catalog/schema.json" || bad "entry conformance"

# --- 3. the generated aggregate is coherent --------------------------------
python3 - "$COPY" <<'EOS'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
cat = json.loads((root / "catalog/skills.json").read_text())
errs = []
if cat.get("catalogVersion") != 1:
    errs.append(f"catalogVersion should be 1, got {cat.get('catalogVersion')!r}")
for s in cat["skills"]:
    label = s.get("name", "<unnamed>")
    for key in ("name", "description", "status", "origin", "maintainers",
                "registries", "governanceLicense", "path", "files"):
        if key not in s:
            errs.append(f"{label}: aggregate entry missing {key!r}")
    if not (root / s["path"] / "SKILL.md").exists():
        errs.append(f"{label}: path {s['path']!r} has no SKILL.md")
    on_disk = sorted(str(p.relative_to(root / s["path"]))
                     for p in (root / s["path"]).rglob("*") if p.is_file())
    if s["files"] != on_disk:
        errs.append(f"{label}: files {s['files']} != on disk {on_disk}")
# `files` earns its place only if something is actually multi-file.
if not any(len(s["files"]) > 1 for s in cat["skills"]):
    errs.append("no multi-file skill in the catalog; the files check proves nothing")
for e in errs:
    print(f"FAIL: {e}", file=sys.stderr)
raise SystemExit(1 if errs else 0)
EOS
[ $? -eq 0 ] && ok "aggregate is coherent and files lists match disk" || bad "aggregate coherence"

# --- 4. the spec's own frontmatter constraints -----------------------------
# A looser check than the spec is worse than none: it passes work that the
# ecosystem's own validators will reject.
probe() {  # <description> <frontmatter-body> <expect: reject|accept>
  reset_copy
  mkdir -p "$COPY/skills/probe-spec"
  printf -- '---\n%s\n---\n\n# Probe\n' "$2" > "$COPY/skills/probe-spec/SKILL.md"
  cat > "$COPY/catalog/entries/probe-spec.json" <<'JSON'
{"name":"probe-spec","classification":"reference","origin":"first-party","maintainers":["x"],"license":"MIT","registries":{}}
JSON
  if bash "$COPY/scripts/catalog.sh" >/dev/null 2>&1; then got=accept; else got=reject; fi
  [ "$got" = "$3" ] && ok "$1" || bad "$1 (expected $3, got $got)"
}

# $'...' is load-bearing: "$(printf '\n')" collapses to an empty string because
# command substitution strips trailing newlines, which silently joined every
# probe onto one line and made three of them pass for the wrong reason.
long_desc="Use when $(python3 -c 'print("x"*1030)')"

probe "rejects a name that does not match its directory" \
      $'name: mismatched\ndescription: Use when testing' reject
probe "rejects frontmatter keys outside the spec" \
      $'name: probe-spec\ndescription: Use when testing\ntier: certified' reject
probe "rejects a name with consecutive hyphens" \
      $'name: probe--spec\ndescription: Use when testing' reject
probe "rejects a description over the spec's 1024 characters" \
      "name: probe-spec"$'\n'"description: $long_desc" reject
probe "accepts the spec's optional fields" \
      $'name: probe-spec\ndescription: Use when testing\nlicense: MIT\ncompatibility: Requires nothing' accept

# --- 5. certification cannot be self-declared ------------------------------
# `certified` drives a public registry grouping. The documented gate is that the
# skill carries both positive and negative trigger cases.
reset_copy
python3 - "$COPY" <<'EOS'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / "catalog/entries/delivery-check.json"
e = json.loads(p.read_text()); e["classification"] = "certified"
p.write_text(json.dumps(e, indent=2) + "\n")
# Strip the negatives: positives alone prove only that a skill can fire.
q = Path(sys.argv[1]) / "evals/delivery-check/trigger-cases.json"
q.write_text(json.dumps([c for c in json.loads(q.read_text()) if c["should_trigger"]],
                        indent=2) + "\n")
EOS
bash "$COPY/scripts/catalog.sh" >/dev/null 2>&1 \
  && bad "'certified' accepted with no negative trigger cases" \
  || ok "'certified' refused without both case polarities"

# --- 6. and it is granted when the evidence is there -----------------------
reset_copy
python3 - "$COPY" <<'EOS'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / "catalog/entries/delivery-check.json"
e = json.loads(p.read_text()); e["classification"] = "certified"
p.write_text(json.dumps(e, indent=2) + "\n")
EOS
if bash "$COPY/scripts/catalog.sh" >/dev/null 2>&1; then
  ok "'certified' granted when both polarities are present"
else
  bad "'certified' refused despite both polarities being present"
fi

# --- 7. an orphaned governance record is caught ----------------------------
reset_copy
cp "$COPY/catalog/entries/delivery-check.json" "$COPY/catalog/entries/ghost.json"
python3 -c "
import json,sys
p=sys.argv[1]+'/catalog/entries/ghost.json'
e=json.load(open(p)); e['name']='ghost'; json.dump(e,open(p,'w'),indent=2)" "$COPY"
bash "$COPY/scripts/catalog.sh" >/dev/null 2>&1 \
  && bad "a governance record with no skill was accepted" \
  || ok "catches a governance record whose skill no longer exists"

[ "$fails" -eq 0 ] && echo "PASS: test-catalog" || echo "FAILED: test-catalog" >&2
exit $((fails > 0))
