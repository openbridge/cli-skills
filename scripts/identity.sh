#!/usr/bin/env bash
# Identity across the tree: name, version, homepage, repository.
#
# Ten manifests, two YAML/py literals, two filenames, and a set of install URLs
# all carry a copy of who this collection is. Nothing generated them, so editing
# one and forgetting the rest was the default failure. This reads
# .skills-identity.json and makes the whole set one operation.
#
#   identity.sh --check            verify every copy agrees with package.json
#   identity.sh --audit            grep for copies nothing is tracking
#   identity.sh set <field> <val>  write one field everywhere
#   identity.sh rename <new-name>  the fork operation: rename the collection
#
# Dependencies: bash + python3 + git, matching the rest of the repo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

python3 - "$@" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ["REPO_ROOT"])
CFG = json.loads((ROOT / ".skills-identity.json").read_text())
SRC_REL = CFG["source"]

fails = []
warns = []


def fail(msg):
    fails.append(msg)
    print(f"FAIL: {msg}", file=sys.stderr)


def warn(msg):
    warns.append(msg)
    print(f"warn  {msg}")


def ok(msg):
    print(f"  ok  {msg}")


# --- file access ------------------------------------------------------------
# Manifests round-trip byte-identically at indent=2, which tests/test-identity.sh
# asserts. If that ever stops being true, a set/rename would reformat a file it
# was only asked to edit one field of.

def read_json(rel):
    return json.loads((ROOT / rel).read_text())


def write_json(rel, data):
    (ROOT / rel).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def dig(obj, path):
    for part in path.split("."):
        obj = obj[int(part)] if part.isdigit() else obj[part]
    return obj


def put(obj, path, value):
    parts = path.split(".")
    for part in parts[:-1]:
        obj = obj[int(part)] if part.isdigit() else obj[part]
    last = parts[-1]
    if last.isdigit():
        obj[int(last)] = value
    else:
        obj[last] = value


def yaml_get(text, key):
    m = re.search(rf"^{re.escape(key)}:\s*(\S.*?)\s*$", text, re.M)
    return m.group(1) if m else None


def yaml_set(text, key, value):
    return re.sub(rf"^({re.escape(key)}:\s*).*$", lambda m: m.group(1) + value, text, count=1, flags=re.M)


def target_get(t):
    if "json" in t:
        try:
            return dig(read_json(t["file"]), t["json"])
        except (KeyError, IndexError):
            return None
    return yaml_get((ROOT / t["file"]).read_text(), t["yaml"])


def target_set(t, value):
    if "json" in t:
        d = read_json(t["file"])
        put(d, t["json"], value)
        write_json(t["file"], d)
    else:
        p = ROOT / t["file"]
        p.write_text(yaml_set(p.read_text(), t["yaml"], value))


def target_label(t):
    return f"{t['file']}:{t.get('json') or t['yaml']}"


def truth():
    return read_json(SRC_REL)


def derived_value(rule, src):
    return rule["template"].format(value=src[rule["from"]])


def slug_value(src):
    s = CFG["slug"]
    return src[s["from"]].replace(s["strip"], "")


# --- check ------------------------------------------------------------------

def regenerate_catalog():
    """The catalog embeds the collection name and version, so any identity write
    invalidates it. Regenerate rather than leave the tree inconsistent — a write
    command that requires a manual follow-up step is a write command people
    forget. Optional: a fork that deletes the catalog keeps working."""
    for name in ("catalog.sh", "registry.sh"):
        script = ROOT / "scripts" / name
        if not script.exists():
            continue
        res = subprocess.run(["bash", str(script)], capture_output=True, text=True)
        if res.returncode == 0:
            print(f"  regenerated via scripts/{name}")
        else:
            warn(f"scripts/{name} failed; run it manually\n{res.stderr.strip()}")


