#!/usr/bin/env bash
# name, version, description, and the repo URL are duplicated across ten
# manifests. Nothing generates them, so editing one and forgetting the rest is
# the default failure mode — and the repo URL is still a placeholder, so this
# test exists to keep the drift at zero until the real one is chosen.
#
# package.json is the single source of truth. Every other manifest must agree.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "test-manifest-sync: name/version/URL agreement across manifests"

python3 - "$REPO_ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
fails = []
def fail(msg): fails.append(msg); print(f"FAIL: {msg}", file=sys.stderr)
def ok(msg): print(f"  ok  {msg}")

truth = json.loads((root / "package.json").read_text())
NAME, VERSION = truth["name"], truth["version"]
HOMEPAGE, REPO = truth["homepage"], truth["repository"]
ok(f"source of truth: package.json  name={NAME} version={VERSION}")

# (path, dotted accessor for name, for version) — None means "not carried here"
JSON_MANIFESTS = [
    (".claude-plugin/plugin.json",      "name", "version"),
    (".codex-plugin/plugin.json",       "name", "version"),
    (".cursor-plugin/plugin.json",      "name", "version"),
    (".devin-plugin/plugin.json",       "name", "version"),
    (".kimi-plugin/plugin.json",        "name", "version"),
    ("gemini-extension.json",           "name", "version"),
    (".claude-plugin/marketplace.json", "plugins.0.name", "plugins.0.version"),
    (".agents/plugins/marketplace.json", "plugins.0.name", None),
]

def dig(d, path):
    for part in path.split("."):
        d = d[int(part)] if part.isdigit() else d[part]
    return d

for rel, name_path, ver_path in JSON_MANIFESTS:
    p = root / rel
    if not p.exists():
        fail(f"{rel} missing"); continue
    d = json.loads(p.read_text())
    try:
        got_name = dig(d, name_path)
    except (KeyError, IndexError):
        fail(f"{rel}: no name at {name_path}"); continue
    if got_name != NAME:
        fail(f"{rel} name: got {got_name!r}, want {NAME!r}")
    if ver_path:
        try:
            got_ver = dig(d, ver_path)
        except (KeyError, IndexError):
            fail(f"{rel}: no version at {ver_path}"); continue
        if got_ver != VERSION:
            fail(f"{rel} version: got {got_ver!r}, want {VERSION!r}")
    ok(f"{rel}")

# YAML manifest — regex rather than a yaml dependency, matching the repo's
# zero-dependency stance.
y = (root / ".hermes-plugin/plugin.yaml").read_text()
for field, want in (("name", NAME), ("version", VERSION)):
    m = re.search(rf"^{field}:\s*(\S+)\s*$", y, re.M)
    if not m:
        fail(f".hermes-plugin/plugin.yaml: no {field}")
    elif m.group(1) != want:
        fail(f".hermes-plugin/plugin.yaml {field}: got {m.group(1)!r}, want {want!r}")
ok(".hermes-plugin/plugin.yaml")

# --- Repo URL agreement -----------------------------------------------------
# The URL is a placeholder until the real repository exists. Until then this
# check's job is to ensure it is the SAME placeholder everywhere, so swapping it
# later is a mechanical find-replace rather than an archaeology exercise.
URL_FIELDS = [
    (".claude-plugin/plugin.json", ["homepage", "repository"]),
    (".codex-plugin/plugin.json",  ["homepage", "repository"]),
    (".cursor-plugin/plugin.json", ["homepage", "repository"]),
    (".devin-plugin/plugin.json",  ["homepage", "repository"]),
    (".kimi-plugin/plugin.json",   ["homepage"]),
]
for rel, fields in URL_FIELDS:
    d = json.loads((root / rel).read_text())
    for f in fields:
        if f not in d:
            fail(f"{rel}: missing {f}"); continue
        want = HOMEPAGE if f == "homepage" else REPO
        if d[f] != want:
            fail(f"{rel} {f}: got {d[f]!r}, want {want!r}")
ok("homepage/repository match package.json")

# Nested interface blocks carry their own copy of the URL.
for rel, path in ((".codex-plugin/plugin.json", "interface.websiteURL"),
                  (".kimi-plugin/plugin.json",  "interface.websiteURL")):
    d = json.loads((root / rel).read_text())
    try:
        got = dig(d, path)
    except KeyError:
        fail(f"{rel}: missing {path}"); continue
    if got != HOMEPAGE:
        fail(f"{rel} {path}: got {got!r}, want {HOMEPAGE!r}")
ok("interface.websiteURL matches package.json")

# Install docs embed the clone URL. A stale one here is a broken install command
# for a real user, which is worse than a stale manifest field.
slug = HOMEPAGE.replace("https://github.com/", "")
install = (root / ".opencode/INSTALL.md").read_text()
urls = re.findall(r"git\+https://github\.com/([\w.-]+/[\w.-]+)\.git", install)
if not urls:
    fail(".opencode/INSTALL.md: found no git+https install URL to check")
for u in urls:
    if u != slug:
        fail(f".opencode/INSTALL.md: install URL {u!r} != {slug!r}")
ok(f".opencode/INSTALL.md install URLs ({len(urls)} found)")

# --- License consistency ----------------------------------------------------
# Six manifests assert MIT. A LICENSE file must back that assertion, and the
# upstream notice must ship, or the MIT grant we rely on is not satisfied.
if not (root / "LICENSE").exists():
    fail("LICENSE missing, but manifests declare a license")
notice = root / "THIRD_PARTY_NOTICES.md"
if not notice.exists():
    fail("THIRD_PARTY_NOTICES.md missing")
else:
    n = notice.read_text()
    if "Permission is hereby granted" not in n:
        fail("THIRD_PARTY_NOTICES.md does not reproduce the upstream permission notice")
    if "Jesse Vincent" not in n:
        fail("THIRD_PARTY_NOTICES.md does not carry the upstream copyright holder")
ok("LICENSE + THIRD_PARTY_NOTICES present and substantive")

raise SystemExit(1 if fails else 0)
PY
rc=$?
[ $rc -eq 0 ] && echo "PASS: test-manifest-sync" || echo "FAILED: test-manifest-sync" >&2
exit $rc
