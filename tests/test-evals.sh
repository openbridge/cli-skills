#!/usr/bin/env bash
# Structural validation of the eval corpus. No model, no network, no cost — the
# half of scripts/eval.sh that can safely gate a commit.
#
# What this protects: eval cases rot quietly. A skill gets renamed and its cases
# point at nothing; a suite loses its negative and silently stops testing
# anything; a case is duplicated and one copy is edited.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "test-evals: eval corpus structure and coverage"

fails=0
ok()  { echo "  ok  $1"; }
bad() { echo "FAIL: $1" >&2; fails=$((fails + 1)); }

# --- 1. the runner's own validation passes ---------------------------------
if out="$(bash "$REPO_ROOT/scripts/eval.sh" --check 2>&1)"; then
  ok "${out#eval --check  ok  }"
else
  bad "scripts/eval.sh --check rejects the corpus"
  echo "$out" | grep '^FAIL' >&2
fi

# --- 2. conformance to evals/schema.json -----------------------------------
python3 - "$REPO_ROOT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
schema = json.loads((root / "evals/schema.json").read_text())
item = schema["items"]
errs = []
for f in sorted((root / "evals").glob("*/trigger-cases.json")):
    rel = f.relative_to(root)
    cases = json.loads(f.read_text())
    if not isinstance(cases, list) or not cases:
        errs.append(f"{rel}: must be a non-empty array")
        continue
    for i, c in enumerate(cases):
        undeclared = set(c) - set(item["properties"])
        if undeclared:
            errs.append(f"{rel}[{i}]: undeclared keys {sorted(undeclared)}")
        for key in item["required"]:
            if key not in c:
                errs.append(f"{rel}[{i}]: missing {key!r}")
        if not isinstance(c.get("should_trigger"), bool):
            errs.append(f"{rel}[{i}]: should_trigger must be a boolean")
        if c.get("expect_skill") and c.get("should_trigger"):
            errs.append(f"{rel}[{i}]: expect_skill is meaningless alongside should_trigger: true")
        if "note" in c and not str(c["note"]).strip():
            errs.append(f"{rel}[{i}]: empty note")
for e in errs:
    print(f"FAIL: {e}", file=sys.stderr)
raise SystemExit(1 if errs else 0)
PY
[ $? -eq 0 ] && ok "cases conform to evals/schema.json" || bad "schema conformance"

# --- 3. every skill has evals, and they discriminate -----------------------
python3 - "$REPO_ROOT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
skills = {p.name for p in (root / "skills").iterdir() if p.is_dir()}
suites = {p.parent.name for p in (root / "evals").glob("*/trigger-cases.json")}
errs = []
for missing in sorted(skills - suites):
    errs.append(f"skills/{missing} has no evals/{missing}/trigger-cases.json")
for orphan in sorted(suites - skills):
    errs.append(f"evals/{orphan}/ has no matching skill")

# Corpus rules — polarity, collision coverage, query types, expect_skill
# targets — are NOT reimplemented here. scripts/eval.sh --check owns them and
# CI runs it. Two hand-written validators of one format drift, and the drift is
# invisible until one accepts what the other rejects.
negatives = collisions = 0
for f in (root / "evals").glob("*/trigger-cases.json"):
    cases = json.loads(f.read_text())
    negatives += sum(1 for c in cases if c.get("should_trigger") is False)
    collisions += sum(1 for c in cases if c.get("expect_skill"))
for e in errs:
    print(f"FAIL: {e}", file=sys.stderr)
print(f"  ok  {len(suites)} suites, {negatives} negative(s), {collisions} collision case(s)")
raise SystemExit(1 if errs else 0)
PY
[ $? -eq 0 ] && ok "suites match skills, with counts" || bad "suite coverage"

# The corpus rules themselves, from the one implementation that owns them.
if bash "$REPO_ROOT/scripts/eval.sh" --check >/dev/null 2>&1; then
  ok "scripts/eval.sh --check accepts the corpus"
else
  bad "scripts/eval.sh --check rejects the corpus"
  bash "$REPO_ROOT/scripts/eval.sh" --check 2>&1 | grep '^FAIL' >&2
fi

# --- 4. plugin-eval cases are at least well-formed --------------------------
# These are never run here (claude plugin eval costs real money), so nothing
# else would notice a typo until someone pays to find out. This cannot validate
# against the real schema — only that tool knows it — but a missing key or a
# malformed grader is catchable for free.
python3 - "$REPO_ROOT" <<'EOS'
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
cases = sorted((root / "plugin-evals").glob("*/case.yaml"))
errs = []
if not cases:
    print("  ok  no plugin-eval cases to check")
for f in cases:
    rel, text = f.relative_to(root), f.read_text()
    for key in ("schema_version:", "name:", "execution:", "graders:"):
        if key not in text:
            errs.append(f"{rel}: missing {key!r}")
    if "prompt:" not in text:
        errs.append(f"{rel}: execution has no prompt")
    graders = re.findall(r"^  - name: (\S+)", text, re.M)
    if not graders:
        errs.append(f"{rel}: no graders")
    for g in re.split(r"^  - ", text.split("graders:")[-1], flags=re.M)[1:]:
        if "type:" not in g:
            errs.append(f"{rel}: a grader has no type")
    # The collection prefix must stay optional, or every case breaks the first
    # time a fork runs scripts/identity.sh rename. Detected structurally rather
    # than by naming a collection: a literal name here would itself be a copy
    # nothing keeps in sync, and identity --audit rightly rejected the first
    # version of this check for exactly that.
    for pat in re.findall(r"(?:input_match|pattern): '([^']+)'", text):
        stripped = re.sub(r"\(\?:[^)]*\)\??", "", pat)   # drop optional groups
        if re.search(r"[\w-]+:[\w-]", stripped):
            errs.append(f"{rel}: grader hardcodes a collection prefix: {pat}")
for e in errs:
    print(f"FAIL: {e}", file=sys.stderr)
if cases and not errs:
    print(f"  ok  {len(cases)} plugin-eval case(s) well-formed")
raise SystemExit(1 if errs else 0)
EOS
[ $? -eq 0 ] && ok "plugin-eval cases are structurally sound" || bad "plugin-eval structure"

[ "$fails" -eq 0 ] && echo "PASS: test-evals" || echo "FAILED: test-evals" >&2
exit $((fails > 0))
