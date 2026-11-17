---
name: provisioning-openbridge-destinations
description: "Use when creating an Openbridge storage destination (Redshift, BigQuery, Snowflake, S3 and the rest), polling a destination_create operation that is still running, or finding the storage_group_id a subscription needs - before calling destination create or storage list"
license: MIT
---

# Provisioning Openbridge Destinations

## Overview

A destination is where pipeline data lands. Creating one is **asynchronous**: the
create call returns a `co_id` for an operation still in flight, and the HTTP
status of the poll — not a field in the body — tells you whether it finished. The
core principle: **create once, then poll the `co_id` until it stops returning
202.**

## When to use

- A subscription needs a destination that does not exist yet.
- A `destination create` was issued and its outcome is unknown.
- You need the `storage_group_id` for an existing destination.

**Not for:** attaching an existing destination to a pipeline — that is
`creating-openbridge-subscriptions`. Not for diagnosing data that reached a
destination and looks wrong (`diagnosing-openbridge-pipelines`).

## Procedure

1. **List what already exists before creating anything.** Destinations are often
   already provisioned, and a duplicate is work to unpick.

   ```bash
   obcmd storage list --fields id,name,status,storage_group_id
   ```

   `--status` defaults to `active` server-side; pass it explicitly to see others.
   **Subscriptions want the `storage_group_id` field, not the row `id`** — both are
   integers, so the wrong one fails late or silently.

2. **Know which path you are on.** `obcmd storage list` is read-only: existing
   destinations are managed in the Openbridge UI, not through this API. The one
   write available is `destination create`.

3. **Preview the create.** `storage_parameters` is the connection object and its
   contents are provider-specific.

   ```bash
   obcmd destination create --name "My Redshift Destination" \
     --storage_parameters '{"storage":"redshift","remote_identity_id":0}' \
     --dry-run
   ```

   The destination's own credentials are a remote identity: resolve or authorize
   one first (`inspecting-remote-identities`, `authorizing-remote-identities`) and
   reference it inside `storage_parameters`. Never put a password or key in argv.

4. **Create once, and keep the `co_id`.** The call returns 202 with a `co_id` — an
   operation ID, not a destination ID.

   ```bash
   obcmd destination create --name "My Redshift Destination" \
     --storage_parameters '{"storage":"redshift","remote_identity_id":90210}'
   ```

5. **Poll that `co_id` until it resolves.** The HTTP status carries the outcome:

   ```bash
   obcmd destination get --co_id 55120
   ```

   | Status | Meaning | Next move |
   |---|---|---|
   | 202 | still processing | wait and poll again |
   | 200 | ready — returns the created subscription | continue |
   | 400 | validation failed | read the error body; fix the parameters and create again |

   Leave a few seconds between polls. Provisioning touches a real warehouse, and
   the poll shares the 1,000-request / 5-minute budget with everything else.

6. **If the create's own response was lost, do not re-create.** `outcome_unknown`
   means the write may already have been applied; a second create can provision a
   second warehouse destination. Read current state instead:

   ```bash
   obcmd storage list --fields id,name,status,storage_group_id
   ```

7. **Confirm before building on it.** A destination is usable once it appears in
   `storage list` with the expected status, and its `storage_group_id` is what the
   subscription takes.

## Rationalizations

| Thought | Reality |
|---|---|
| "`destination create` returned, so the destination exists" | It returned 202 and a `co_id`. Nothing exists until the poll returns 200. |
| "The `co_id` is the destination ID" | It identifies the provisioning operation. The destination appears in `storage list` afterwards. |
| "202 looks like a failure, I will create it again" | 202 is "still working". Re-creating provisions a second destination. |
| "I will poll in a tight loop until it is ready" | Polling shares one rate limit with every other call. Space the polls out. |
| "`storage list --fields id` gives me what the subscription needs" | It needs `storage_group_id`. The row `id` is a different number. |
| "I will edit the destination through the API" | Only create and poll exist here. Everything else is the UI. |
| "The create timed out, so it did not happen" | `outcome_unknown` means it may have. List before resending. |
