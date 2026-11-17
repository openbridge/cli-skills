#!/usr/bin/env bash
# Run the trigger evals: does a prompt actually pull in the skill it should?
#
#   eval.sh --check        structural validation only; no model, no cost
#   eval.sh --dry-run      print the prompts that would be sent; no cost
#   eval.sh --run          actually call a model  (THIS SPENDS MONEY)
#   eval.sh --record       --run, then write evals/results.json
#
# Running costs real money on whoever's account the model command bills. It is
# behind an explicit flag for that reason: --check and --dry-run are the free
# paths, and a bare invocation does nothing but tell you so. The official
# `claude plugin eval` harness is far more expensive again — a recorded pass
# over three cases with ablation came to $4.68.
#
# --record writes evals/results.json: the artifact that lets someone point at a
# run rather than at the intention to do one. It is supporting evidence, NOT the
# certification gate.
#
# The gate scripts/catalog.sh actually enforces for `classification: certified`
# is narrower: the skill must carry both a positive and a negative trigger case.
# That is checked offline and for free. Nothing in this repository requires a
# recorded run, because nothing here has paid for one — see the decision in
# docs/status.md.
#
# The governance field is `classification`, in catalog/entries/<name>.json.
# There is no `tier` field anywhere in this repository.
#
# Deliberately NOT part of tests/run-tests.sh. That suite is offline, free, and
# deterministic, and it stays that way. This one calls a model: it costs money,
# it can disagree with itself between runs, and it must never gate a commit.
#
# The model call is delegated, so this works with whatever you already have:
#
#   SKILLS_EVAL_CMD='claude -p'          # default when `claude` is on PATH
#   SKILLS_EVAL_CMD='codex exec'
#   SKILLS_EVAL_CMD='./my-model-wrapper'
#
# The command receives the full prompt on stdin and must print the answer on
# stdout. Nothing else about it is assumed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

MODE=""
RECORD=0
case "${1:-}" in
  --check)   MODE="check";   shift ;;
  --dry-run) MODE="dry-run"; shift ;;
  --run)     MODE="run";     shift ;;
  --record)  MODE="run"; RECORD=1; shift ;;
esac

if [ -z "$MODE" ]; then
  cat >&2 <<'MSG'
Nothing run. Calling a model costs money, so it needs an explicit flag:

  scripts/eval.sh --check      structure only, free
  scripts/eval.sh --dry-run    show the prompts, free
  scripts/eval.sh --run        call a model  (SPENDS MONEY)
  scripts/eval.sh --record     --run, then write evals/results.json

MSG
  exit 2
fi
export EVAL_RECORD="$RECORD"
export EVAL_RECORDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$MODE" = "run" ] && [ -z "${SKILLS_EVAL_CMD:-}" ]; then
  if command -v claude >/dev/null 2>&1; then
    SKILLS_EVAL_CMD='claude -p'
  else
    echo "No model command. Set SKILLS_EVAL_CMD, or use --check / --dry-run." >&2
    exit 2
  fi
fi
export SKILLS_EVAL_CMD="${SKILLS_EVAL_CMD:-}"
export EVAL_MODE="$MODE"

python3 - "$@" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ["REPO_ROOT"])
MODE = os.environ["EVAL_MODE"]
RECORD = os.environ.get("EVAL_RECORD") == "1"
CMD = os.environ.get("SKILLS_EVAL_CMD", "")
only = set(sys.argv[1:])

catalog_path = ROOT / "catalog" / "skills.json"
if not catalog_path.exists():
    print("catalog/skills.json missing — run scripts/catalog.sh", file=sys.stderr)
    raise SystemExit(2)
catalog = json.loads(catalog_path.read_text())
known = {s["name"]: s["description"] for s in catalog["skills"]}

