#!/usr/bin/env bash
# The skills tree and the references that hang off it.
#
# The failure this guards against is quiet: a tool mapping that exists but is
# linked from nothing is a file no agent ever reads, and a Platform Adaptation
# entry pointing at a missing file is an instruction to read something that is
# not there. Both look fine in a directory listing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "test-skill-integrity: frontmatter, references, Gemini includes"

python3 - "$REPO_ROOT" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
fails = []
def fail(msg): fails.append(msg); print(f"FAIL: {msg}", file=sys.stderr)
def ok(msg): print(f"  ok  {msg}")

skills = sorted(p for p in (root / "skills").iterdir() if p.is_dir())
if not skills:
    fail("no skills found")

for s in skills:
    md = s / "SKILL.md"
    if not md.is_file():
        fail(f"{s.name}: no SKILL.md"); continue
    text = md.read_text()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        fail(f"{s.name}: no YAML frontmatter"); continue
    fm = m.group(1)
    name = re.search(r"^name:\s*(\S+)\s*$", fm, re.M)
    desc = re.search(r"^description:\s*(.+)$", fm, re.M)
    if not name:
        fail(f"{s.name}: frontmatter has no name")
    elif name.group(1) != s.name:
        fail(f"{s.name}: frontmatter name {name.group(1)!r} != directory name")
    if not desc:
        fail(f"{s.name}: frontmatter has no description")
    else:
        # A description carrying ": " or a leading indicator must be quoted to
        # be valid YAML, so the prefix check has to look past the quotes rather
        # than at the raw line — otherwise the correctly-quoted form fails a
        # check about its wording. See "The supported YAML subset" in
        # docs/skill-format.md.
        raw = desc.group(1).strip()
        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
            raw = raw[1:-1]
        if not raw.lower().startswith("use when"):
            # The description is a trigger, not a summary — see docs/skill-format.md.
            fail(f"{s.name}: description should start with 'Use when'")
    ok(f"skills/{s.name}/SKILL.md")

# --- Every skill: reference files ↔ links, in both directions ----------------
# A reference nothing links is a file no agent reads; a link with no file is an
# instruction to read something that is not there. Both look fine in `ls`.
for s in skills:
    md = s / "SKILL.md"
    if not md.is_file():
        continue
    text = md.read_text()
    # Backticked `references/x.md` and markdown links (references/x.md)
    linked = set(re.findall(r"`(references/[\w.-]+\.md)`", text))
    linked |= set(re.findall(r"\]\((references/[\w.-]+\.md)\)", text))
    refs_dir = s / "references"
    on_disk = {f"references/{f.name}" for f in refs_dir.iterdir()} if refs_dir.is_dir() else set()

    for rel in sorted(linked):
        if not (s / rel).is_file():
            fail(f"{s.name} links {rel}, which does not exist")
    for rel in sorted(on_disk - linked):
        fail(f"{s.name}/{rel} exists but nothing links it — no agent will read it")
    if on_disk:
        ok(f"{s.name}: {len(on_disk)} reference(s), all linked")
    for f in sorted(refs_dir.iterdir()) if refs_dir.is_dir() else []:
        if len(f.read_text().strip()) < 200:
            fail(f"{s.name}/references/{f.name} is too short to be substantive")

btext = (root / "skills/using-skills/SKILL.md").read_text()
if "## Platform Adaptation" not in btext:
    fail("using-skills has no Platform Adaptation section")
else:
    ok("using-skills has a Platform Adaptation section")

# --- The delivery probe must still be able to prove delivery -----------------
# Every live harness verification depends on these phrases. If one is edited away
# the probe silently starts passing for the wrong reason.
probe = root / "skills/delivery-check/SKILL.md"
if not probe.is_file():
    fail("skills/delivery-check/SKILL.md missing — nothing can verify delivery")
else:
    ptext = probe.read_text()
    if "pelican-notarized-drift" not in ptext:
        fail("delivery-check lost phrase 1; live verification records refer to it")
    deep = root / "skills/delivery-check/references/deep-check.md"
    if not deep.is_file():
        fail("delivery-check/references/deep-check.md missing — step 3 cannot run")
    elif "walrus-escrowed-lantern" not in deep.read_text():
        fail("deep-check.md lost phrase 2")
    else:
        ok("delivery-check carries both confirmation phrases")

# The template must NOT carry a phrase: if it did, finding the template would
# look like proof of delivery.
tmpl = root / "skills/example-skill"
if tmpl.is_dir():
    blob = "\n".join(f.read_text() for f in tmpl.rglob("*.md"))
    for phrase in ("pelican-notarized-drift", "walrus-escrowed-lantern"):
        if phrase in blob:
            fail(f"example-skill contains {phrase!r}; the template must not be a probe")
    ok("example-skill carries no confirmation phrase")

# --- Gemini @-includes -------------------------------------------------------
gem = root / "GEMINI.md"
if not gem.is_file():
    fail("GEMINI.md missing")
else:
    includes = re.findall(r"^@(\./\S+)$", gem.read_text(), re.M)
    if not includes:
        fail("GEMINI.md has no @-includes")
    for inc in includes:
        if not (root / inc[2:]).is_file():
            fail(f"GEMINI.md includes {inc}, which does not exist")
    ok(f"GEMINI.md includes resolve ({len(includes)})")

import json
ext = root / "gemini-extension.json"
if ext.is_file():
    ctx_name = json.loads(ext.read_text()).get("contextFileName")
    if not ctx_name:
        fail("gemini-extension.json declares no contextFileName")
    elif not (root / ctx_name).is_file():
        fail(f"gemini-extension.json points at {ctx_name}, which does not exist")
    else:
        ok(f"contextFileName -> {ctx_name}")

# --- Skills must not name harness tools --------------------------------------
# This is the invariant that lets one skills/ tree serve every harness. Tool
# names belong in references/, never in a skill body.
TOOL_NAMES = ["TodoWrite", "AskUserQuestion", "WebFetch", "NotebookEdit"]
tool_violations = 0
for s in skills:
    body = (s / "SKILL.md").read_text()
    for tool in TOOL_NAMES:
        if tool in body:
            tool_violations += 1
            fail(f"{s.name}/SKILL.md names the harness tool {tool!r}; "
                 "skills name actions, not tools")
if not tool_violations:
    ok("no skill body names a harness-specific tool")

raise SystemExit(1 if fails else 0)
PY
rc=$?
[ $rc -eq 0 ] && echo "PASS: test-skill-integrity" || echo "FAILED: test-skill-integrity" >&2
exit $rc
