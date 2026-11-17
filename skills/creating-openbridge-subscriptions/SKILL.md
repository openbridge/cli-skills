---
name: creating-openbridge-subscriptions
description: "Use when someone wants to add, create, set up, connect, onboard or start pulling data into a new Openbridge subscription, pipeline, feed or source - the words add and new mean create, so never stall to ask whether they meant to edit something - and use it before calling subscription create; it walks the fixed selection order (product, identity, profile, marketplace, tables, destination, name) and takes every option list from the product card rather than from existing pipelines"
license: MIT
---

# Creating Openbridge Subscriptions

## Overview

A subscription is one product, one identity, one destination, plus whatever
selectors and tables that product requires. Every one of those is the user's
choice, and every one has exactly one command that lists the valid options.

The core principle: **the product card is the plan. Read it once, then walk the
selection order, asking at each fork.** Nothing in this flow requires looking at
an existing pipeline, and treating other people's subscriptions as the source of
truth is what turns a six-question setup into an open-ended search.

## "Add" means create

Add, new, set up, connect, hook up, onboard, launch, "start pulling X" — all of
these describe a subscription that does not exist yet. Asking "did you want to
create a new one or edit an existing one?" reads as stalling, because the answer
was already in the sentence.

It is an update only when the request points at a record that already exists: a
subscription ID, a name you can look up, or an explicit "the one we set up last
week". "Add a stage to 48213" edits 48213. "Add Amazon Attribution for the UK"
creates. The first belongs to `updating-openbridge-subscriptions`.

## When to use

- Any request to set up a new pipeline, feed, source or subscription.
- The user named a platform and a destination but no IDs — that is the normal
  starting point, not a blocker.
- A create attempt returned 400 and you are about to retry it.

**Not for:** changing a subscription that already exists
(`updating-openbridge-subscriptions`), backfilling once it is live
(`backfilling-openbridge-history`), or creating the destination itself
(`provisioning-openbridge-destinations`).

## The selection order

| # | What the user chooses | The command that lists the options | Skip the question when |
|---|---|---|---|
| 1 | source product | `product-card list` | the request names a product that resolves to exactly one row |
| 2 | identity — whose credentials | `remote-identity-shared list --remote_identity_type <from card>` | exactly one valid identity of that type exists |
| 3 | platform account or profile | the command for the card's requirement — [references/selectors.md](references/selectors.md) | the card declares no selector |
| 4 | marketplaces or another plural selector | the same command, narrowed to the account picked in 3 | only one exists |
| 5 | tables to land | the card's `stages` | the card has one stage, or the user named them |
| 6 | destination | `storage list` | exactly one active destination |
| 7 | name | you propose, the user may overrule | the user supplied one |

The order is fixed because each list is keyed by the answer above it: the
identity list needs the product's identity type, the profile list needs the
identity, the marketplace set needs the account, and the create body needs all
of them. Running it out of order is what forces a guess.

Skipping a question because only one option exists is good judgment — say which
one you took, so a wrong single option is still correctable.

## Ask adaptively, never choose silently

How much to ask at once depends on how much the request already pinned down:

- **Vague** ("set up Amazon Attribution for us") — one step at a time. Each
  answer narrows the next list, and a wall of menus for choices that depend on
  each other cannot be answered in order anyway.
