---
name: updating-openbridge-subscriptions
description: "Use when changing, pausing, repointing, renaming or cancelling an Openbridge subscription that already exists - the request names it, by ID or by a name you can look up - or when reading back which product parameters are stored, before calling subscription update or subscription cancel; a request to add or set up a pipeline that does not exist yet is a create, so hand that to creating-openbridge-subscriptions instead"
license: MIT
---

# Updating Openbridge Subscriptions

## Overview

`subscription update` is a partial update and `product_parameters` **merges**
rather than replaces. There is no delete: cancellation is the terminal state, and
two status values turn an ordinary update into a destructive one. The core
principle: **read what is stored, send only what changes, and know which status
values retire the record.**

## When to use

- Pausing or resuming a pipeline, renaming it, or repointing it at a different
  identity or destination.
- Changing stages or other product parameters.
- Cancelling a subscription, or confirming what a previous update actually stored.

**Not for:** creating one (`creating-openbridge-subscriptions`), or re-running
history after a change (`backfilling-openbridge-history`).

**"Add" only lands here when the target already exists.** "Add the search-terms
table to 48213" names a subscription, so it is an update. "Add Amazon
Attribution for the UK" names none, so it is a create — and asking the user to
choose between create and edit wastes a turn on a question their sentence
already answered. Check for a subscription ID or a name you can resolve; if
there is neither, this is not the skill.

## Procedure

1. **Read the current state first.** An update you compose without reading is an
   update that silently drops a parameter.

   ```bash
   obcmd subscription get --subscription_id 48213
   obcmd subscription-parameter list --subscription_id 48213
   ```

   `subscription-parameter list` returns **one aggregate resource** whose `id` is
   the subscription ID, not a list of rows. For several subscriptions at once:

   ```bash
   obcmd subscription-parameter get --subscription_ids 48213,48214,48215
   ```

   That bulk read takes 1 to 100 IDs and is **all-or-nothing**: one missing or
   inaccessible ID returns 404 for the whole request, with every unresolved ID
   listed in the error detail. It always returns an array, one row per requested
   ID, including for a single ID.

2. **Send only the attributes that change.** Omitted attributes keep their stored
   value.

   ```bash
   obcmd subscription update --subscription_id 48213 --name "Brand X - EU" --dry-run
   ```

3. **Treat `product_parameters` as a merge.** Omitted keys keep their stored
   value, and **an empty object clears nothing**. There is no replace-all
   operation and no null-to-delete.

   ```bash
   obcmd subscription update --subscription_id 48213 \
     --product_parameters '{"stage_ids":"[1000,1001]"}' --dry-run
   obcmd subscription-parameter list --subscription_id 48213   # confirm what landed
   ```

   `stage_ids` stays a **string** containing a JSON array on update, exactly as on
   create. The legacy `subscription_product_meta_attributes` attribute is
   rejected.

4. **Know which status values are destructive.** `--status` accepts `active`,
   `paused`, `cancelled` and `invalid`. The last two retire the record and
   require `--yes`; `describe --json` reports this as `destructive_when` on the
   command rather than as a destructive command.

   | Intent | Command |
   |---|---|
   | stop processing, keep the record usable | `--status paused` |
   | resume | `--status active` |
   | retire permanently | `obcmd subscription cancel --subscription_id <id>` |

   Pause is the reversible option. Reach for it whenever the user says "stop" and
   has not said "delete".

5. **Cancel deliberately — there is no delete and no undo.** The API exposes no
   subscription delete; `cancelled` is terminal.

   ```bash
   obcmd subscription cancel --subscription_id 48213 --dry-run
   obcmd subscription cancel --subscription_id 48213 --yes
   ```

   Preview first, show the user what will be cancelled, and confirm the intent is
   permanent retirement rather than a pause.

6. **Repointing identity or destination uses the same two traps as create.**
   `--storage_group` takes the `storage_group_id` field from `obcmd storage list`,
   not the row `id`; set the identity with `--remote_identity` and nowhere else.

   ```bash
   obcmd storage list --fields id,name,storage_group_id
   obcmd subscription update --subscription_id 48213 --storage_group 7788 --dry-run
   ```

7. **Reactivating fails when the product has gone inactive.** Check before
   blaming the update:

   ```bash
   obcmd product get --product_id 50 --fields id,name,active
   ```

8. **Avoid `subscription-parameter create`.** It writes a single parameter row and
   is rarely the right call; a duplicate key returns 409. Prefer
   `--product_parameters` on update.

## Rationalizations

| Thought | Reality |
|---|---|
| "They said *add*, so I should ask whether this is a new pipeline or an edit" | Look for a target first. Named subscription means update; no target means create, and the question was already answered. |
| "I will send the full parameter set to be safe" | Merge semantics mean you only need the changed keys — and a stale full set overwrites newer values. |
| "An empty `product_parameters` clears them" | It clears nothing. There is no delete-by-null and no replace-all. |
| "The user said stop, so cancel it" | `paused` is reversible, `cancelled` is terminal with no delete to undo it. Ask which they mean. |
| "`subscription update` is not a destructive command" | It is, for `--status cancelled` and `--status invalid`. Read `destructive_when`. |
| "The update returned 200, so the parameters are right" | Read them back with `subscription-parameter list`. Merge outcomes are not visible in the update response. |
| "I will bulk-read parameters for the twenty subscriptions I care about" | One inaccessible ID fails the whole request with 404. Read in smaller batches, or handle the all-or-nothing result. |
| "Reactivation failed, so the subscription is broken" | The product may have gone inactive since. Check `product get`. |
