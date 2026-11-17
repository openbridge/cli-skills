#!/usr/bin/env bash
# Generate catalog/skills.json.
#
#   catalog.sh            regenerate
#   catalog.sh --check    fail if stale (for CI)
#
# Two sources, and the split is deliberate:
#
#   SKILL.md frontmatter   the Agent Skills specification's discovery fields
#                          (name, description, license, compatibility, metadata,
#                          allowed-tools). Generated from, never duplicated.
#   catalog/entries/*.json governance — classification, origin, maintainers,
#                          licence, registries, source. Hand-written, because
#                          none of it is derivable from a skill describing
#                          itself. Not duplication; different facts.
#
# Spec: https://agentskills.io/specification
#
# Dependencies: bash + python3.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

python3 - "$@" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ["REPO_ROOT"])
OUT = ROOT / "catalog" / "skills.json"
ENTRIES = ROOT / "catalog" / "entries"

# The specification's frontmatter field set. Anything else is rejected rather
# than passed through: the spec says client-specific properties belong under
# `metadata`, and a collection that invents top-level keys teaches every fork
# to do the same.
SPEC_FIELDS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
CLASSIFICATIONS = {"certified", "reference"}
ORIGINS = {"first-party", "third-party"}

fails = []


def fail(msg):
    fails.append(msg)
    print(f"FAIL: {msg}", file=sys.stderr)


# A plain (unquoted) YAML scalar cannot contain ": " and cannot start with an
# indicator character — a real parser either errors or reads something other
# than the author intended. The old parser accepted both by splitting on the
# first colon, so `description: Use when reviewing code: before merge` passed
# here and failed in PyYAML: this generator certified a file the format it
# claims to enforce cannot read.
PLAIN_FORBIDDEN = re.compile(r":(?:\s|$)| #")
INDICATORS = set("-?:,[]{}#&*!|>'\"%@`")


def decode_scalar(raw, label, key):
    """One YAML scalar from the subset this repository supports.

    Quoted forms are decoded properly; plain forms are checked for the
    constructs that make them mean something else. Anything outside the subset
    is rejected with the fix in the message, never silently reinterpreted.
    """
    s = raw.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        try:
            return json.loads(s)
        except json.JSONDecodeError:
            fail(f"{label}: {key}: cannot decode double-quoted scalar {s!r}. "
                 f"Backslashes and inner quotes must be escaped.")
            return ""
    if len(s) >= 2 and s[0] == "'" and s[-1] == "'":
        inner = s[1:-1]
        if re.search(r"(?<!')'(?!')", inner.replace("''", "\x00\x00")):
            fail(f"{label}: {key}: unbalanced quote in single-quoted scalar {s!r}")
            return ""
        return inner.replace("''", "'")
    if s and s[0] in INDICATORS:
        fail(f"{label}: {key}: plain scalar starts with the YAML indicator "
             f"{s[0]!r}. Quote the value.")
        return ""
    if PLAIN_FORBIDDEN.search(s):
        fail(f"{label}: {key}: plain scalar contains ': ' or ' #', which YAML "
             f"reads as a mapping or a comment: {s!r}. Quote the value.")
        return ""
    return s


def parse_frontmatter(text, label):
    """Minimal YAML: scalars, inline lists, block lists, and one nested map.

    A real YAML parser is a dependency this repo does not have, and neither do
    the adapters — the hook and the Hermes plugin both read frontmatter with
    regexes. Supporting exactly what the spec permits keeps parser and format
    honest about each other.

    The subset is documented in docs/skill-format.md. What is NOT supported is
    rejected rather than half-read: anchors, aliases, multi-line block scalars,
    nested maps below one level, and plain scalars carrying YAML syntax.
    """
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        fail(f"{label}: no YAML frontmatter")
        return {}
    data, key, nested = {}, None, None
    seen = set()
    for raw in m.group(1).split("\n"):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.startswith("  ") and not raw.startswith("  - ") and nested is not None:
            km = re.match(r"^\s+([A-Za-z0-9_-]+):\s*(.*)$", raw)
            if km:
                data[nested][km.group(1)] = decode_scalar(
                    km.group(2), label, f"{nested}.{km.group(1)}")
                continue
        if raw.startswith(("  - ", "- ")):
            if key is None:
                fail(f"{label}: list item before any key")
                continue
            data.setdefault(key, []).append(
                decode_scalar(raw.split("- ", 1)[1], label, f"{key}[]"))
            continue
        km = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", raw)
        if not km:
            fail(f"{label}: cannot parse frontmatter line {raw!r}")
            continue
        key, value = km.group(1), km.group(2).strip()
        # A duplicate key is a silent overwrite here and an error in YAML. The
        # author meant one of the two and has no way to tell which survived.
        if key in seen:
            fail(f"{label}: duplicate frontmatter key {key!r}")
        seen.add(key)
        nested = None
        if value == "":
            data[key] = {}
            nested = key
        elif value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            data[key] = ([decode_scalar(v, label, f"{key}[]")
                          for v in inner.split(",")] if inner else [])
        else:
            data[key] = decode_scalar(value, label, key)
    # A key opened as a map but never filled is a block list, not a map.
    for k, v in list(data.items()):
        if v == {}:
            data[k] = []
    return data


