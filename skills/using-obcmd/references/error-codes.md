# obcmd error codes

The JSON on stderr carries a stable snake_case `error`. Branch on that and on the
exit code; `message` text is not a contract.

```json
{
  "error": "missing_required_flags",
  "message": "Missing required flag: --subscription_id",
  "field": null,
  "errors": [],
  "suggestions": ["obcmd subscription get --subscription_id <value>"],
  "failing_input": { "missing_flags": ["subscription_id"] },
  "retryable": false,
  "retry_after_seconds": null,
  "http_status": null
}
```

`errors` lists every field-level failure as `{ field, pointer, code, message }`.
`field` names the single rejected attribute, or is `null` when the API named none
or several. `suggestions` is ordered and runnable — try the entries in order.

## Authentication

| `error` | Exit | Cause | Fix |
|---|---|---|---|
| `not_authenticated` | 4 | no refresh token configured | export `OBCMD_REFRESH_TOKEN`, then `obcmd auth login` |
| `auth_no_token` | 1 | auth API returned no token | the refresh token was revoked; a human must issue a new one |
| `http_401` | 4 | access token rejected | `obcmd auth logout`, then log in again |
| `http_403` | 4 | valid token, wrong account | confirm `obcmd account get` matches the `--account_id` passed |

## Usage — all exit 2, none retryable

| `error` | Fix |
|---|---|
| `missing_required_flags` | the message names them; `--help --json` lists all |
| `unknown_flags` | typo, or the flag belongs to a different command |
| `unknown_resource` / `unknown_verb` | `obcmd describe --json` lists everything |
| `invalid_identifier` | a URL or path was passed where a bare ID belongs |
| `invalid_integer` / `invalid_date` / `invalid_enum` | wrong format; the message states the expected one |
| `invalid_filter` | `--filter` must be `key=value` |
| `invalid_payload_json` | `--payload` is not valid JSON |
| `invalid_boolean` | `--yes` takes no value, or exactly `true`/`false`; `--yes=no` is rejected rather than read as consent |
| `confirmation_required` | destructive command; preview with `--dry-run`, then add `--yes` |
| `credential_in_argv` | there is no credential flag; export `OBCMD_REFRESH_TOKEN` |
| `unexpected_collection` | a `get` declared `object` matched more than one record; narrow the query rather than taking the first |

## API and network

| `error` | Exit | Meaning and next move |
|---|---|---|
| `http_400` | 2 | the API rejected the body; `failing_input` shows what was sent |
| `http_404` | 3 | no such record, or not visible to this account |
| `http_409` | 5 | already exists; read current state before retrying |
| `http_429` | 1 | rate limited; already retried, `retry_after_seconds` says how long to wait |
| `request_timeout` | 1 | raise it: `OBCMD_TIMEOUT_MS=60000` |
| `network_error` | 1 | connectivity; `retryable` is true |
| `retries_exhausted` | 1 | budget spent; raise with `OBCMD_MAX_RETRIES=10` |
| `outcome_unknown` | 1 | a write did not complete and was **not** replayed; it may already have been applied — read current state before resending |
| `unsafe_pagination_link` | 1 | the API returned a `next` link outside its own origin; it was not followed. Page manually with `--page` |
| `pagination_cycle` | 1 | `--all` was handed a `next` link pointing at a page already fetched; refused rather than looping |

Never retry a `4xx` other than `429`. Retrying a `400`, `403` or `404` cannot
resolve it.

## Debugging

```bash
OBCMD_DEBUG=1 obcmd <command>       # stack traces to stderr
obcmd <command> --dry-run --json    # exact URL and body, nothing sent
obcmd auth status                   # what credentials are in play
obcmd config get                    # resolved configuration
```
