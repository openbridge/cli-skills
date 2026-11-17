---
name: backfilling-openbridge-history
description: "Use when asked to backfill, re-run, reprocess or fetch historical data for an Openbridge subscription, or to stop a backfill already running, before calling history trigger - the date flags are counter-intuitive and the subscription must already have a job"
license: MIT
---

# Backfilling Openbridge History

## Overview

`history trigger` queues historical retrieval for a subscription. Two things
reject most first attempts: **`start_date` is the more recent date**, and the
subscription must already have a job. The core principle: **check the limit and
the prerequisites, preview the dates, then trigger once.**

## When to use

- A gap in historical data, or a request to re-pull a past date range.
- A subscription was just created and the user wants data from before today.
- A backfill is running and needs to be stopped.

**Not for:** finding out *why* current data is missing — that is
`diagnosing-openbridge-pipelines`, and a backfill over a broken pipeline just
queues work that will fail the same way.

## Procedure

1. **Confirm the subscription has a job.** The backend creates it within about ten
   seconds of the subscription being created, and `history trigger` has nothing to
   queue without it.

   ```bash
   obcmd job list --subscription_ids 48213 --fields id,status,report_date
   ```

2. **Get the range cap from the product card, and the request cap from
   `history-limit get`.** They answer different questions and the first is the one
   that constrains the dates you can ask for.

   ```bash
   obcmd product-card get --product_id 2     # history_info: how far back, per stage
   obcmd history-limit get                   # how many history requests are permitted
   ```

   `history_info` carries `days` and `max_request_time` per
   (stage, subproduct) — for Facebook Page Insights, 365 and 364. A range beyond
   `days` cannot be served no matter how the flags are written.

   `history-limit get` always returns an **array**, one row per (product,
   subproduct, stage), even for a single row — and it may carry **no row for your
   product at all**, so treat an empty result as "no stated request cap", not as
   an error or as a zero limit. It is not a substitute for `history_info`.

3. **Get the date flags the right way round.** The API converts both dates to days
   back from today and requires start < end in that converted space:

   - `--start_date` is the **more recent** date, nearer today.
   - `--end_date` is the **older** date.

   Reversing them fails with *"do you have start_date and end_date backwards?"*.
   Either `--dates`, or **both** `--start_date` and `--end_date`, must be supplied.

   ```bash
   # January 2026, with the more recent date first
   obcmd history trigger --subscription_id 48213 \
     --start_date 2026-01-31 --end_date 2026-01-01 --dry-run
   ```

4. **Use `--dates` for specific, non-contiguous days.** It takes a JSON array and
   replaces the range flags.

   ```bash
   obcmd history trigger --subscription_id 48213 \
     --dates '["2026-01-05","2026-01-12"]' --dry-run
   ```

5. **Narrow the run only when the user asked for that.** `--product_id` restricts
   it to one product; `--stage_id` restricts it to one pipeline stage and
   **requires `--start_time`**.

   `--start_time` (`YYYY-MM-DD HH:MM:SS`) is **when processing should begin and
   must be in the future** — it schedules the run and has nothing to do with the
   date range being fetched. Resolve stage IDs with:

   ```bash
   obcmd product-payload list --product_id 50 --fields name,stage_id
   ```

6. **Preview, then trigger once.** The response is a HistoryTransaction carrying
   the `job_ids` it queued — record them; they are how you track the run.

   ```bash
   obcmd history trigger --subscription_id 48213 \
     --start_date 2026-01-31 --end_date 2026-01-01
   ```

   **Then read the transaction back and check `start_days` and `end_days`.** That
   is the API stating, in its own terms, how it understood your dates — days back
   from today, where `start_days` is the nearer bound. This is the only proof the
   range was not inverted:

   ```bash
   obcmd history get --transaction_id 104022
   # start_days: 0, end_days: 30  -> today back thirty days, as intended
   ```

   Count the `job_ids` against what you expect: dates × stages. A 31-day window
   over three stages queued 93 jobs.

   A 400 naming historical meta means the product has no historical definition for
   its (product, subproduct, stage) triple — that is a product capability, not a
   fixable argument.

7. **Watch the run, knowing what each command returns.** The two history reads
   have different shapes, and neither is a flat list of dates:

   | Command | Shape |
   |---|---|
   | `history list --subscription_id <id>` | one row per transaction, each carrying a nested `active[]` array of `{job_id, report_date, stage_id, schedule}` |
   | `history get --transaction_id <id>` | one transaction: `start_days`, `end_days`, `schedule_offset`, `job_ids` |

   ```bash
   obcmd history list --subscription_id 48213
   obcmd history get --transaction_id 72418
   obcmd job list --subscription_ids 48213 --all | jq -c 'select(.status != "processed")'
   ```

   Queued jobs run on a **staggered schedule**, not immediately — the observed
   offset was fifteen minutes between dates. Nothing reaches the destination for a
   while, so an empty transaction list shortly after triggering means "not yet",
   not "failed".

8. **Stop a run at the right granularity.** Both are destructive and need `--yes`;
   both accept `--status cancelled`, which is the only value.

   | Scope | Command |
   |---|---|
   | one transaction | `obcmd history cancel --transaction_id 72418 --yes` |
   | every transaction on the subscription | `obcmd history delete --subscription_id 48213 --yes` |

   `history delete` is bulk cancellation, not a record deletion. **Preview it with
   `--dry-run` and show the user the scope before confirming** — it cancels work
   nobody else asked you to touch. The response reports how many jobs were updated.

## Rationalizations

| Thought | Reality |
|---|---|
| "`start_date` is the beginning of the range" | It is the **more recent** date. The API thinks in days back from today. |
| "I will pass a range and a dates array to be thorough" | `--dates` replaces the range. Pick one. |
| "`--start_time` is the start of the period to fetch" | It is when processing should begin, and it must be in the future. |
| "The subscription exists, so I can backfill" | It needs a job, which appears about ten seconds after creation. |
| "Data is missing, so backfill it" | If the pipeline is failing, the backfill fails too. Diagnose first. |
| "`history delete` removes history records" | It cancels every transaction on the subscription. Preview the scope. |
| "`history-limit get` returned an array, something is odd" | One row per (product, subproduct, stage). The array is the declared shape. |
| "`history-limit get` returned nothing for my product, so backfill is blocked" | It states a request cap and may have no row for your product. The range cap is `history_info` on the product card. |
| "The trigger succeeded, so the range was right" | Read `start_days` and `end_days` back. A silently inverted range is the failure this confirms against. |
| "No transactions yet, so the backfill failed" | Jobs are staggered over hours. Compare transactions against queued `job_ids` before concluding anything. |
| "The trigger returned 400, I will adjust the dates again" | If it names historical meta, the product cannot be backfilled at that triple at all. |