def check_spec(fm, dirname):
    """Enforce the specification's own constraints, not a looser house version."""
    label = f"skills/{dirname}"
    extra = set(fm) - SPEC_FIELDS
    if extra:
        fail(f"{label}: frontmatter keys outside the Agent Skills spec: {sorted(extra)}. "
             f"Client-specific properties belong under `metadata`.")
    name = fm.get("name")
    if not name:
        fail(f"{label}: no name")
    else:
        if name != dirname:
            fail(f"{label}: frontmatter name {name!r} does not match the directory")
        if len(name) > 64:
            fail(f"{label}: name is {len(name)} characters, spec maximum is 64")
        # Rejects a leading/trailing hyphen and consecutive hyphens, which a
        # naive ^[a-z0-9][a-z0-9-]*$ lets through.
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name):
            fail(f"{label}: name {name!r} must be lowercase alphanumerics and single "
                 f"hyphens, not starting or ending with one")
    # Every field the spec defines as a scalar must actually BE one. Without
    # this, `description: [not, a, string]` parsed to a list, passed every
    # check below, and was written into catalog/skills.json as a JSON array —
    # a generator emitting a shape the specification it cites does not allow.
    for field in ("description", "license", "compatibility", "allowed-tools"):
        # `field:` with nothing after it parses as an empty block, not as a
        # string. Saying "got list" sends the author looking for a list.
        if fm.get(field) == []:
            fail(f"{label}: {field} has no value")
        elif field in fm and not isinstance(fm[field], str):
            fail(f"{label}: {field} must be a string, got "
                 f"{type(fm[field]).__name__}")
        # An empty optional scalar is a field the author started and did not
        # finish. Absent says that; present-and-blank says nothing.
        elif field in fm and field != "description" and not fm[field].strip():
            fail(f"{label}: {field} is present but empty — omit it instead")

    desc = fm.get("description")
    if not desc:
        fail(f"{label}: no description")
    elif isinstance(desc, str) and len(desc) > 1024:
        fail(f"{label}: description is {len(desc)} characters, spec maximum is 1024")
    compat = fm.get("compatibility")
    if isinstance(compat, str) and len(compat) > 500:
        fail(f"{label}: compatibility is {len(compat)} characters, spec maximum is 500")

    meta = fm.get("metadata")
    if meta is not None and not isinstance(meta, dict):
        fail(f"{label}: metadata must be a map of string keys to string values")
    elif isinstance(meta, dict):
        # The spec says string keys to string values. A nested map or list here
        # is the same class of defect as a non-string description, and metadata
        # is exactly where client-specific junk accumulates.
        for k, v in meta.items():
            if not isinstance(k, str) or not isinstance(v, str):
                fail(f"{label}: metadata.{k} must map a string key to a string "
                     f"value, got {type(v).__name__}")
    return not fails


def load_entry(name):
    p = ENTRIES / f"{name}.json"
    if not p.exists():
        fail(f"catalog/entries/{name}.json missing — every skill needs a governance record")
        return None
    try:
        e = json.loads(p.read_text())
    except json.JSONDecodeError as exc:
        fail(f"catalog/entries/{name}.json: invalid JSON ({exc})")
        return None
    label = f"catalog/entries/{name}.json"
    if e.get("name") != name:
        fail(f"{label}: name {e.get('name')!r} does not match the file")
    for field in ("classification", "origin", "maintainers", "license", "registries"):
        if field not in e:
            fail(f"{label}: missing required {field!r}")
    if e.get("classification") not in CLASSIFICATIONS:
        fail(f"{label}: classification must be one of {sorted(CLASSIFICATIONS)}")
    if e.get("origin") not in ORIGINS:
        fail(f"{label}: origin must be one of {sorted(ORIGINS)}")
    if not isinstance(e.get("maintainers"), list) or not e.get("maintainers"):
        fail(f"{label}: maintainers must be a non-empty list")
    else:
        for m in e["maintainers"]:
            if not isinstance(m, str) or not m.strip():
                fail(f"{label}: maintainers entries must be non-empty strings, got {m!r}")
    if not isinstance(e.get("license"), str) or not e["license"].strip():
        fail(f"{label}: license must be a non-empty string")
    if not isinstance(e.get("registries"), dict):
        fail(f"{label}: registries must be an object")
    else:
        for k, v in e["registries"].items():
            if not isinstance(v, str) or not v.strip():
                fail(f"{label}: registries.{k} must be a non-empty string, got {v!r}")
    # Without an immutable revision there is no statement of what was reviewed.
    if e.get("origin") == "third-party":
        src = e.get("source")
        if not isinstance(src, dict):
            fail(f"{label}: third-party entries must record a source")
        else:
            for field in ("repository", "revision", "path"):
                if not src.get(field):
                    fail(f"{label}: source.{field} is required for a third-party skill")
            if src.get("repository") and not str(src["repository"]).startswith("https://"):
                fail(f"{label}: source.repository must be an https URL")
            if src.get("revision") and not re.fullmatch(r"[0-9a-f]{40,64}", str(src["revision"])):
                fail(f"{label}: source.revision must be a full commit hash")
            if not isinstance(src.get("path"), str) or not str(src.get("path", "")).strip():
                fail(f"{label}: source.path must be a non-empty string")
            if set(src) - {"repository", "revision", "path"}:
                fail(f"{label}: source carries keys outside the schema: "
                     f"{sorted(set(src) - {'repository', 'revision', 'path'})}")
            # The scaffold's placeholders satisfy every rule above: the URL is
            # https and the revision is forty lowercase hex characters. A
            # comment in new-skill.sh claimed they were "deliberately invalid"
            # and nothing checked, so a fabricated provenance record could ship
            # looking reviewed.
            if str(src.get("repository", "")).upper().endswith("/OWNER/REPO"):
                fail(f"{label}: source.repository is still the scaffold placeholder")
            if re.fullmatch(r"0+", str(src.get("revision", "x"))):
                fail(f"{label}: source.revision is still the all-zero placeholder")
    return e


