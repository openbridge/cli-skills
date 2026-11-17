---
name: diagnosing-openbridge-pipelines
description: "Use when an Openbridge subscription stops producing data, data arrives late or incomplete, a job or healthcheck reports an error, a job, transaction or healthcheck call returns 403 for one subscription while other obcmd commands work, or the user asks why a pipeline is broken - before changing any configuration or re-running history"
license: MIT
---

# Diagnosing Openbridge Pipelines

## Overview

Four layers can break a pipeline and they have different owners: the third-party
credential, the subscription's configuration, the job schedule, and the
processing transactions. The core principle: **work the ladder from credential to
transaction, and change nothing until a layer has actually been ruled out.**

The most common single cause is a revoked third-party credential, which no
amount of reconfiguring will fix.

## When to use

- "Data stopped arriving", "the feed is stale", "rows are missing".
- A healthcheck, job or transaction reports an error status.
- Before re-running history or editing a subscription that was working yesterday.

**Not for:** a command that failed in your own hands with a non-zero exit — read
the error body and `using-obcmd` instead. Not for authenticating yourself
(`authenticating-obcmd`): exit 4 on *your* commands is your token, not the
pipeline's credential.

## Procedure

1. **Check the credential first.** A subscription attached to an invalid identity
   stops processing data, and nothing else you change will restart it.

   ```bash
   obcmd remote-identity-shared list --invalid_identity 1 --fields id,name
   ```

   Any hit here explains the outage. The platform account holder must re-authorize
   through the Openbridge UI — you cannot do it for them. Map the identity back to
   the affected subscriptions:

   ```bash
   obcmd subscription list --remote_identity 90210 --fields id,name,status
   ```

   **An invalid identity with no active subscription attached is not an outage.**
   Run that lookup before reporting one. The same applies in reverse — which
   subscriptions feed a destination, which identity a pipeline uses — and those
   joins are in
   [references/reverse-lookups.md](references/reverse-lookups.md).

2. **Ask the account what is failing.** Healthchecks are the account-wide view.

   ```bash
   obcmd healthcheck list --account_id 1234 --status ERROR --order_by=-modified_at \
     --fields id,subscription_id,subscription_name,status,err_msg
   ```

   Narrow by time with a Django lookup through `--filter`:

   ```bash
   obcmd healthcheck list --account_id 1234 --status ERROR \
     --filter modified_at__gte=2026-10-01 --order_by=-modified_at
   ```

   `--account_id` must match the account in your token; another account's
   healthchecks return 403 and always will.

3. **Confirm the subscription itself is still live and pointed where it should be.**

   ```bash
   obcmd subscription get --subscription_id 48213 --fields id,name,status,product_id,remote_identity_id,storage_group_id
   obcmd subscription-parameter list --subscription_id 48213
   obcmd product get --product_id 50 --fields id,name,active
   ```

   A `cancelled`, `paused` or `invalid` status, or a product that has gone
   inactive, ends the investigation here.

4. **Look at the jobs — with the plural flag.**

   ```bash
   obcmd job list --subscription_ids 48213 --order_by=-modified_at \
     --fields id,status,report_date,stage_id
   ```

   `--subscription_ids` is **required**. Without it the API returns 403 *"No
   subscription IDs provided"* — an argument error reported as a permission error,
   and `--id` or `--ids` do not satisfy it. `--ids` appears to be ignored by the
   API entirely; filter a single job with `--id`. `job get` also needs
   `--subscription_ids` alongside `--job_id`, because the jobs backend authorizes
   by subscription.

5. **Read the transactions to see what processing actually did.**

   ```bash
   obcmd transaction list --subscription_id 48213 --status ERROR \
     --fields id,sender,status,attribution_date,payload_name,error_message,modified_at
   ```

   Four things about this endpoint change how you read the result, and getting any
   of them wrong produces a confident wrong answer:

   - **Only `PROCESSED` from `sender: zeroadmin` confirms a load into the
     destination.** Other senders and statuses describe earlier stages.
   - **Records are retained for three days**, and retries reuse the same
     transaction ID with merged updates. A record is the *current merged state*,
     not an attempt history — `--status ERROR` finds what is failing **now**, not
     everything that ever failed.
   - **Filters are exact-match and AND-combined.** No substring, no multi-value.
     `--error_message` matches the full string only.
   - **Pagination is cursor-based.** `--all` streams everything; otherwise pass the
     `--cursor` token from `meta.next_cursor` and keep every other filter
     unchanged. A short or even empty page can still have a next page.

   **Count what you found against what was queued before concluding anything.**
   No `ERROR` rows means nothing has failed *among the jobs that have run* — and
   after a backfill, most have not. Observed live: 42 transactions against 93
   queued jobs, zero errors, and the run still hours from finished.

   ```bash
   obcmd history get --transaction_id 104022          # how many job_ids were queued
   obcmd transaction list --subscription_id 48213 --all | wc -l
   ```

   A `NO_DATA` row is also not a failure: the upstream platform returned nothing
   for that date and stage.

   The filter surface, the status values and the `--tree` expansion are in
   [references/transaction-queries.md](references/transaction-queries.md).

6. **Check the transformation rules only when the data arrived but looks wrong.**

   ```bash
   obcmd rule list --path_contains "amzadv" --latest --fields path,version
   ```

7. **Report the layer, not a guess.** Say which command produced the evidence, and
   name the owner of the fix: the platform account holder for a revoked
   credential, Openbridge support for a pipeline-side error, the user for a
   paused or misconfigured subscription. Re-run history only after the cause is
   fixed — a backfill over a broken pipeline queues work that fails identically.

## Rationalizations

| Thought | Reality |
|---|---|
| "No data, so I will re-trigger history" | A backfill over a broken pipeline fails the same way and hides the cause. Diagnose first. |
| "The 403 from `job list` means I lack permission" | It usually means `--subscription_ids` was missing. The API reports an argument error as a permission error. |
| "`--status ERROR` returned nothing, so nothing failed" | Transactions are retained three days and records are merged, so that filter shows what is failing *now*. |
| "The transaction says `PROCESSED`, the data landed" | Only `PROCESSED` from `zeroadmin` confirms a destination load. |
| "I will substring-match the error message" | Transaction filters are exact-match. Use `--error_code`, or page and filter locally. |
| "The page came back short, so that is the end" | Cursor pagination can return a short or empty page with a next cursor. Stop when the cursor stops. |
| "No ERROR rows, so the pipeline is healthy" | Only among jobs that have run. Compare the transaction count to the queued `job_ids`. |
| "An invalid identity means someone has an outage" | Not until an active subscription is attached to it. Check first. |
| "The identity exists, so credentials are fine" | Read `invalid_identity`. Existing and valid are different. |
| "I will fix the subscription config while I am here" | Changing configuration mid-diagnosis destroys the evidence and can mask the real cause. |

## Supporting files

- [references/transaction-queries.md](references/transaction-queries.md) — the
  transaction filter surface, status values, senders, and `--tree` expansion.
- [references/reverse-lookups.md](references/reverse-lookups.md) — answering "what
  is attached to this?" for identities, destinations and products.