- **Mostly specified** ("Amazon Attribution, Openbridge Production identity, US
  only, into prod-redshift") — read the card, then put the remaining open
  choices in one message and dry-run as soon as they come back.

What adaptive does not mean: filling a blank in yourself. The identity, the
profile or marketplace, the stage subset and the destination all change what
data lands and who pays for it, so each is presented rather than assumed. The
name is the single exception — propose one, because having a suggestion to
reject is faster than being asked to invent one.

## Do not go fishing

Everything this flow needs comes from `product-card get`, one list command per
choice, and `subscription create --help --json` for encodings. Specifically, do
not:

- browse existing subscriptions to work out the parameter shape — the card gives
  the required keys and `--help --json` gives the encodings
- ask the user for an ID you could list for them
- ask whether they meant create or edit
- enumerate every product when they already named one, or every identity type
  when the card names one

Existing subscriptions are worth reading in exactly two situations: sampling
names in step 7, and checking for a duplicate after exit 5 / `http_409`.

## Procedure

1. **Resolve your own account and user IDs once, then stop passing them.**

   ```bash
   obcmd account get --fields id
   obcmd user get --fields id
   obcmd config update --account_id <account_id> --user_id <user_id>
   ```

2. **Offer the product menu when the request did not pin one down.** One call
   returns every active product with a summary, so there is no reason to guess
   at search terms:

   ```bash
   obcmd product-card list --fields id,name,summary
   ```

   **That list is active-only, which is why the menu needs no `active` check.**
   It returned 84 rows against a catalog that also holds retired products —
   Twitter Tweet Vault (1) and Instagram Community IQ (9) are both `active: 0`
   and neither appears. The rows carry no `active` field to inspect, so the
   guarantee comes from the endpoint rather than from anything you can see in
   the output; do not re-derive it with `product list`.

   **Leave the Amazon DSP products out of the menu.** Amazon DSP (54) and Amazon
   DSP v3 (85) are not created through this flow at all — customers set those up
   in the Openbridge UI. Offering them as options, even annotated, invites the
   user to pick one and then be turned away, so filter them out of the list
   before presenting it. When someone asks for DSP directly, say plainly that it
   is UI-only and stop; do not resolve its advertisers or stages.

   When a product *was* named, confirm it resolves to one row before continuing:

   ```bash
   obcmd product list --is_storage_product 0 --name_contains "amazon attribution" \
     --fields id,name,active
   ```

   Several products share a family name — there are two called "Google Ads" — and
   **creation against an inactive product is rejected**, which is the most common
   unexplained 400 on this call.

   **An empty result here does not mean the product does not exist.** `product
   list` filters to `active=1` server-side, so a retired product comes back as
   nothing at all. Searching `--name_contains "instagram community"` returns `[]`
   while the same search with `--active 0` returns product 9. Before telling
   someone their platform is unsupported, re-run with `--active 0`: "that
   connector has been retired" is a different answer from "no such product", and
   only one of them is true.

3. **Read the product card. It is the one call that answers "what does this
   product need".**

   ```bash
   obcmd product-card get --product_id 50
   ```

   | Field | What it tells you |
   |---|---|
   | `remote_identity_type_id` / `remote_identity_type_name` | which identities are eligible in step 4 |
   | `subscription_info.spm_requirements` | the selectors to resolve in step 5 |
   | `stages` | every `stage_id` with its table name, for step 6 |
   | `history_info` | the backfill cap per stage — `days`, `max_request_time` |
   | `initialize_job` | whether the backend creates the job for you |

   Read `obcmd subscription create --help --json` once per session for the
   parameter encodings. It states the string-wrapped form inline —
   `product_parameters` is a "flat key/value object, e.g.
   `{"stage_ids":"[1000]"}`" — plus the `storage_group_id`-not-row-`id` rule and
   that `remote_identity` is canonical. Between the card and that call, the only
   parameter fact neither reports is what `product_parameters.account_id` means;
   step 9 covers it.

4. **List the identities of the type the card named.**

   ```bash
   obcmd remote-identity-shared list --remote_identity_type 14 \
     --invalid_identity 0 --fields id,name,region
   ```

   Prefer `remote-identity-shared` over `remote-identity` — it includes
   identities shared with your account, which is what a subscription may attach.
   `--invalid_identity 0` keeps revoked credentials out of the menu. If nothing
   comes back, the user must authorize one first; see
   `authorizing-remote-identities`.

5. **Resolve the card's selectors, in dependency order, and let the plural ones
   be plural.**

   A key named in the singular (`profile_id`, `client_customer_id`) takes one
   value per subscription. A key named in the plural (`marketplace_ids`, `ids`,
   `keywords`) takes a set, so present it as a multi-select rather than asking
   the user to pick one.

   Selectors also chain: `gcm-report list` requires a `--profile_id` and
   `googleads-managed-customer list` requires the manager customer ID, so the
   parent is settled before the child can be listed.
   [references/selectors.md](references/selectors.md) maps every requirement key
   to its command; `resolving-platform-ids` has the detail.

   **For Amazon Advertising, a profile *is* a marketplace.** `amzadv-profile
   list` returns one row per account-marketplace pair, so one seller account
   with four countries is four profiles:

   ```bash
   obcmd amzadv-profile list --remote_identity_id 3433
   ```

   | profile_id | country | account_info.name | account_info.id |
   |---|---|---|---|
   | 1043817530956285 | US | LY Berditchev Co. | A16HZ3J3WEU71V |
   | 1658663597711042 | MX | LY Berditchev Co. | A16HZ3J3WEU71V |
   | 3160527526345509 | BR | LY Berditchev Co. | A16HZ3J3WEU71V |
   | 3113768872537682 | CA | LY Berditchev Co | A16HZ3J3WEU71V |

   So ask it as two questions — which advertiser account, then which marketplaces
   — by grouping the rows on `account_info.id`. **Group on the ID, never the
   name:** the fourth row above is the same Amazon account with a display name
   missing its trailing period, and grouping by name splits one account into two.

   Because `profile_id` is singular, *n* marketplaces means *n* subscriptions.
   That is expected, not a workaround. Dry-run all of them, show the set, take
   one confirmation, then create them in order and report each ID — step 9.

6. **Present the tables by the name a person would recognise, with the stage ID
   and the real table name beside it.** Each stage is a separate feed that lands
   its own tables and gets its own pair of jobs, so quietly subscribing to all of
   them when the user wanted two multiplies the pipeline and the bill.

   The card's stage names are machine names with a shared prefix. Strip the
   longest prefix common to that product's own stage names, turn the underscores
   into spaces, and title-case the rest. **Do not use `worker_name` as the
   prefix** — it often disagrees with the stage names (product 2's worker is
   `fbinsights` while its stages are `fb_*`; product 44's worker is `shopify`
   while its stages are `sh_*`).

   For product 2, common prefix `fb_`:

   | # | Table | stage_id | lands as |
   |---|---|---|---|
   | 1 | Page Insights | 1000 | `fb_page_insights` |
   | 2 | Post Insights | 1001 | `fb_post_insights` |
   | 3 | Post Stats | 1002 | `fb_post_stats` |

   Offer "all of them" as one option among several rather than as the default.
   Subsets are ordinary: live subscription `133390` on that product stores
   `"stage_ids":"[1001,1002]"`, with page insights deliberately omitted. Skip the
   question only when the user already named the tables or the card returns one.

7. **List the destinations and take `storage_group_id`, not the row `id`.**

   ```bash
   obcmd storage list --fields id,name,status,storage_group_id
   ```

   `--storage_group` takes the `storage_group_id` field. Passing the row `id`
   produces a subscription pointed at the wrong destination or a 400, and the
   mistake is invisible afterwards because both are integers.

   **Both numbers are real and both name the same destination**, which is why the
   confusion survives: a destination *is* itself a subscription, and the row `id`
   is that destination subscription's own ID. Observed live: destination
   subscription `129213` is storage group `7096`.

8. **Propose a name that matches the account's house style, if it has one.** One
   call, names only:

   ```bash
   obcmd subscription list --fields name --page_size 25
   ```

   If several names share a visible pattern, propose in that pattern. Many
   accounts have none — a real sample came back with `Openbridge FB Page`,
   `CSVTest3` and `reee is this thing on?` — and in that case fall back to
   `<Product> - <Account label> <Marketplace>`, e.g. `Amazon Attribution - LY
   Berditchev US`. Either way offer it as a suggestion the user can replace; the
   name is the one field where a proposal beats a question.

9. **Dry-run every create, show the set, then execute.**

   ```bash
   obcmd subscription create \
     --account <account_id> --user <user_id> --product 50 \
     --name "Amazon Attribution - LY Berditchev US" \
     --status active --date_start 2026-01-01T00:00:00Z \
     --remote_identity 3433 \
     --storage_group <storage_group_id> \
     --product_parameters '{"stage_ids":"[1000,1001]","profile_id":"1043817530956285"}' \
     --dry-run
   ```

   Drop `--dry-run` to execute. Four details the API will not forgive:

   - **`stage_ids` is a string containing a JSON array**, not an array:
     `"stage_ids":"[1000,1001]"`. It carries the tables chosen in step 6.
   - **An `account_id` inside `product_parameters` is a platform-side ID, never
     your Openbridge account.** The two sit in the same body and look
     interchangeable: `--account 3558` is the Openbridge account, while
     `product_parameters.account_id` is, for Facebook Page Insights, the Facebook
     **Page ID** from `facebook-page list`.
   - **Set the identity with `--remote_identity` only.** It may also be accepted
     inside `product_parameters`, but supplying both is allowed only when they
     agree; conflicting values return 400.
   - `--date_end` defaults to `2099-12-31` when omitted, and `date_start` is never
     returned in responses — do not treat its absence as a failed write.

   For a multi-marketplace fan-out, preview all of them before creating any. A
   dry run costs nothing and a half-finished set of four is the expensive
   outcome.

10. **Confirm each subscription and wait for its jobs before doing anything
    else.**

    ```bash
    obcmd subscription get --subscription_id <id> --fields id,name,status,product_id
    obcmd subscription-parameter list --subscription_id <id>
    obcmd job list --subscription_ids <id> --fields id,status,report_date
    ```

    Jobs appear within about ten seconds — four was the observed delay. History
    backfills require them, so a backfill attempted immediately after creation
    fails for a reason that has nothing to do with the dates.

    **Expect two jobs per stage, not one.** Each stage gets an `is_primary: true`
    and an `is_primary: false` row, so a three-stage subscription creates six
    jobs. That is the correct result, not a duplicate-creation bug.

11. **On exit 5 or `http_409`, read before writing again.** A conflict means a
    matching record exists. The same applies to `outcome_unknown`: the write may
    already have landed, and resending blind is how a duplicate appears.

    ```bash
    obcmd subscription list --product 50 --remote_identity <id> --fields id,name,status
    ```

A full worked flow, including the multi-marketplace fan-out and the
destination-product variant, is in
[references/worked-create.md](references/worked-create.md).

## Rationalizations

| Thought | Reality |
|---|---|
| "They said *add* — I should check whether they mean create or edit" | Add, new and set up mean create. Only a request naming an existing record is an update. |
| "I need to see how their other pipelines are configured first" | The product card carries the requirements and `create --help --json` the encodings. Existing subscriptions answer neither. |
| "`product list --name_contains` came back empty, so we do not support that platform" | It filters to `active=1`. Re-run with `--active 0` — a retired connector and a nonexistent one are different answers. |
| "I should verify `active` on every row of the product menu" | `product-card list` is active-only and its rows carry no `active` field. Checking it again costs 84 calls and proves nothing. |
| "I will search products by guessing a name fragment" | `product-card list` returns all of them with summaries in one call. |
| "Four marketplaces, so one subscription with four profile IDs" | `profile_id` is singular. Four marketplaces is four subscriptions — dry-run all four, confirm once. |
| "I will group the profile rows by account name" | Names differ by punctuation for the same account. Group on `account_info.id`. |
| "The stage names are the table names, so I will show those" | Show both. `amzn_attribution_metrics` reads as "Metrics" to a person, and the raw name still tells them what lands. |
| "`worker_name` is the stage prefix, so I will strip that" | It frequently is not. Strip the longest prefix common to that product's own stage names. |
| "The product has six stages, so the subscription takes six" | Each stage is a separate feed with its own tables and jobs. Ask; a subset is a normal answer. |
| "`stage_ids` is a list, so I will pass a JSON array" | It is a **string** containing a JSON array. An array is rejected. |
| "`storage list` returned `id`, that is the storage group" | `--storage_group` wants `storage_group_id`. Both are integers, so the wrong one fails silently or at 400. |
| "I will set the identity in `product_parameters` with everything else" | Use `--remote_identity`. Supplying both only works when they agree. |
| "`account_id` must be my Openbridge account" | Inside `product_parameters` it is a platform-side ID — a Facebook Page ID, an Amazon profile. `--account` is the Openbridge one. |
| "The create returned 400, I will adjust and retry" | Check product `active` first, then the parameter shapes. Exit 2 is not retryable. |
| "They asked for Amazon DSP, I will list its advertisers" | Both DSP products, 54 and 85, are UI-only. Say so and stop — and keep them out of the product menu so nobody picks one. |
| "Creation succeeded, so I can backfill now" | The jobs appear about ten seconds later. `history trigger` needs them. |
| "Six jobs appeared for three stages, something double-fired" | Each stage gets a primary and a non-primary job. That is the expected shape. |
| "The write timed out — I will send it again" | `outcome_unknown` means it may already have been applied. List first. |

## Supporting files

- [references/selectors.md](references/selectors.md) — every
  `spm_requirements` key, the command that lists its options, and which are
  multi-select.
- [references/worked-create.md](references/worked-create.md) — the complete flow
  end to end, with the multi-marketplace fan-out, the destination-product
  variant and the raw-payload escape hatch.