def trigger_case_polarity(name):
    """Certification's documented gate: both positive and negative cases exist.

    A suite of positives proves only that a skill can fire. Whether it stays out
    of other skills' way is the half that decays as a collection grows, so a
    certified claim without negatives certifies the easy direction only.
    """
    p = ROOT / "evals" / name / "trigger-cases.json"
    if not p.exists():
        return False, False
    try:
        cases = json.loads(p.read_text())
    except json.JSONDecodeError:
        fail(f"evals/{name}/trigger-cases.json: invalid JSON")
        return False, False
    pos = any(c.get("should_trigger") is True for c in cases)
    neg = any(c.get("should_trigger") is False for c in cases)
    return pos, neg


def build():
    skills = []
    for d in sorted((ROOT / "skills").iterdir()):
        if not d.is_dir():
            continue
        skill_md = d / "SKILL.md"
        if not skill_md.exists():
            fail(f"skills/{d.name}: no SKILL.md")
            continue
        fm = parse_frontmatter(skill_md.read_text(), f"skills/{d.name}")
        if not fm:
            continue
        check_spec(fm, d.name)
        entry = load_entry(d.name)
        if entry is None:
            continue

        if entry.get("classification") == "certified":
            pos, neg = trigger_case_polarity(d.name)
            if not (pos and neg):
                missing = []
                if not pos:
                    missing.append("positive")
                if not neg:
                    missing.append("negative")
                fail(f"catalog/entries/{d.name}.json claims 'certified' but "
                     f"evals/{d.name}/trigger-cases.json has no {' or '.join(missing)} case(s)")
                continue

        record = {
            "name": fm["name"],
            "description": fm["description"],
        }
        for optional in ("license", "compatibility", "metadata", "allowed-tools"):
            if fm.get(optional):
                record[optional] = fm[optional]
        record.update({
            "status": entry["classification"],
            "origin": entry["origin"],
            "maintainers": entry["maintainers"],
            "registries": entry["registries"],
            "governanceLicense": entry["license"],
            # Additive, beyond the spec's discovery fields: a consumer reads
            # `files` to know whether sibling delivery matters for this skill.
            "path": f"skills/{d.name}",
            "files": sorted(str(p.relative_to(d)) for p in d.rglob("*") if p.is_file()),
        })
        if entry.get("source"):
            record["source"] = entry["source"]
        skills.append(record)

    # Orphaned governance records point at skills that no longer exist.
    for p in sorted(ENTRIES.glob("*.json")):
        if not (ROOT / "skills" / p.stem).is_dir():
            fail(f"catalog/entries/{p.name} has no matching skill directory")

    return {"catalogVersion": 1, "skills": skills}


catalog = build()
if fails:
    raise SystemExit(1)

rendered = json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"

if sys.argv[1:2] == ["--check"]:
    if not OUT.exists():
        fail("catalog/skills.json missing — run scripts/catalog.sh")
        raise SystemExit(1)
    current = OUT.read_text()
    if current != rendered:
        fail("catalog/skills.json is stale — run scripts/catalog.sh")
        try:
            old = {s["name"]: s for s in json.loads(current)["skills"]}
        except Exception:
            old = {}
        new = {s["name"]: s for s in catalog["skills"]}
        for n in sorted(set(old) | set(new)):
            if n not in old:
                print(f"  + {n}", file=sys.stderr)
            elif n not in new:
                print(f"  - {n}", file=sys.stderr)
            elif old[n] != new[n]:
                changed = [k for k in set(old[n]) | set(new[n]) if old[n].get(k) != new[n].get(k)]
                print(f"  ~ {n}: {', '.join(sorted(changed))}", file=sys.stderr)
        raise SystemExit(1)
    print(f"catalog --check  ok  {len(catalog['skills'])} skills, catalog current")
    raise SystemExit(0)

OUT.parent.mkdir(exist_ok=True)
OUT.write_text(rendered)
print(f"wrote catalog/skills.json  ({len(catalog['skills'])} skills)")
for s in catalog["skills"]:
    print(f"  {s['status']:10} {s['origin']:12} {s['name']:20} {len(s['files'])} file(s)")
PY
