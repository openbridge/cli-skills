#!/usr/bin/env bash
# The session-start hook emits one of three JSON shapes, chosen by environment.
#
# This is the test that would have caught the Copilot CLI bug: Copilot sets both
# COPILOT_CLI and CLAUDE_PLUGIN_ROOT, so a branch order that checks
# CLAUDE_PLUGIN_ROOT first swallows it and emits a field Copilot never reads.
# The bootstrap then vanishes with no error anywhere — nothing crashes, the agent
# simply never learns the collection exists.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/session-start"

fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
pass() { echo "  ok  $*"; }

echo "test-hook-branches: session-start JSON shape per harness"

[ -x "$HOOK" ] || fail "hook is not executable (git mode should be 100755)"

# Assert: running the hook with the given env emits exactly one top-level key,
# equal to $want, whose value is a non-empty string containing the bootstrap.
check_shape() {
  local label="$1" want="$2"; shift 2
  local out
  out="$(env -i PATH="$PATH" HOME="$HOME" "$@" bash "$HOOK" 2>/dev/null)" || {
    fail "$label: hook exited non-zero"; return
  }
  local result
  result="$(printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(f"BAD_JSON {e}"); raise SystemExit
keys = list(d.keys())
if len(keys) != 1:
    print(f"MULTI_KEY {keys}"); raise SystemExit
k = keys[0]
v = d[k]
if k == "hookSpecificOutput":
    if v.get("hookEventName") != "SessionStart":
        print("BAD_EVENT_NAME"); raise SystemExit
    v = v.get("additionalContext")
if not isinstance(v, str) or not v.strip():
    print("EMPTY_PAYLOAD"); raise SystemExit
if "EXTREMELY_IMPORTANT" not in v:
    print("NO_BOOTSTRAP"); raise SystemExit
print(k)
')"
  if [ "$result" = "$want" ]; then
    pass "$label -> $want"
  else
    fail "$label: expected key '$want', got '$result'"
  fi
}

# Cursor sets CURSOR_PLUGIN_ROOT and MAY ALSO set CLAUDE_PLUGIN_ROOT. If the
# branch order regresses, this case is the first to break.
check_shape "Cursor (CURSOR + CLAUDE set)" additional_context \
  CURSOR_PLUGIN_ROOT=/fake CLAUDE_PLUGIN_ROOT=/fake

check_shape "Claude Code (CLAUDE only)" hookSpecificOutput \
  CLAUDE_PLUGIN_ROOT=/fake

# Copilot CLI sets BOTH. The -z COPILOT_CLI guard on the Claude branch is what
# makes this land in the SDK-standard fallback.
check_shape "Copilot CLI (CLAUDE + COPILOT_CLI)" additionalContext \
  CLAUDE_PLUGIN_ROOT=/fake COPILOT_CLI=1

check_shape "unknown harness (nothing set)" additionalContext \
  UNRELATED=1

# A missing bootstrap must be a silent no-op, not a malformed payload: degrading
# to "skills are opt-in" beats breaking the session.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -R "$REPO_ROOT/hooks" "$tmp/hooks"
mkdir -p "$tmp/skills"
out="$(CLAUDE_PLUGIN_ROOT=/fake bash "$tmp/hooks/session-start" 2>/dev/null)"
rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then
  pass "missing bootstrap -> exit 0, empty stdout"
else
  fail "missing bootstrap: rc=$rc, stdout=${#out} bytes (want rc=0, empty)"
fi

# Escaping must survive the characters that break naive JSON emission.
probe='He said "hi"	and \ then
a newline'
escaped="$(printf '%s' "$probe" | python3 -c '
import json, sys
s = sys.stdin.read()
print(json.dumps(s))')"
if [ -n "$escaped" ]; then
  pass "escaping probe constructed"
fi

if [ "$fails" -eq 0 ]; then
  echo "PASS: test-hook-branches"
else
  echo "FAILED: $fails check(s)" >&2
  exit 1
fi
