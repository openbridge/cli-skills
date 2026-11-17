---
name: using-obcmd
description: "Use when running any obcmd command or working against the Openbridge APIs (subscriptions, jobs, healthchecks, remote identities, history, destinations), before the first invocation - covers discovery, exit-code branching, dry-run and output guarantees"
license: MIT
---

# Using Obcmd

## Overview

`obcmd` is the Openbridge CLI. It is self-describing: one call returns every
resource, verb, flag and type, so there is never a reason to guess a command or
discover the surface by trial. The single principle: **ask the tool what exists,
then branch on exit codes rather than on prose.**

## When to use

- Any task that will run `obcmd`, before the first invocation.
- A command failed and the next move depends on *why* — the exit code answers that.
- You are about to parse obcmd output, or write a script around it.

**Not for:** a specific workflow that has its own skill. Creating a subscription,
backfilling history, diagnosing a stalled pipeline, authorizing an identity and
provisioning a destination each have one. Load this skill for the mechanics and
that skill for the sequence.

## Procedure

1. **Discover the surface in one call.** Do not walk the tree node by node.

   ```bash
   obcmd describe --json > obcmd-tree.json
   ```

   For a single command, including every flag and its required status:

   ```bash
   obcmd <resource> <verb> --help --json
   ```

   `obcmd <resource> describe` lists that resource's commands and never calls the
   API. `describe` is not a verb — it is introspection.

2. **Compose from the grammar** rather than searching for a command name.

   ```
   obcmd <resource> <verb> [flags]
   ```

   Noun first. The verb set is closed and means the same thing everywhere:
   `list get create update delete cancel trigger validate`.

   **Attach any value that starts with `-` using `=`, not a space.** The parser
   reads a space-separated `-value` as another flag, so
   `--order_by -modified_at` exits 2 with `unknown_flags: --modified_at` while
   `--order_by=-modified_at` works. This bites descending sorts above all —
   `--ordering`, `--order_by` — and any negative number or value with a leading
   dash.

3. **Preview every mutating command with `--dry-run` first.** It prints the exact
   URL and body, sends nothing, and needs no credentials. Show the user that
   output before dropping the flag.

   Destructive commands additionally require `--yes`; without it they fail with
   `confirmation_required` and exit 2. The CLI never prompts, so a missing `--yes`
   is an error to correct, not a question to answer.

4. **Read `destructive_when`, not only `destructive`.** A command can be
   destructive for particular flag values — `subscription update --status cancelled`
   retires the record. Both `describe --json` and `--help --json` report it.

5. **Branch on the exit code.** Never on message text; `message` changes between
   versions, the code does not.

   | Code | Meaning | Next move |
   |---|---|---|
   | 0 | success | continue |
   | 1 | failure (API, network, internal) | check `retryable` in the error body |
   | 2 | usage error | fix the flags; retrying unchanged cannot help |
   | 3 | not found | the record is absent or invisible to this account |
   | 4 | not authenticated or permission denied | terminal; re-authenticate, do not retry |
   | 5 | conflict | read current state, then decide |

6. **Take errors from stderr as JSON.** stdout carries data only. On failure, read
   the stable snake_case `error` code, then run the entries in `suggestions` in
   order — they are real commands. Full code table:
   [references/error-codes.md](references/error-codes.md).

7. **Narrow reads with `--fields`, and page with `--all`.** `--fields` accepts dot
   notation and `*`. `--all` streams every page as NDJSON, one object per line, on
   list commands only. Pagination differs per command — page-based for most,
   cursor-based for `transaction list`.

   **Count rows against distinct `id`s after any `--all` sweep.** Page-based
   pagination can re-serve rows across pages when no sort is applied; sort with
   the command's own ordering flag where one exists, and deduplicate by `id`
   where none does. See [references/pagination.md](references/pagination.md).

8. **Rely on the output guarantees instead of defensive parsing.** Optional fields
   are present as `null`; empty collections are `[]`; the top-level type comes from
   `response_shape` in `describe --json` and never varies with how many records
   matched. Responses never omit a field. The full set, including the three `get`
   commands that return arrays, is in
   [references/output-guarantees.md](references/output-guarantees.md).

9. **Serialize when issuing many commands.** The limit is 1,000 requests per five
   minutes per IP across all Openbridge APIs. `obcmd` already backs off on `429`;
   firing commands concurrently just spends the budget faster.

## Rationalizations

| Thought | Reality |
|---|---|
| "I know the flag is called `--id`" | Flag names vary per command. `--help --json` costs one call and is authoritative. |
| "The table output is easy enough to grep" | Human tables are for humans and are not a contract. Pass `--json`; piped output is already JSON. |
| "Exit 1 means transient, so retry" | 1 is the generic failure code. `retryable` is an explicit field — read it. |
| "The error says not found, I will create it" | Exit 3 can also mean not visible to this account. Confirm the account first. |
| "`--dry-run` is an extra step on a simple create" | It is the only step that is free. A wrong body costs a real record. |
| "The write timed out, I will send it again" | `outcome_unknown` means the server may already have applied it. Read current state first; resending blind is how a duplicate subscription appears. |
| "`--all` finished, so I have every record once" | Page-based sweeps can repeat rows without a stable sort. Compare the row count to the distinct `id` count. |
| "One record matched, so I will index the object" | Shape is per-command, not per-result-count. `list` is always an array; read `response_shape`. |

## Supporting files

- [references/error-codes.md](references/error-codes.md) — every `error` code, its
  exit code, and the fix.
- [references/pagination.md](references/pagination.md) — page vs cursor styles,
  `--all`, and the two refusals that protect it.
- [references/output-guarantees.md](references/output-guarantees.md) — the response
  contract, including where a `get` returns an array.