def cmd_check():
    src = truth()
    print(f"identity --check  (source of truth: {SRC_REL})")
    for field, targets in CFG["fields"].items():
        want = src.get(field)
        if want is None:
            fail(f"{SRC_REL} has no {field!r}")
            continue
        bad = 0
        for t in targets:
            got = target_get(t)
            if got is None:
                fail(f"{target_label(t)}: missing")
                bad += 1
            elif got != want:
                fail(f"{target_label(t)}: got {got!r}, want {want!r}")
                bad += 1
        if not bad:
            ok(f"{field} = {want!r} across {len(targets)} targets")

    for rule in CFG.get("derived", []):
        want = derived_value(rule, src)
        bad = 0
        for t in rule["targets"]:
            got = target_get(t)
            if got != want:
                fail(f"{target_label(t)}: got {got!r}, want {want!r} (derived from {rule['from']})")
                bad += 1
        if not bad:
            ok(f"{rule['id']} = {want!r} across {len(rule['targets'])} targets")

    want_slug = slug_value(src)
    for t in CFG["slug"]["targets"]:
        text = (ROOT / t["file"]).read_text()
        found = re.findall(t["pattern"], text)
        if not found:
            fail(f"{t['file']}: no occurrence matching {t['pattern']}")
            continue
        wrong = [f for f in found if f != want_slug]
        if wrong:
            fail(f"{t['file']}: slug {wrong[0]!r} != {want_slug!r}")
        else:
            ok(f"{t['file']} ({len(found)} install URLs) = {want_slug}")

    # The manifests can agree with each other perfectly and still all be wrong.
    # Nothing above compares them to the repository this actually lives in.
    # A warning, not a failure: a fork before its first push has no origin, and
    # a deliberate placeholder is a legitimate state.
    try:
        origin = subprocess.run(
            ["git", "-C", str(ROOT), "remote", "get-url", "origin"],
            capture_output=True, text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        origin = ""
    if origin:
        m = re.search(r"[/:]([\w.-]+/[\w.-]+?)(?:\.git)?$", origin)
        real = m.group(1) if m else None
        if real and real != want_slug:
            warn(f"manifests say {want_slug!r} but origin is {real!r} "
                 f"— run: scripts/identity.sh set homepage https://github.com/{real}")
        elif real:
            ok(f"matches git origin ({real})")

    return 1 if fails else 0


# --- audit ------------------------------------------------------------------

def field_files():
    """Files whose identity copies live at a declared JSON/YAML path."""
    files = set()
    for targets in CFG["fields"].values():
        files.update(t["file"] for t in targets)
    for rule in CFG.get("derived", []):
        files.update(t["file"] for t in rule["targets"])
    files.update(t["file"] for t in CFG["slug"]["targets"])
    return files


def is_declared_occurrence(line, needle):
    """True when the value sits at a whole-field position on this line."""
    if re.search(rf'"{re.escape(needle)}"', line):
        return True
    if re.search(rf"^\s*[\w.-]+:\s*{re.escape(needle)}\s*$", line):
        return True
    return False


def expected_values(src):
    """Every string an identity copy is legitimately allowed to appear inside.

    Whitelisting by file is too coarse (a marketplace *description* sits in a
    tracked file at an untracked path and nothing would update it), and matching
    by line shape is too crude (the repo name "ob-skills-template" contains the
    collection name "ob-skills" but is governed by `set homepage`, not
    `rename`). So: collect the exact values every declared target holds, and
    treat a line as declared when removing all of them leaves no needle behind.
    """
    values = set()
    for field, targets in CFG["fields"].items():
        if src.get(field) is not None:
            values.add(str(src[field]))
    for rule in CFG.get("derived", []):
        values.add(derived_value(rule, src))
    slug = slug_value(src)
    values.add(slug)
    values.add(slug.split("/")[-1])          # the repository name itself
    for r in CFG.get("renames", []):
        for ref in r["referenced_by"]:
            values.add(ref["template"].format(name=src["name"]))
        values.add(r["path"].format(name=src["name"]))
    # Longest first: strip "ob-skills-template" before "ob-skills", or the
    # shorter match leaves "-template" behind and the line still looks dirty.
    return sorted(values, key=len, reverse=True)


# A collection named for its own payload cannot be audited by grep. The payload
# directory is `skills/`, two generated files are `catalog/skills.json` and
# `skills.sh.json`, and "skills" is the single most common word in this
# repository's prose. Every one of those is indistinguishable from an untracked
# identity copy, so the name sweep returns hundreds of occurrences and no human
# can act on any of them. A check that always reports drift is a check nobody
# reads — the same failure as one that never does. Skip the sweep and say so.
STRUCTURAL_NAMES = {"skill", "skills"}


def cmd_audit():
    src = truth()
    name, version = src["name"], src["version"]
    excludes = [re.compile(p) for p in CFG["audit"]["exclude"]]
    # Files the literal pass rewrites wholesale need no per-line judgement.
    rewritten = {f.format(name=name) for f in CFG["literals"]["files"]}
    for r in CFG.get("renames", []):
        rewritten.add(r["path"].format(name=name))
    allowed = expected_values(src)
    declared = field_files()

    print(f"identity --audit  (name={name!r} version={version!r})")
    sweeps = [(name, "name"), (version, "version")]
    if name in STRUCTURAL_NAMES:
        sweeps = [(version, "version")]
        print(f"  skip  name sweep: {name!r} is also this repository's payload "
              f"directory, so grep cannot tell an identity copy from a path or "
              f"from ordinary prose")
        print(f"        --check still verifies every declared copy of the name; "
              f"only the untracked-copy sweep is lost")
    unexpected = 0
    for needle, label in sweeps:
        # --no-index reads the working tree rather than the index, and
        # --exclude-standard still honours .gitignore. A plain `git grep`
        # searches tracked content only, so it finds nothing at all in a tree
        # whose files are not committed yet — a fork on its first day, or a
        # scratch copy like the one tests/test-identity.sh builds. An audit
        # that silently scans nothing is the failure mode --audit exists to
        # prevent, so it must read what is on disk.
        try:
            out = subprocess.run(
                ["git", "-C", str(ROOT), "grep", "--no-index",
                 "--exclude-standard", "-I", "-n", "-F", needle],
                capture_output=True, text=True).stdout
        except FileNotFoundError:
            fail("git not available; --audit needs it")
            return 1
        for line in out.splitlines():
            path, _, rest = line.partition(":")
            _, _, body = rest.partition(":")
            if path in rewritten or any(e.search(path) for e in excludes):
                continue
            # Strip only the LONGER strings that legitimately contain the
            # needle (the repo name, the derived marketplace name, plugin
            # filenames). The needle itself must never be stripped, or this
            # check silently passes on everything — which it did, until a
            # mutation test caught it.
            residue = body
            for value in allowed:
                if value != needle:
                    residue = residue.replace(value, "")
            if needle not in residue:
                continue
            # What remains is a bare occurrence. In a file that declares the
            # value at a JSON/YAML path, the field form itself is legitimate.
            if path in declared and is_declared_occurrence(residue, needle):
                continue
            print(f"  {label}: {line}")
            unexpected += 1
    if unexpected:
        print(f"\n{unexpected} occurrence(s) outside .skills-identity.json.")
        print("Each is a copy nothing keeps in sync. Add it to the config, or "
              "rewrite it so it reads identity at runtime.")
        # Nonzero, because CONTRIBUTING lists this among the pre-pull-request
        # checks and CI cannot gate on a command that always succeeds. A drift
        # checker that reports drift and exits 0 is the same bug --audit was
        # written to catch, one level up.
        return 1
    ok("no untracked occurrences")
    return 0


# --- set --------------------------------------------------------------------

def cmd_set(field, value):
    if field not in CFG["fields"]:
        fail(f"unknown field {field!r}; known: {', '.join(CFG['fields'])}")
        return 2
    if field == "name":
        fail("use `identity.sh rename <new-name>` — the name also appears in "
             "source literals and two filenames that `set` does not touch")
        return 2
    for t in CFG["fields"][field]:
        target_set(t, value)
    print(f"set {field} = {value!r} in {len(CFG['fields'][field])} targets")
    if field == "version":
        regenerate_catalog()
    if field == "homepage":
        src = truth()
        new_slug = slug_value(src)
        for t in CFG["slug"]["targets"]:
            p = ROOT / t["file"]
            text = p.read_text()
            text = re.sub(t["pattern"], lambda m: m.group(0).replace(m.group(1), new_slug), text)
            p.write_text(text)
        print(f"rewrote install slugs to {new_slug}")
    return 0


# --- rename -----------------------------------------------------------------

def cmd_rename(new):
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", new):
        fail(f"{new!r} is not a usable plugin name (lowercase, digits, . _ -)")
        return 2
    src = truth()
    old = src["name"]
    if old == new:
        print(f"already named {new!r}; nothing to do")
        return 0

    # When the collection name and the repository name are the same string, a
    # bare occurrence of it in prose or an install URL is ambiguous: nothing in
    # the text says which identity it is. The masking in step 4 below is what
    # keeps a rename from rewriting install URLs, and it needs the two names to
    # differ in order to tell them apart. Refusing is the only honest option --
    # the alternative is silently corrupting every install command.
    repo_slug = slug_value(src)
    if repo_slug.split("/")[-1] == old:
        fail(f"collection name {old!r} is also the repository name in "
             f"{repo_slug!r}, so a rename cannot tell the two apart and would "
             f"rewrite every install URL.\n"
             f"  Point the repository elsewhere first:\n"
             f"    identity.sh set homepage https://github.com/<owner>/<repo>")
        return 2

    print(f"rename {old!r} -> {new!r}")

    # 1. filenames first, so the literal pass below reads the moved files.
    for r in CFG.get("renames", []):
        old_path = r["path"].format(name=old)
        new_path = r["path"].format(name=new)
        if not (ROOT / old_path).exists():
            warn(f"{old_path} not found; skipping rename")
            continue
        res = subprocess.run(["git", "-C", str(ROOT), "mv", old_path, new_path],
                             capture_output=True, text=True)
        if res.returncode != 0:
            (ROOT / old_path).rename(ROOT / new_path)
        print(f"  moved {old_path} -> {new_path}")
        for ref in r["referenced_by"]:
            target_set(ref, ref["template"].format(name=new))
            print(f"  updated {target_label(ref)}")

    # 2. declarative name targets.
    for t in CFG["fields"]["name"]:
        target_set(t, new)
    print(f"  set name in {len(CFG['fields']['name'])} manifest targets")

    # 3. derived values.
    src = truth()
    for rule in CFG.get("derived", []):
        if rule["from"] != "name":
            continue
        val = derived_value(rule, src)
        for t in rule["targets"]:
            target_set(t, val)
        print(f"  set {rule['id']} = {val!r}")

    # 4. bare string literals no JSON path can reach.
    #
    # The collection name and the repository name are different identities that
    # happen to look alike ("ob-skills" lives inside "ob-skills-template"). A
    # naive replace rewrites the repo name too, corrupting every install URL and
    # the README title. Mask the repo name, replace, unmask. Changing the repo
    # identity is `set homepage`, not `rename`.
    repo_name = slug_value(src).split("/")[-1]
    MASK = "\x00repo\x00"
    touched = 0
    for tmpl in CFG["literals"]["files"]:
        p = ROOT / tmpl.format(name=new)
        if not p.exists():
            warn(f"{p.relative_to(ROOT)} not found; skipping literals")
            continue
        text = p.read_text()
        if old not in text:
            continue
        masked = text.replace(repo_name, MASK)
        rewritten = masked.replace(old, new).replace(MASK, repo_name)
        if rewritten != text:
            p.write_text(rewritten)
            touched += 1
    print(f"  rewrote literals in {touched} file(s) (repo name {repo_name!r} left alone)")

    # 5. the catalog carries the collection name; leave no stale generated file.
    regenerate_catalog()

    print("\nDone. Now run:")
    print("  scripts/identity.sh --check")
    print("  scripts/identity.sh --audit    # catches literals nothing tracked")
    return 0


# --- dispatch ---------------------------------------------------------------

args = sys.argv[1:]
cmd = args[0] if args else "--check"

if cmd == "--check":
    rc = cmd_check()
elif cmd == "--audit":
    rc = cmd_audit()
elif cmd == "set":
    if len(args) != 3:
        print("usage: identity.sh set <field> <value>", file=sys.stderr)
        rc = 2
    else:
        rc = cmd_set(args[1], args[2])
elif cmd == "rename":
    if len(args) != 2:
        print("usage: identity.sh rename <new-name>", file=sys.stderr)
        rc = 2
    else:
        rc = cmd_rename(args[1])
else:
    print(f"unknown command {cmd!r}; try --help", file=sys.stderr)
    rc = 2

raise SystemExit(rc)
PY
