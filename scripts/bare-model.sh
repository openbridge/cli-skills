#!/usr/bin/env bash
# A bare single-completion model call, for SKILLS_EVAL_CMD.
#
#   SKILLS_EVAL_CMD=scripts/bare-model.sh scripts/eval.sh --run
#
# evals/README.md explains why the eval runner must not talk to an agent
# harness: a full agent carries its *own* installed skills and answers from
# those instead of the catalog on stdin, so the run measures the host machine
# rather than this collection. On a machine where skills is installed, that
# contamination is guaranteed.
#
# `claude --bare` is the documented minimal mode, but it reads neither OAuth nor
# the keychain — API key only. With no ANTHROPIC_API_KEY, these three flags get
# the same isolation out of a logged-in CLI:
#
#   --disable-slash-commands   removes the installed skills from the prompt, so
#                              the only catalog the model sees is the one the
#                              eval handed it
#   --settings <disableAllHooks>  stops SessionStart hooks injecting a bootstrap
#                              or rewriting the answer on its way out
#   --strict-mcp-config        no MCP servers, no project config
#   --allowed-tools ''         no tool calls; one completion, one answer
#
# Check a run for contamination the same way the runner does: an answer naming a
# skill outside the catalog, or carrying a plugin prefix like `skills:`, means
# the isolation failed and the numbers describe the host.
#
# Override the model with SKILLS_EVAL_MODEL. Anything that takes a prompt on
# stdin and prints one answer on stdout works here — this file is the version
# that needs no API key.
set -uo pipefail

SETTINGS="$(mktemp -t skills-eval-settings)"
trap 'rm -f "$SETTINGS"' EXIT
printf '{"disableAllHooks":true}' > "$SETTINGS"

ARGS=(-p --disable-slash-commands --strict-mcp-config --allowed-tools '' --settings "$SETTINGS")
[ -n "${SKILLS_EVAL_MODEL:-}" ] && ARGS+=(--model "$SKILLS_EVAL_MODEL")

exec claude "${ARGS[@]}"
