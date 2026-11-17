#!/usr/bin/env bash
# The scaffold's only real contract: whatever it emits must pass this repo's own
# validators unmodified. A scaffold that produces a skill failing skill-integrity
# or catalog generation teaches the format wrong to every author on day one.
#
# Runs against a copy, so a failed run never leaves a probe skill behind.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "test-scaffold: generated skills pass the repo's own validators"

fails=0
ok()  { echo "  ok  $1"; }
bad() { echo "FAIL: $1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$REPO_ROOT" "$WORK/pristine" 2>/dev/null
COPY="$WORK/repo"
reset_copy() { rm -rf "$COPY"; cp -R "$WORK/pristine" "$COPY" 2>/dev/null; }
reset_copy

# --- 1. multi-file scaffold passes every validator -------------------------
if bash "$COPY/scripts/new-skill.sh" probe-multi --trigger "a probe runs" --refs >/dev/null 2>&1; then
  ok "multi-file scaffold runs"
else
  bad "multi-file scaffold failed"
fi
bash "$COPY/tests/test-skill-integrity.sh" >/dev/null 2>&1 \
  && ok "scaffolded multi-file skill passes test-skill-integrity" \
  || bad "scaffolded multi-file skill fails test-skill-integrity"
bash "$COPY/scripts/catalog.sh" --check >/dev/null 2>&1 \
  && ok "scaffold left the catalog current" \
  || bad "scaffold did not regenerate the catalog"

# --- 2. all three files, and spec-only frontmatter -------------------------
# A skill is not only its SKILL.md. If the scaffold skips the governance record
# or the trigger cases, the tree fails its own checks the moment it is generated.
bash "$COPY/scripts/new-skill.sh" probe-single --trigger "a single-file probe runs" >/dev/null 2>&1
bash "$COPY/scripts/new-skill.sh" probe-third --trigger "a third-party probe runs" \
     --origin third-party \
     --source-repo https://github.com/example/upstream \
     --source-rev 1111111111111111111111111111111111111111 >/dev/null 2>&1
python3 - "$COPY" <<'EOS'
import json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
SPEC = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
errs = []

for name in ("probe-multi", "probe-single", "probe-third"):
    md = root / "skills" / name / "SKILL.md"
    if not md.exists():
        errs.append(f"{name}: no SKILL.md")
        continue
    fm = re.match(r"^---\n(.*?)\n---\n", md.read_text(), re.S).group(1)
    keys = set(re.findall(r"^([A-Za-z0-9_-]+):", fm, re.M))
    extra = keys - SPEC
    if extra:
        errs.append(f"{name}: frontmatter keys outside the Agent Skills spec: {sorted(extra)}")
    entry = root / "catalog/entries" / f"{name}.json"
    if not entry.exists():
        errs.append(f"{name}: no governance entry")
        continue
    e = json.loads(entry.read_text())
    if e["name"] != name:
        errs.append(f"{name}: entry name mismatch")
    cases_path = root / "evals" / name / "trigger-cases.json"
    if not cases_path.exists():
        errs.append(f"{name}: no trigger cases")
        continue
    cases = json.loads(cases_path.read_text())
    # Both polarities, or the skill is uncertifiable the moment it is created.
    if not any(c["should_trigger"] for c in cases):
        errs.append(f"{name}: scaffolded cases carry no positive")
    if not any(c["should_trigger"] is False for c in cases):
        errs.append(f"{name}: scaffolded cases carry no negative")

single = (root / "skills/probe-single/SKILL.md").read_text()
if (root / "skills/probe-single/references").exists():
    errs.append("single-file scaffold created a references/ directory")
if "## Supporting files" in single:
    errs.append("single-file scaffold kept the Supporting files section")

# A third-party skill without an immutable revision is unreviewable, so the
# scaffold must not leave the source out.
third = json.loads((root / "catalog/entries/probe-third.json").read_text())
if third.get("origin") != "third-party":
    errs.append("--origin third-party was not recorded")
if not third.get("source", {}).get("revision"):
    errs.append("third-party scaffold left out the source revision")

for e in errs:
    print(f"FAIL: {e}", file=sys.stderr)
raise SystemExit(1 if errs else 0)
EOS
[ $? -eq 0 ] && ok "SKILL.md, governance entry, and both case polarities are all created" \
             || bad "scaffold output shape"

# Everything it wrote must satisfy the free checks with no hand editing.
bash "$COPY/scripts/catalog.sh" --check >/dev/null 2>&1 \
  && ok "scaffolded tree passes catalog --check" || bad "catalog is stale after scaffolding"
bash "$COPY/scripts/eval.sh" --check >/dev/null 2>&1 \
  && ok "scaffolded trigger cases pass eval --check" || bad "scaffolded cases fail eval --check"

# --- 3. no unreplaced template placeholders --------------------------------
if grep -rq '{{' "$COPY/skills/probe-multi" 2>/dev/null; then
  bad "scaffolded skill still contains {{placeholders}}"
else
  ok "no unreplaced placeholders in the output"
fi

# --- 4. the reference file is substantive ----------------------------------
# test-skill-integrity rejects references under 200 characters, so a template
# that is merely a stub would make every scaffolded multi-file skill fail.
ref="$COPY/skills/probe-multi/references/detail.md"
if [ "$(wc -c < "$ref")" -ge 200 ]; then
  ok "reference template is long enough to pass the integrity threshold"
else
  bad "reference template is under the 200-character integrity minimum"
fi

# --- 5. bad input is rejected ----------------------------------------------
reset_copy
bash "$COPY/scripts/new-skill.sh" Bad_Name >/dev/null 2>&1 \
  && bad "accepted an invalid skill name" \
  || ok "rejects a name that is not lowercase-hyphen"
bash "$COPY/scripts/new-skill.sh" probe-x --classification gold >/dev/null 2>&1 \
  && bad "accepted an invalid classification" \
  || ok "rejects a classification outside the enum"
bash "$COPY/scripts/new-skill.sh" probe-x --origin nowhere >/dev/null 2>&1 \
  && bad "accepted an invalid origin" \
  || ok "rejects an origin outside the enum"
bash "$COPY/scripts/new-skill.sh" probe--x >/dev/null 2>&1 \
  && bad "accepted a name with consecutive hyphens" \
  || ok "rejects a name the Agent Skills spec forbids"
bash "$COPY/scripts/new-skill.sh" using-skills >/dev/null 2>&1 \
  && bad "overwrote an existing skill" \
  || ok "refuses to overwrite an existing skill"

# --- 6. "Use when" is not doubled ------------------------------------------
# The integrity test only checks the prefix, so a doubled "Use when Use when"
# would pass validation while reading as a stutter in every agent's skill list.
bash "$COPY/scripts/new-skill.sh" probe-stutter --trigger "Use when someone repeats the prefix" >/dev/null 2>&1
if grep -q "description: Use when someone repeats the prefix" "$COPY/skills/probe-stutter/SKILL.md"; then
  ok "a trigger that repeats 'Use when' is normalised"
else
  bad "trigger normalisation failed: $(grep '^description:' "$COPY/skills/probe-stutter/SKILL.md")"
fi

# --- 6b. third-party provenance cannot be left as a placeholder ------------
# The scaffold used to emit OWNER/REPO and forty zeros. Both satisfied every
# validator, so a fabricated provenance record shipped looking reviewed.
reset_copy
bash "$COPY/scripts/new-skill.sh" probe-noprov --trigger "a probe" --origin third-party >/dev/null 2>&1 \
  && bad "accepted --origin third-party with no source" \
  || ok "requires a source for a third-party skill"
bash "$COPY/scripts/new-skill.sh" probe-zerorev --trigger "a probe" --origin third-party \
     --source-repo https://github.com/example/upstream \
     --source-rev 0000000000000000000000000000000000000000 >/dev/null 2>&1 \
  && bad "accepted an all-zero revision" \
  || ok "rejects the all-zero revision placeholder"
bash "$COPY/scripts/new-skill.sh" probe-httprev --trigger "a probe" --origin third-party \
     --source-repo http://github.com/example/upstream \
     --source-rev 1111111111111111111111111111111111111111 >/dev/null 2>&1 \
  && bad "accepted a non-https source repository" \
  || ok "rejects a non-https source repository"
# And the validator refuses the old placeholders even if hand-written back in.
reset_copy
bash "$COPY/scripts/new-skill.sh" probe-hand --trigger "a probe" --origin third-party \
     --source-repo https://github.com/example/upstream \
     --source-rev 1111111111111111111111111111111111111111 >/dev/null 2>&1
python3 - "$COPY" <<'EOS'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / "catalog" / "entries" / "probe-hand.json"
e = json.loads(p.read_text())
e["source"]["repository"] = "https://github.com/OWNER/REPO"
e["source"]["revision"] = "0" * 40
p.write_text(json.dumps(e, indent=2) + "\n")
EOS
bash "$COPY/scripts/catalog.sh" >/dev/null 2>&1 \
  && bad "catalog.sh accepted hand-written placeholder provenance" \
  || ok "catalog.sh rejects placeholder provenance"
reset_copy

# --- 7. hostile trigger text cannot produce invalid YAML -------------------
# The scaffold interpolated user text straight into `description:`. A trigger
# containing ": " produced a line no conformant YAML parser accepts, and the
# repo's own parser took it, so the defect shipped looking like a working skill.
reset_copy
i=0
for trig in "reviewing code: before merge" \
            'carrying "quotes" inside' \
            'ending with a # hash' \
            'holding a \backslash' \
            '  padded with spaces  '; do
  i=$((i + 1))
  if bash "$COPY/scripts/new-skill.sh" "probe-yaml-$i" --trigger "$trig" >/dev/null 2>&1; then
    if python3 - "$COPY/skills/probe-yaml-$i/SKILL.md" <<'EOS'
import re, sys
text = open(sys.argv[1]).read()
fm = re.match(r"^---\n(.*?)\n---\n", text, re.S).group(1)
line = [l for l in fm.split("\n") if l.startswith("description:")][0]
raw = line.split(":", 1)[1].strip()
if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
    import json
    value = json.loads(raw) if raw[0] == '"' else raw[1:-1].replace("''", "'")
else:
    # A plain scalar must not carry YAML syntax; if it does, the writer failed.
    assert not re.search(r":(?:\s|$)| #", raw), f"unquoted YAML syntax: {raw!r}"
    value = raw
assert value.startswith("Use when"), f"lost the prefix: {value!r}"
EOS
    then
      ok "trigger ${trig:0:28} serialises to a readable scalar"
    else
      bad "trigger ${trig:0:28} produced frontmatter no parser can read"
    fi
  else
    bad "scaffold refused a legitimate trigger: ${trig:0:28}"
  fi
done

# --- 8. a newline in a CLI value is refused outright -----------------------
# `--trigger $'work\nbogus: injected'` used to add a `bogus` frontmatter key.
reset_copy
if bash "$COPY/scripts/new-skill.sh" probe-inject --trigger "$(printf 'doing work\nbogus: injected')" >/dev/null 2>&1; then
  bad "accepted a newline in --trigger (frontmatter injection)"
else
  ok "refuses a newline in a CLI value"
fi
[ -e "$COPY/skills/probe-inject" ] \
  && bad "left a skill behind after refusing the input" \
  || ok "creates nothing when it refuses the input"

# --- 9. a rejected skill is rolled back, not left on disk ------------------
# The old script used `generator && echo`, so a FAIL from catalog.sh printed,
# was ignored, and the run still exited 0 with the bad skill in the tree.
reset_copy
python3 - "$COPY" <<'EOS'
import sys
from pathlib import Path
# registry.sh, not catalog.sh: a broken catalog also trips the integrity check
# further down, so the run would exit nonzero for the wrong reason and the test
# would pass even with the generator's status swallowed again. registry.sh is
# downstream of everything else the scaffold verifies, so only the generator
# branch can catch this.
p = Path(sys.argv[1]) / "scripts" / "registry.sh"
t = p.read_text()
marker = "python3 - \"$@\" <<'PY'"
assert marker in t, "registry.sh shape changed; update this mutation"
p.write_text(t.replace(marker, "echo 'FAIL: forced rejection for the rollback test' >&2; exit 1\n" + marker, 1))
EOS
bash "$COPY/scripts/new-skill.sh" probe-rollback --trigger "a rejected probe" >/dev/null 2>&1 \
  && bad "exited 0 after a generator rejected the skill" \
  || ok "exits nonzero when a generator rejects the skill"
for leftover in "skills/probe-rollback" "catalog/entries/probe-rollback.json" "evals/probe-rollback"; do
  [ -e "$COPY/$leftover" ] && bad "left $leftover behind after a failed run"
done
[ -e "$COPY/skills/probe-rollback" ] || ok "rolls the tree back on failure"
reset_copy

[ "$fails" -eq 0 ] && echo "PASS: test-scaffold" || echo "FAILED: test-scaffold" >&2
exit $((fails > 0))
