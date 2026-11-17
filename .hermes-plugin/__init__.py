"""skills plugin for Hermes Agent.

Registers every skill with Hermes' native loader, then injects the using-skills
bootstrap on the first turn so the agent knows the collection exists.
"""

import os
import re
from pathlib import Path

BOOTSTRAP_MARKER = "skills:using-skills bootstrap for hermes"


def _skills_dir() -> str:
    """Locate the skills/ tree for either supported install layout.

    - git-clone install (`hermes plugins install openbridge/skills`):
      the plugin dir is the repo root, so `.hermes-plugin/` and `skills/` are
      siblings and this resolves `../skills`.
    - flattened install (plugin files copied to the plugin dir root): `skills/`
      sits next to this module.

    Raises loudly when neither matches. A bootstrap that silently skips is how a
    broken install masquerades as a working one.
    """
    here = os.path.dirname(os.path.realpath(__file__))
    candidates = (
        os.path.realpath(os.path.join(here, "..", "skills")),
        os.path.realpath(os.path.join(here, "skills")),
    )
    for cand in candidates:
        if os.path.isfile(os.path.join(cand, "using-skills", "SKILL.md")):
            return cand
    raise RuntimeError(
        "skills plugin: cannot find the skills/ tree "
        f"(looked at {candidates}). Reinstall with "
        "`hermes plugins install openbridge/skills`."
    )


def _strip_frontmatter(content: str) -> str:
    match = re.match(r"^---\n[\s\S]*?\n---\n([\s\S]*)$", content)
    return (match.group(1) if match else content).strip()


def _build_bootstrap(skills_dir: str) -> str:
    with open(
        os.path.join(skills_dir, "using-skills", "SKILL.md"), encoding="utf-8"
    ) as f:
        body = _strip_frontmatter(f.read())

    tools_path = os.path.join(
        skills_dir, "using-skills", "references", "hermes-tools.md"
    )
    with open(tools_path, encoding="utf-8") as f:
        tool_mapping = f.read().strip()

    return (
        f"<EXTREMELY_IMPORTANT>\n"
        f"{BOOTSTRAP_MARKER}\n\n"
        f"You have skills.\n\n"
        f"The using-skills content below is already loaded for this Hermes "
        f"session. Follow it now. Do not try to load using-skills again.\n\n"
        f"{body}\n\n"
        f"## Loading skills on Hermes\n\n"
        f"Skills are registered with Hermes' native skill loader: invoke one "
        f'with `skill_view("skills:skill-name")`. If a namespaced lookup '
        f"returns 'not found', read the skill file directly instead:\n"
        f'`read_file("{skills_dir}/skill-name/SKILL.md")`\n\n'
        f"The skills directory is: `{skills_dir}`\n\n"
        f"{tool_mapping}\n"
        f"</EXTREMELY_IMPORTANT>"
    )


def register(ctx):
    skills_dir = _skills_dir()
    bootstrap = _build_bootstrap(skills_dir)

    # Register each skill with Hermes' native loader so skill_view can load them
    # on demand. Standard markdown, no conversion.
    #
    # register_skill requires a pathlib.Path. Passing a str raises
    # AttributeError, and Hermes responds by silently disabling the entire
    # plugin — no skills, no bootstrap, no error the user ever sees.
    for name in sorted(os.listdir(skills_dir)):
        skill_md = os.path.join(skills_dir, name, "SKILL.md")
        if os.path.isfile(skill_md):
            ctx.register_skill(name, Path(skill_md))

    # pre_llm_call returning {"context": ...} is the injection path that works:
    # on_session_start return values are ignored, and ctx.inject_message refuses
    # when called from that hook. The returned context is appended to the first
    # turn's user message.
    def pre_llm_call(
        session_id=None,
        user_message=None,
        conversation_history=None,
        is_first_turn=None,
        model=None,
        platform=None,
        **kwargs,
    ):
        if is_first_turn:
            return {"context": bootstrap}
        return None

    ctx.register_hook("pre_llm_call", pre_llm_call)