# --- load and validate cases ------------------------------------------------
# Format is evals/<skill>/trigger-cases.json: a flat array of
# {query, should_trigger}, matching the shape used across sibling collections so
# that anything able to read one can read the other. Two additive keys a plain
# reader can ignore:
#   expect_skill  which skill should win instead (a boolean cannot say)
#   note          what the case protects, so it is not deleted when it first fails
problems = []
files = sorted((ROOT / "evals").glob("*/trigger-cases.json"))
suites = []
for f in files:
    rel = f.relative_to(ROOT)
    skill = f.parent.name
    try:
        cases = json.loads(f.read_text())
    except json.JSONDecodeError as e:
        problems.append(f"{rel}: invalid JSON ({e})")
        continue
    if not isinstance(cases, list) or not cases:
        problems.append(f"{rel}: expected a non-empty array of cases")
        continue
    if skill not in known:
        problems.append(f"{rel}: skill {skill!r} is not in the catalog")
    seen = set()
    for i, c in enumerate(cases):
        if not isinstance(c, dict):
            problems.append(f"{rel}[{i}]: case is not an object")
            continue
        # `not c.get("query")` let a truthy non-string through — 42, True, a
        # list — even though evals/schema.json declares a string.
        if not isinstance(c.get("query"), str) or not c["query"].strip():
            problems.append(f"{rel}[{i}]: 'query' must be a non-empty string, "
                            f"got {c.get('query')!r}")
        if not isinstance(c.get("should_trigger"), bool):
            problems.append(f"{rel}[{i}]: 'should_trigger' must be true or false")
        if c.get("query") in seen:
            problems.append(f"{rel}[{i}]: duplicate query")
        seen.add(c.get("query"))
        exp = c.get("expect_skill")
        if exp is not None:
            if c.get("should_trigger"):
                problems.append(f"{rel}[{i}]: expect_skill is meaningless when "
                                f"should_trigger is true")
            elif exp not in known:
                problems.append(f"{rel}[{i}]: expect_skill {exp!r} is not in the catalog")
    # Certification's documented gate, and the reason it is checked here too: a
    # suite of positives proves only that a skill can fire.
    if not any(c.get("should_trigger") is False for c in cases if isinstance(c, dict)):
        problems.append(f"{rel}: no negative case (should_trigger: false); nothing "
                        f"tests that {skill!r} stays out of other skills' way")
    # Per skill. Counting collision cases across the whole tree and reporting
    # that every skill had one is how a scaffolded skill with none passed on
    # the strength of somebody else's.
    if not any(c.get("expect_skill") for c in cases if isinstance(c, dict)):
        problems.append(f"{rel}: no collision case; nothing tests that {skill!r} "
                        f"is not taking a neighbouring skill's prompts. Add a "
                        f"case with should_trigger false and expect_skill set "
                        f"to the skill that should win instead")
    if not only or skill in only:
        suites.append((rel, skill, cases))


def expected_for(skill, case):
    """The skill that should win, or None when nothing should fire."""
    if case.get("should_trigger"):
        return skill
    return case.get("expect_skill")


if MODE == "check":
    for p in problems:
        print(f"FAIL: {p}", file=sys.stderr)
    for name in known:
        if name not in {f.parent.name for f in files}:
            print(f"FAIL: skills/{name} has no evals/{name}/trigger-cases.json", file=sys.stderr)
            problems.append(name)
    if not problems:
        total = sum(len(c) for _, _, c in suites)
        print(f"eval --check  ok  {len(suites)} suite(s), {total} cases, all well-formed")
    raise SystemExit(1 if problems else 0)

if problems:
    for p in problems:
        print(f"FAIL: {p}", file=sys.stderr)
    raise SystemExit(1)


# --- the prompt -------------------------------------------------------------
# Every skill is offered for every case. A per-skill yes/no question cannot
# surface the failure this whole format exists for: two descriptions competing
# for the same prompt.
def build_prompt(user_message):
    lines = [
        "You are choosing which skill, if any, to load before answering a user.",
        "",
        "Available skills:",
    ]
    for name, desc in sorted(known.items()):
        lines.append(f"- {name}: {desc}")
    lines += [
        "",
        "Rules:",
        "- Choose the single MOST SPECIFIC applicable skill.",
        "- If no skill genuinely applies, answer NONE.",
        "- Answer with the skill name alone, or NONE. No explanation.",
        "",
        f"User message: {user_message}",
        "",
        "Skill:",
    ]
    return "\n".join(lines)


if MODE == "dry-run":
    for rel, skill, cases in suites:
        for c in cases:
            print("=" * 70)
            print(f"{rel}  expect={expected_for(skill, c)}")
            print(build_prompt(c["query"]))
    raise SystemExit(0)


def normalise(raw):
    """Reduce a model's reply to a bare skill name, or None for NONE.

    Answers arrive namespaced ("<collection>:<skill>"), backticked, bulleted,
    or trailing a full sentence. None of that is a description problem, so none
    of it should count as one.
    """
    line = ""
    for candidate in reversed(raw.strip().splitlines()):
        if candidate.strip():
            line = candidate.strip()
            break
    line = line.strip("-*• \t").strip()
    line = line.strip(".`'\"")
    if ":" in line:                      # collection:skill
        line = line.rsplit(":", 1)[-1].strip().strip(".`'\"")
    if line.upper() == "NONE":
        return None
    return line


