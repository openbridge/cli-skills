#!/usr/bin/env python3
"""Hermes plugin: skill registration + first-turn injection.

Two failure modes worth a permanent test:

1. ``register_skill`` requires a ``pathlib.Path``. Passing a ``str`` raises
   AttributeError inside Hermes, and Hermes responds by silently disabling the
   entire plugin — no skills, no bootstrap, and no error the user ever sees. The
   fake context here asserts the type, so a regression fails loudly instead.

2. Injection must happen on the first turn only. Returning context on every turn
   re-sends the whole bootstrap each time.

Stdlib only, no pytest, matching the repo's zero-dependency stance.
"""
import importlib.util
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
# Identity from package.json, never a literal — scripts/identity.sh rename
# rewrites the name inside the plugin, and a hardcoded copy here would fail for
# every fork on its first day.
NAME = json.loads((REPO_ROOT / "package.json").read_text())["name"]
PLUGIN = REPO_ROOT / ".hermes-plugin" / "__init__.py"

failures = []


def check(name, fn):
    try:
        fn()
        print(f"  ok  {name}")
    except AssertionError as e:
        failures.append(name)
        print(f"FAIL: {name}\n      {e}", file=sys.stderr)


def load_plugin():
    spec = importlib.util.spec_from_file_location("ob_skills_hermes_plugin", PLUGIN)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class FakeCtx:
    """Stands in for Hermes' plugin context, enforcing its real contract."""

    def __init__(self):
        self.skills = {}
        self.hooks = {}

    def register_skill(self, name, path):
        assert isinstance(path, Path), (
            f"register_skill got {type(path).__name__} for {name!r}; Hermes requires "
            "pathlib.Path and silently disables the plugin otherwise"
        )
        assert path.is_file(), f"registered path does not exist: {path}"
        self.skills[name] = path

    def register_hook(self, name, fn):
        self.hooks[name] = fn


print("test-hermes-plugin: registration + pre_llm_call injection")

mod = load_plugin()
ctx = FakeCtx()
mod.register(ctx)


def skills_dir_resolves():
    d = Path(mod._skills_dir())
    assert d.is_dir(), f"not a directory: {d}"
    assert (d / "using-skills" / "SKILL.md").is_file(), "bootstrap skill not found"


def registers_every_skill():
    on_disk = {p.parent.name for p in (REPO_ROOT / "skills").glob("*/SKILL.md")}
    assert set(ctx.skills) == on_disk, f"registered {set(ctx.skills)}, expected {on_disk}"
    assert on_disk, "no skills found on disk — the test would pass vacuously"


def registers_pre_llm_call():
    assert "pre_llm_call" in ctx.hooks, f"hooks registered: {list(ctx.hooks)}"


def injects_on_first_turn():
    out = ctx.hooks["pre_llm_call"](is_first_turn=True)
    assert isinstance(out, dict), f"expected a dict, got {type(out).__name__}"
    assert "context" in out, f"expected a 'context' key, got {list(out)}"
    assert mod.BOOTSTRAP_MARKER in out["context"], "bootstrap marker missing"


def skips_later_turns():
    assert ctx.hooks["pre_llm_call"](is_first_turn=False) is None
    assert ctx.hooks["pre_llm_call"](is_first_turn=None) is None


def tolerates_unknown_kwargs():
    # Hermes may pass arguments this plugin does not know about; the signature
    # takes **kwargs so a harness update does not crash the hook.
    out = ctx.hooks["pre_llm_call"](is_first_turn=True, some_future_arg="x")
    assert out is not None


def bootstrap_is_substantive():
    text = ctx.hooks["pre_llm_call"](is_first_turn=True)["context"]
    assert text.startswith("<EXTREMELY_IMPORTANT>"), "missing opening marker"
    assert text.rstrip().endswith("</EXTREMELY_IMPORTANT>"), "missing closing marker"
    assert f"You have {NAME}." in text, "collection name missing"
    assert "skill_view" in text, "Hermes skill-loading instructions missing"
    assert "delegate_task" in text, "Hermes tool mapping missing"
    assert "description: Use when starting any conversation" not in text, (
        "frontmatter leaked into the bootstrap"
    )


def missing_skills_tree_raises():
    # A bootstrap that silently skips is how a broken install masquerades as a
    # working one, so _skills_dir must raise rather than return a bad path.
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        stub = Path(tmp) / "__init__.py"
        stub.write_text(PLUGIN.read_text())
        spec = importlib.util.spec_from_file_location("ob_skills_hermes_broken", stub)
        broken = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(broken)
        try:
            broken._skills_dir()
        except RuntimeError as e:
            assert "cannot find the skills/ tree" in str(e)
            return
        raise AssertionError("_skills_dir did not raise with no skills/ tree present")


check("skills dir resolves", skills_dir_resolves)
check("registers every skill on disk, as pathlib.Path", registers_every_skill)
check("registers the pre_llm_call hook", registers_pre_llm_call)
check("injects on the first turn", injects_on_first_turn)
check("returns None on later turns", skips_later_turns)
check("tolerates unknown kwargs from the harness", tolerates_unknown_kwargs)
check("bootstrap is well-formed and frontmatter-free", bootstrap_is_substantive)
check("raises loudly when the skills tree is missing", missing_skills_tree_raises)

if failures:
    print(f"FAILED: {len(failures)} check(s)", file=sys.stderr)
    sys.exit(1)
print("PASS: test-hermes-plugin")
