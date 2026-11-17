---
name: authenticating-obcmd
description: "Use when an obcmd command exits 4 or reports not_authenticated, http_401 or credential_in_argv, when every command fails the same way, when http_403 means the token belongs to a different account than the one being asked for, when obcmd is being set up for the first time, or before a session that will issue many Openbridge calls - decides whether to re-authenticate, switch account context, or stop and ask a human"
license: MIT
---

# Authenticating Obcmd

## Overview

`obcmd` uses two tokens and the distinction decides your next move: a long-lived
**refresh token** that only a human can create, and a short-lived **access token**
the CLI exchanges and caches for you. The core principle: **exit 4 is terminal.
Re-authenticate or ask the user — never retry.**

## When to use

- A command exited 4, or the error body carries `not_authenticated`, `http_401`
  or `http_403`.
- Setting `obcmd` up in a new shell, container or CI runner.
- The same account and user IDs are about to be typed into many commands.

**Not for:** third-party credentials. `OBCMD_REFRESH_TOKEN` authenticates *you*
to Openbridge; an Amazon or Google authorization that Openbridge holds on your
behalf is a remote identity, and a revoked one presents as a pipeline that
stopped producing data rather than as exit 4. Those are
`authorizing-remote-identities` and `inspecting-remote-identities`.

## Procedure

1. **Establish what is configured before doing anything else.**

   ```bash
   obcmd auth status    # whether a credential is present, and when it expires
   obcmd config get     # resolved configuration, with credential values masked
   ```

2. **Supply the refresh token through the environment, and only there.**

   ```bash
   export OBCMD_REFRESH_TOKEN=<token>
   obcmd auth login     # verifies the token and caches an access token
   ```

   There is no flag for it. Passing `--refresh-token` fails with
   `credential_in_argv` at exit 2 — argv is visible in `ps` output to every user
   on the machine, and lands in shell history and CI logs.

3. **When no token is configured, stop and ask the user for one.** Refresh tokens
   are created by a human in the Openbridge UI under **Account → API Management**
   and cannot be created through the API. You cannot obtain one yourself, so a
   missing token is a question, not a task — say which environment variable to set
   and wait.

4. **Diagnose by error code, not by retrying.**

   | `error` | Exit | What it actually means | Move |
   |---|---|---|---|
   | `not_authenticated` | 4 | no refresh token in the environment | export it, then `obcmd auth login` |
   | `http_401` | 4 | the cached access token was rejected | `obcmd auth logout`, then log in again |
   | `http_403` | 4 | the token is valid but for a different account | compare `obcmd account get` against the `--account_id` passed |
   | `auth_no_token` | 1 | the auth API accepted the call and returned no token | the refresh token was revoked; a human must issue a new one |
   | `credential_in_argv` | 2 | a credential was passed as a flag | export `OBCMD_REFRESH_TOKEN` instead |

5. **Treat `http_403` as a context error, not a permissions wall.** Account-scoped
   endpoints validate against the account in your token — `healthcheck list` for
   another account returns 403 and always will. Confirm whose token you are using
   before concluding the record is restricted.

6. **Save the account and user IDs once** rather than resolving them per command.

   ```bash
   obcmd account get --fields id
   obcmd user get --fields id
   obcmd config update --account_id <account_id> --user_id <user_id>
   ```

   `~/.config/obcmd/config.json` holds those defaults only; it never contains the
   refresh token. Precedence, highest first: command-line flag, environment
   variable, config file, built-in default.

7. **Let the cache do its job.** `auth login` caches an access token in
   `~/.config/obcmd/token.json` and reuses it until 60 seconds before expiry. Do
   not call `obcmd auth token get` in a loop — the Authentication API shares the
   same 1,000-request / 5-minute budget as every other Openbridge API, so a token
   loop can rate-limit the work it was meant to support.

8. **To sign out fully, clear both halves.** `obcmd auth logout` deletes the
   cached access token; the refresh token lives in the environment, so
   `unset OBCMD_REFRESH_TOKEN` as well.

## Rationalizations

| Thought | Reality |
|---|---|
| "Exit 4 might be transient, retry once" | 4 is terminal by definition. Retrying spends rate-limit budget and changes nothing. |
| "I will pass the token as a flag just this once" | There is no such flag, and the attempt is rejected. argv is readable by every user on the box. |
| "No token configured — I will find or mint one" | Only a human can create a refresh token, in the UI. Ask; do not search the filesystem for credentials. |
| "403 means I lack permission" | It usually means the token belongs to a different account than the ID you passed. Check `account get` first. |
| "I will fetch a fresh access token before each call to be safe" | The cache already refreshes before expiry. A token loop burns the shared rate limit. |
| "`auth logout` signs me out" | It clears the access token only. The refresh token is still in the environment. |
| "On CI each job needs its own cached token" | The cache is fingerprint-bound to the refresh token that filled it, so a shared home directory does not leak the previous account's token. |
