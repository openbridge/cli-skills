#!/usr/bin/env bash
# The scope boundary — that this repository authors skills and does not review the
# systems it documents — and the completion test that stops authoring from running
# on forever.
#
# Both are prose, so nothing else in the suite notices when one is deleted. That
# matters more than it looks: the boundary exists because an agent handed an
# unfamiliar CLI will read it, find something alarming, and report on it instead of
# finishing the skill. Delete the paragraph and the behaviour comes straight back,
# with every other test still green.
#
# This checks the instruction is present and reachable on every harness. It cannot
# check that an agent obeys it — that is plugin-evals/authoring-stays-in-scope.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "test-charter: scope boundary, observation drain, definition of done"

python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
fails = []
def fail(msg): fails.append(msg); print(f"FAIL: {msg}", file=sys.stderr)
def ok(msg): print(f"  ok  {msg}")

def text(rel):
    p = root / rel
    return p.read_text() if p.is_file() else None

# --- The charter itself ------------------------------------------------------
agents = text("AGENTS.md")
if agents is None:
    fail("AGENTS.md missing — the charter has no home")
else:
    required = {
        "## Reading a source system is in scope. Judging it is not.":
            "the in-scope/out-of-scope distinction",
        "## Not this repository's job":
            "the list of other agents' work",
        "## When you notice one anyway":
            "the route to the drain file",
        "## Done":
            "the completion test",
    }
    for heading, what in required.items():
        if heading not in agents:
            fail(f"AGENTS.md lost {heading!r} — {what}")
    # The distinction is carried by the worked examples, not the heading. A
    # heading with the table deleted reads as a rule with no way to apply it.
    if "OBSERVATIONS.md" not in agents:
        fail("AGENTS.md names no drain file, so a noticed observation has nowhere to go")
    if "Unread source material" not in agents:
        fail("AGENTS.md lost the clause that unread material does not mean unfinished")
    if not fails:
        ok("AGENTS.md carries the charter, the boundary, and the stop rule")

# --- Reachable on every harness ---------------------------------------------
# Three delivery paths, three ways to silently lose it. Claude Code imports it,
# Gemini @-includes it, and AGENTS.md is read directly by the rest.
claude = text("CLAUDE.md")
if claude is None:
    fail("CLAUDE.md missing — Claude Code reads no repository instructions")
elif "@AGENTS.md" not in claude and "@./AGENTS.md" not in claude:
    fail("CLAUDE.md does not import AGENTS.md; the charter will not reach the session")
else:
    ok("CLAUDE.md imports AGENTS.md")

gemini = text("GEMINI.md")
if gemini is None:
    fail("GEMINI.md missing")
elif "@./AGENTS.md" not in gemini:
    fail("GEMINI.md does not include ./AGENTS.md; Gemini sessions lose the charter")
else:
    ok("GEMINI.md includes AGENTS.md")

if text("OBSERVATIONS.md") is None:
    fail("OBSERVATIONS.md missing — AGENTS.md routes observations to a file that is "
         "not there, which reads as permission to report them inline instead")
else:
    ok("OBSERVATIONS.md exists as the drain")

# --- The authoring skill must restate it ------------------------------------
# AGENTS.md is loaded by the harness; the skill is loaded when the task starts.
# An agent that picks up authoring mid-session may only ever see the skill.
tmpl = text("skills/example-skill/SKILL.md")
if tmpl is None:
    fail("skills/example-skill/SKILL.md missing")
else:
    if "reviewing the system you are documenting" not in tmpl:
        fail("example-skill no longer states that reviewing the documented system "
             "is out of scope")
    if "OBSERVATIONS.md" not in tmpl:
        fail("example-skill names no drain file")
    if "Stop when the checks are green" not in tmpl:
        fail("example-skill lost its completion step; authoring has no defined end")
    ok("example-skill restates the boundary and ends with a stop rule")

raise SystemExit(1 if fails else 0)
PY
rc=$?
[ $rc -eq 0 ] && echo "PASS: test-charter" || echo "FAILED: test-charter" >&2
exit $rc
