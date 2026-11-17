#!/usr/bin/env bash
# Run every offline test. No dependencies beyond bash, python3, and node.
#
# What these prove: the adapters behave as written when their hooks are driven
# directly. What they do NOT prove: that any harness loads the plugin, calls
# those hooks, or reads the field emitted. See docs/live-smoke-tests.md for the
# checks only a real session can make.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pass=0 fail=0 skip=0
failed_names=()

run() {
  local name="$1"; shift
  echo
  echo "── $name ──────────────────────────────────────────"
  if "$@"; then
    if [ "${LAST_SKIPPED:-0}" = "1" ]; then skip=$((skip + 1)); else pass=$((pass + 1)); fi
  else
    fail=$((fail + 1)); failed_names+=("$name")
  fi
}

# node tests exit 0 with a SKIP line when the runtime is too old; treat that as
# a pass for exit-code purposes but report it separately.
run_node() {
  local name="$1" file="$2"
  echo
  echo "── $name ──────────────────────────────────────────"
  local out rc
  out="$(node "$file" 2>&1)"; rc=$?
  echo "$out"
  if [ $rc -ne 0 ]; then
    fail=$((fail + 1)); failed_names+=("$name")
  elif grep -q '^SKIP:' <<<"$out"; then
    skip=$((skip + 1))
  else
    pass=$((pass + 1))
  fi
}

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
command -v node    >/dev/null || { echo "node is required" >&2; exit 1; }

run     "hook branches"    bash "$SCRIPT_DIR/test-hook-branches.sh"
run     "manifest sync"    bash "$SCRIPT_DIR/test-manifest-sync.sh"
run     "identity"         bash "$SCRIPT_DIR/test-identity.sh"
run     "catalog"          bash "$SCRIPT_DIR/test-catalog.sh"
run     "registry"         bash "$SCRIPT_DIR/test-registry.sh"
run     "scaffold"         bash "$SCRIPT_DIR/test-scaffold.sh"
run     "evals (structure)" bash "$SCRIPT_DIR/test-evals.sh"
run     "skill integrity"  bash "$SCRIPT_DIR/test-skill-integrity.sh"
run     "charter"          bash "$SCRIPT_DIR/test-charter.sh"
run_node "opencode plugin" "$SCRIPT_DIR/test-opencode-plugin.mjs"
run_node "pi extension"    "$SCRIPT_DIR/test-pi-extension.mjs"
run     "hermes plugin"    python3 "$SCRIPT_DIR/test-hermes-plugin.py"

echo
echo "═══════════════════════════════════════════════════"
printf 'passed %d   skipped %d   failed %d\n' "$pass" "$skip" "$fail"
if [ "$fail" -gt 0 ]; then
  printf 'failed: %s\n' "${failed_names[*]}" >&2
  exit 1
fi
echo "All offline tests passed."
echo "Reminder: 11 of 15 harness rows have never been driven live. See docs/live-smoke-tests.md."
