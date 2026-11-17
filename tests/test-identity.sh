#!/usr/bin/env bash
# scripts/identity.sh is the write side of manifest consistency; this is the
# test that it works and, more importantly, that it still FAILS when it should.
#
# A drift checker that has never rejected anything is indistinguishable from
# `exit 0`, and this one shipped in exactly that state once: expected_values()
# stripped the collection name itself before searching for it, so --audit passed
# on every possible tree. Every mutation below exists because of a real bug.
#
# Destructive operations run against a copy in a temp dir, never the checkout.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Step 7 runs the whole offline suite against a renamed copy, and that suite
# includes this file. Without a guard the copy copies itself forever.
if [ -n "${IDENTITY_TEST_NESTED:-}" ]; then
  echo "SKIP: test-identity (nested run inside the rename check)"
  exit 0
fi

echo "test-identity: check/audit/rename across the manifest set"

fails=0
ok()   { echo "  ok  $1"; }
bad()  { echo "FAIL: $1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# Snapshot-and-restore, never `git checkout`: the checkout under test usually
# has uncommitted work, and reverting to HEAD would silently test a different
# tree than the one being changed. That mistake made two checks below pass for
# the wrong reason.
cp -R "$REPO_ROOT" "$WORK/pristine" 2>/dev/null
COPY="$WORK/repo"
reset_copy() { rm -rf "$COPY"; cp -R "$WORK/pristine" "$COPY" 2>/dev/null; }
reset_copy

# --- 1. JSON round-trip fidelity -------------------------------------------
# identity.sh rewrites manifests by re-serializing at indent=2. If a manifest is
# hand-formatted differently, editing one field silently reformats the file.
python3 - "$COPY" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
cfg = json.loads((root / ".skills-identity.json").read_text())
files = {t["file"] for ts in cfg["fields"].values() for t in ts if "json" in t}
bad = []
for rel in sorted(files):
    orig = (root / rel).read_text()
    if json.dumps(json.loads(orig), indent=2, ensure_ascii=False) + "\n" != orig:
        bad.append(rel)
if bad:
    print("FAIL: not indent=2 round-trip clean: " + ", ".join(bad), file=sys.stderr)
    raise SystemExit(1)
print(f"  ok  {len(files)} JSON manifests round-trip byte-identically")
PY
[ $? -eq 0 ] || bad "JSON round-trip fidelity"

# --- 2. every manifest in the tree is registered ---------------------------
# Adding a harness without adding it here is how the drift comes back.
python3 - "$COPY" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
cfg = json.loads((root / ".skills-identity.json").read_text())
declared = {t["file"] for ts in cfg["fields"].values() for t in ts}
found = set()
for pat in ("*plugin.json", "*marketplace.json", "*extension.json", "plugin.yaml"):
    for p in root.rglob(pat):
        if ".git" in p.parts or "node_modules" in p.parts:
            continue
        found.add(str(p.relative_to(root)))
missing = sorted(found - declared)
if missing:
    print("FAIL: manifests not in .skills-identity.json: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
print(f"  ok  all {len(found)} manifests registered in .skills-identity.json")
PY
[ $? -eq 0 ] || bad "manifest registration"

# --- 3. --check passes on a clean tree -------------------------------------
if bash "$COPY/scripts/identity.sh" --check >/dev/null 2>&1; then
  ok "--check passes on a clean tree"
else
  bad "--check rejects the checked-in tree"
fi

# --- 4. --check catches drift in each field --------------------------------
for field in name version homepage repository; do
  python3 - "$COPY" "$field" <<'PY'
import json, sys
from pathlib import Path
root, field = Path(sys.argv[1]), sys.argv[2]
cfg = json.loads((root / ".skills-identity.json").read_text())
# Mutate the last target, not the first: the first is often package.json, which
# is the source of truth, and changing THAT makes every other file look wrong
# rather than testing the check.
t = [x for x in cfg["fields"][field] if x["file"] != cfg["source"]][-1]
p = root / t["file"]
if "json" in t:
    d = json.loads(p.read_text())
    parts = t["json"].split(".")
    o = d
    for k in parts[:-1]:
        o = o[int(k)] if k.isdigit() else o[k]
    o[parts[-1]] = "DRIFTED"
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
else:
    import re
    p.write_text(re.sub(rf"^({t['yaml']}:\s*).*$", r"\1DRIFTED", p.read_text(), count=1, flags=8))
PY
  if bash "$COPY/scripts/identity.sh" --check >/dev/null 2>&1; then
    bad "--check passed with $field drifted"
  else
    ok "--check catches $field drift"
  fi
  reset_copy
done

# --- 5. --audit catches an untracked copy ----------------------------------
# Inject the collection's ACTUAL identity, read at runtime — a literal here
# would both break in a fork that has renamed and show up in this very audit.
#
# Which value to inject depends on the collection's name. A name that collides
# with the repository's own structure ("skills" is also the payload directory)
# cannot be swept by grep, so identity.sh skips that sweep and says so. Ask the
# tool which sweeps are live rather than hardcoding the rule in two places.
if bash "$COPY/scripts/identity.sh" --audit 2>&1 | grep -q "skip  name sweep"; then
  name_sweep_live=0
else
  name_sweep_live=1
fi

inject_identity_copy() {
  python3 - "$COPY" "$name_sweep_live" <<'PY'
import json, sys
from pathlib import Path
root, live = Path(sys.argv[1]), sys.argv[2] == "1"
pkg = json.loads((root / "package.json").read_text())
needle = pkg["name"] if live else pkg["version"]
p = root / "docs/skill-format.md"
p.write_text(p.read_text() + f"\nInstall {needle} today.\n")
PY
}

inject_identity_copy
out="$(bash "$COPY/scripts/identity.sh" --audit 2>&1)"; rc=$?
if grep -q "occurrence(s) outside" <<<"$out"; then
  ok "--audit flags a bare identity value in an unregistered file"
else
  bad "--audit missed an untracked copy (the bug that shipped once)"
fi
# The diagnostic and the exit status are separate claims. Asserting only the
# first is how --audit shipped printing drift and returning 0: every human
# reading the output saw a failure, and CI saw success.
if [ "$rc" -ne 0 ]; then
  ok "--audit exits nonzero when it reports drift"
else
  bad "--audit reported drift and exited 0 — CI cannot gate on this"
fi
reset_copy

# --- 5b. --audit works in a tree with no commits ---------------------------
# A fork's first day: files on disk, `git init` run, nothing committed yet. A
# plain `git grep` searches tracked content only, so an audit built on one
# reports "clean" having scanned nothing - the exact state where a fork is most
# likely to still carry the upstream name. The scratch copy above carries the
# real .git, which is why every check so far passes over committed content and
# none of them would have caught this.
rm -rf "$COPY/.git"
git -C "$COPY" init -q 2>/dev/null
inject_identity_copy
fresh_out="$(bash "$COPY/scripts/identity.sh" --audit 2>&1)"; fresh_rc=$?
if grep -q "occurrence(s) outside" <<<"$fresh_out"; then
  ok "--audit flags an untracked copy in a tree with no commits"
else
  bad "--audit scanned nothing in an uncommitted tree and called it clean"
fi
if [ "$fresh_rc" -ne 0 ]; then
  ok "--audit exits nonzero in an uncommitted tree"
else
  bad "--audit reported drift in an uncommitted tree and exited 0"
fi
reset_copy

# --- 6. --audit clean on the real tree -------------------------------------
clean_out="$(bash "$COPY/scripts/identity.sh" --audit 2>&1)"; clean_rc=$?
if grep -q "no untracked occurrences" <<<"$clean_out"; then
  ok "--audit clean on the checked-in tree"
else
  bad "--audit reports untracked copies in the checked-in tree"
fi
if [ "$clean_rc" -eq 0 ]; then
  ok "--audit exits 0 on a clean tree"
else
  bad "--audit exited $clean_rc on a tree it calls clean"
fi

# --- 6b. a structural name disables the name sweep out loud -----------------
# Silence here would be the real failure: a fork named for its own payload
# would read "no untracked occurrences" and believe the name was swept.
if [ "$name_sweep_live" -eq 0 ]; then
  if grep -q "skip  name sweep" <<<"$clean_out" \
     && grep -q -- "--check still verifies" <<<"$clean_out"; then
    ok "a structural collection name disables the name sweep and says so"
  else
    bad "name sweep is unusable for this name but --audit does not say so"
  fi
else
  ok "name sweep is live for this collection name (no skip expected)"
fi

# --- 7. rename is complete and leaves a working tree ------------------------
# Name generated at runtime, never written here as a literal: after the rename
# the tree IS that name, and a literal copy in this file would be found by the
# very --audit run two checks below.
probe_name="zz-renamed-$$"
repo_slug="$(python3 -c "import json,sys;u=json.load(open(sys.argv[1]))['repository'];print(u.rstrip('/').removesuffix('.git').split('github.com/')[-1])" "$COPY/package.json")"
coll_name="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['name'])" "$COPY/package.json")"

# A collection whose name is also its repository name cannot be renamed: step 4
# of rename masks the repo name to protect install URLs, and masking cannot
# distinguish two identical strings. rename must refuse rather than corrupt
# every install command, so that configuration asserts the refusal instead.
if [ "${repo_slug##*/}" = "$coll_name" ]; then
  before="$(cat "$COPY/.opencode/INSTALL.md")"
  bash "$COPY/scripts/identity.sh" rename "$probe_name" >/dev/null 2>&1
  rename_rc=$?
  if [ "$rename_rc" -ne 0 ] && [ "$(cat "$COPY/.opencode/INSTALL.md")" = "$before" ]; then
    ok "rename refuses when the collection name is also the repository name"
  else
    bad "rename proceeded with an ambiguous name and rewrote install URLs"
  fi
  reset_copy
  [ "$fails" -eq 0 ] && echo "PASS: test-identity" || echo "FAILED: test-identity" >&2
  exit $((fails > 0))
fi

bash "$COPY/scripts/identity.sh" rename "$probe_name" >/dev/null 2>&1
if bash "$COPY/scripts/identity.sh" --check >/dev/null 2>&1; then
  ok "rename leaves --check passing"
else
  bad "rename leaves the tree inconsistent"
fi
renamed_out="$(bash "$COPY/scripts/identity.sh" --audit 2>&1)"; renamed_rc=$?
if [ "$renamed_rc" -eq 0 ] && grep -q "no untracked occurrences" <<<"$renamed_out"; then
  ok "rename leaves --audit clean"
else
  bad "rename leaves untracked copies of the old name"
fi
# The renamed tree must still be a working collection, not just a consistent
# one. This is the check that caught tests hardcoding the old plugin filename.
if (cd "$COPY" && IDENTITY_TEST_NESTED=1 bash tests/run-tests.sh >/dev/null 2>&1); then
  ok "the renamed tree still passes its own offline suite"
else
  bad "offline suite fails after a rename — a fork's first day would fail"
fi
# The repository name is a different identity and rename must not touch it.
# The slug is read from the tree at runtime for the same reason the probe name
# is generated above: a literal here is an untracked identity copy that --audit
# would flag, and it would fail in any fork pointing at its own repository.
if grep -rq "$repo_slug" "$COPY/.opencode/INSTALL.md" 2>/dev/null; then
  ok "rename leaves the repository name alone"
else
  bad "rename corrupted the repo name inside install URLs"
fi

[ "$fails" -eq 0 ] && echo "PASS: test-identity" || echo "FAILED: test-identity" >&2
exit $((fails > 0))