def ask(prompt):
    res = subprocess.run(CMD, shell=True, input=prompt,
                         capture_output=True, text=True)
    if res.returncode != 0:
        return "", res.stderr.strip()
    return res.stdout, None


results = []
off_catalog = []
for rel, skill, cases in suites:
    print(f"\n── {rel} ──")
    for c in cases:
        raw, err = ask(build_prompt(c["query"]))
        if err:
            print(f"  ERR  {c['query'][:60]}...\n       {err}")
            results.append((rel, c, None, False, False))
            continue
        want = expected_for(skill, c)
        norm = normalise(raw)
        # An answer naming something outside this catalog is not a verdict on
        # any description here. It means the eval command is an agent with its
        # own skills, answering from those instead of the list it was given.
        contaminated = norm is not None and norm not in known
        hit = (not contaminated) and norm == want
        mark = "ok  " if hit else ("OFF " if contaminated else "MISS")
        shown = (norm or "NONE")[:24]
        print(f"  {mark} want={want or 'NONE':<16} got={shown:<24} {c['query'][:46]}")
        if contaminated:
            off_catalog.append((c["query"], norm))
        elif not hit:
            if c.get("note"):
                print(f"       why this case exists: {c['note']}")
        results.append((rel, c, norm, hit, contaminated))

total = len(results)
hits = sum(1 for *_, h, _ in results if h)
print(f"\n{'=' * 70}\n{hits}/{total} cases matched")

if off_catalog:
    print(f"\n{len(off_catalog)} answer(s) named a skill outside this catalog:")
    for prompt, name in off_catalog:
        print(f"  {name!r}  <- {prompt[:50]}")
    print("\nThese are not description problems. SKILLS_EVAL_CMD is running an")
    print("agent that carries its own skills and answered from those. Point it at")
    print("a bare model call — an agent harness cannot evaluate a catalog it is")
    print("already overriding.")

# The two real failure kinds need opposite fixes, so never merge them.
missed = [c for _, c, g, h, bad in results if not h and not bad and g is None]
overreach = {}
for _, c, g, h, bad in results:
    if not h and not bad and g is not None:
        overreach[g] = overreach.get(g, 0) + 1
if missed:
    print(f"\nDid not fire when they should have: {len(missed)}")
    for c in missed:
        print(f"  {c['query'][:66]}")
if overreach:
    print("Fired on prompts belonging elsewhere:")
    for name, n in sorted(overreach.items(), key=lambda kv: -kv[1]):
        print(f"  {name}: {n} case(s) — its description is too broad")

if RECORD:
    if only:
        print("\n--record needs a full run; drop the skill filter.", file=sys.stderr)
        raise SystemExit(2)
    # A skill earns certification only when every case in its own suite passed
    # AND no other suite's case was wrongly answered with it. Firing on someone
    # else's prompts is a defect even when your own cases are green.
    misfired = {g for _, c, g, h, bad in results if not h and not bad and g is not None}
    per_skill = {}
    for rel, c, g, h, bad in results:
        skill = Path(rel).parent.name
        st = per_skill.setdefault(skill, {"cases": 0, "passed": 0, "off_catalog": 0})
        st["cases"] += 1
        st["passed"] += 1 if h else 0
        st["off_catalog"] += 1 if bad else 0

    for skill, st in per_skill.items():
        st["certified"] = (
            st["passed"] == st["cases"]
            and st["off_catalog"] == 0
            and skill not in misfired
        )
        if skill in misfired:
            st["withheld"] = "fired on a prompt belonging to another skill"
        elif st["off_catalog"]:
            st["withheld"] = "run was contaminated; answers named skills outside the catalog"
        elif st["passed"] != st["cases"]:
            st["withheld"] = "not every case passed"

    out = ROOT / "evals" / "results.json"
    out.write_text(json.dumps({
        "version": 1,
        "recorded_at": os.environ.get("EVAL_RECORDED_AT", ""),
        "recorded_by": "scripts/eval.sh --record",
        "command": CMD,
        "skills": dict(sorted(per_skill.items())),
    }, indent=2, ensure_ascii=False) + "\n")
    certified = sorted(k for k, v in per_skill.items() if v["certified"])
    print(f"\nwrote evals/results.json — certified: {', '.join(certified) or 'none'}")

raise SystemExit(0 if hits == total else 1)
PY
