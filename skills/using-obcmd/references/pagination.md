# Paginating obcmd output

Two styles exist and they are not interchangeable. `pagination_style` in
`describe --json` says which one a command uses: `page` or `cursor`. A command
with `paginated: false` returns everything in one response.

## Every page, the simple way

```bash
obcmd subscription list --status active --all
```

`--all` works on list commands only, auto-paginates, and streams NDJSON — one
JSON object per line, not a JSON array. Consume it line by line:

```bash
obcmd job list --subscription_ids 48213 --all | jq -c 'select(.status != "processed")'
```

## Always check a sweep for duplicates

**A page-based `--all` sweep can return the same record more than once.** Pages
are server-side offsets, so without a stable sort the set can shift between
requests and page two re-serves rows from page one. Observed live:
`remote-identity-shared list --all` returned 59 rows containing 44 distinct IDs.

Count rows against distinct IDs every time, before using the result:

```bash
obcmd remote-identity-shared list --all --fields id > rows.ndjson
wc -l rows.ndjson                                   # rows streamed
jq -r .id rows.ndjson | sort -u | wc -l             # distinct records
```

Two fixes, in order of preference:

1. **Sort, where the command allows it.** `--ordering id` on
   `remote-identity-shared list` made the same sweep return 59 distinct rows.
   The flag's name varies — `--ordering` here, `--order_by` on `healthcheck list`
   and `job list`. Check `--help --json`. For a descending sort, attach the value
   with `=`: `--ordering=-id`, not `--ordering -id`.
2. **Deduplicate by `id`.** Several list commands — `subscription list` among them
   — expose **no sort flag at all**, so this is the only option there:

   ```bash
   obcmd subscription list --status active --all | jq -s 'unique_by(.id)'
   ```

Never report a count straight from `wc -l` on a sweep you have not deduplicated.

## Page-based commands

Most lists. Take pages yourself with `--page` and `--page_size` when you want a
bounded read instead of the whole set.

```bash
obcmd healthcheck list --account_id 1234 --page 1 --page_size 50
```

## Cursor-based commands

`transaction list` is cursor-based. The cursor token for the next page is
reported on stderr; pass it back with `--cursor`.

```bash
obcmd transaction list --subscription_id 48213 --limit 100
obcmd transaction list --subscription_id 48213 --limit 100 --cursor <token>
```

**A short page, or even an empty one, can still have a next page.** Stop when no
cursor comes back — never when a page looks thin.

## Two deliberate refusals

| `error` | What happened | What to do |
|---|---|---|
| `unsafe_pagination_link` | the API returned a `next` link outside its own origin; it was not followed | page manually with `--page` |
| `pagination_cycle` | `--all` was handed a `next` link pointing at a page already fetched | the server is looping; page manually and report the range you covered |

Both exit 1. Neither is fixed by retrying.

## Narrowing instead of paging

Often the cheaper answer. `--fields` trims the response, server-side filters trim
the result set, and `--filter key=value` passes an API-native lookup straight
through — including Django suffixes on the APIs that accept them
(`__gte`, `__lte`, `__contains`, `__icontains`, `__exact`).

```bash
obcmd healthcheck list --account_id 1234 --status ERROR \
  --filter modified_at__gte=2026-01-01 --fields id,subscription_id,err_msg
```

Unknown *flags* are rejected, but `--filter` values are passed verbatim. A filter
the API does not recognize is dropped server-side with no error — if a filter
seems ignored, check the spelling of the lookup suffix before concluding the data
is wrong.
