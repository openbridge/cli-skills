# Querying transactions

`transaction list` is the most detailed view of what processing did, and the most
easily misread. `--subscription_id` is required on **every** call, including
cursor pages and tree queries; without it the Service API returns 403.

```bash
obcmd transaction list --subscription_id 48213 --limit 200 \
  --fields id,sender,status,attribution_date,payload_name,error_code,error_message,modified_at
```

## What the records mean

- Retention is **three days**.
- Retries reuse the same transaction ID and updates are **merged**. A record is
  the current merged state, not an attempt history.
- Default fields are `id, sender, status, attribution_date, payload_name,
  modified_at`.

## Status values

`UNPROCESSED` · `PROCESSING` · `IN_PROGRESS` · `RETRY` · `ERROR` · `PROCESSED` ·
`SUCCESS` · `NO_DATA` · `IGNORED`

**Only `PROCESSED` from `sender: zeroadmin` confirms a load into the
destination.** `SUCCESS` and `PROCESSED` from other senders describe an earlier
stage completing.

`NO_DATA` is not a failure: the upstream platform returned nothing for that date.

## Senders

`scheduler` · `supervisor` · `ftpsync` · `zeroadmin`

Read `--sender` alongside `--status`; the same status means different things at
different stages.

## Filters

All exact-match and AND-combined. There is no substring form and no multi-value
form.

| Flag | Notes |
|---|---|
| `--attribution_date` | the **data** date requested upstream, not processing time. `2026-01-01` does not match a value carrying a time such as `2026-09-09T19:00` |
| `--timestamp_from` / `--timestamp_to` | inclusive bounds on processing time, Unix seconds. **Prefer these** for time ranges |
| `--modified_at_from` / `--modified_at_to` | compared **lexicographically** against stored text, so the format must match exactly |
| `--job_id` | exact. Many records store an empty `job_id` and will not match any value |
| `--payload_name`, `--product_name`, `--subscription_name` | exact |
| `--error_code`, `--error_message` | exact; `--error_message` has no substring match |
| `--file_path`, `--parent`, `--time_to_live` | exact |
| `--status`, `--sender` | enums, listed above |

## Pagination

Cursor-based, not page-based. `--limit` is 1–200, default 50, and counts records
*evaluated* per page.

```bash
obcmd transaction list --subscription_id 48213 --limit 200                     # first page
obcmd transaction list --subscription_id 48213 --limit 200 --cursor <token>    # next
obcmd transaction list --subscription_id 48213 --all                           # every page as NDJSON
```

The token comes from `meta.next_cursor` and is reported on stderr. **Keep every
other filter unchanged across cursor pages.** A short page, or an empty one, can
still have a next page — stop when no cursor comes back.

## Tree expansion

```bash
obcmd transaction list --subscription_id 48213 --tree --tree_depth 2
```

`--tree` expands child references into merged root-to-descendant records, one per
branch. Filters and the cursor apply **before** expansion, and `--limit` does not
cap the expanded count — a limit of 50 can return far more rows. `--tree_depth`
is 1–4, default 4, and is only valid with `--tree`.

## Useful queries

```bash
# what is failing right now
obcmd transaction list --subscription_id 48213 --status ERROR \
  --fields id,sender,error_code,error_message,attribution_date

# did one date actually land in the destination
obcmd transaction list --subscription_id 48213 --attribution_date 2026-10-01 \
  --sender zeroadmin --fields id,status,payload_name,modified_at

# everything processed in a window, newest-first by processing time
obcmd transaction list --subscription_id 48213 \
  --timestamp_from 1759276800 --timestamp_to 1759363200 --all
```
