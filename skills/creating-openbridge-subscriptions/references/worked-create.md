# Creating a subscription, end to end

Every command here is real. The order is the selection order from `SKILL.md`:
each list is keyed by the answer above it.

## 1. Context

```bash
obcmd account get --fields id
obcmd user get --fields id
obcmd config update --account_id 1234 --user_id 5678   # stop passing them per call
```

## 2. Product

When the user named nothing, show the menu — one call covers every active
product:

```bash
obcmd product-card list --fields id,name,summary
```

When they named one, confirm it resolves to a single active row:

```bash
obcmd product list --is_storage_product 0 --name_contains "amazon attribution" \
  --fields id,name,active,remote_identity_type_id
```

`active` must be `1`. An inactive product is rejected at create, and so is
reactivating a subscription whose product has since gone inactive.

## 3. The card

```bash
obcmd product-card get --product_id 50
```

For product 50 this returns identity type 14 (`Amazon Oauth`),
`spm_requirements: ["profile_id", "remote_identity_id"]`, and six stages
`1000`–`1005` prefixed `amzn_attribution_`.

The Amazon DSP products (54 and 85) never reach this step — they are filtered
out of the menu in step 2, because they are created in the Openbridge UI.

## 4. Identity

```bash
obcmd remote-identity-shared list --remote_identity_type 14 \
  --invalid_identity 0 --fields id,name,region
```

## 5. Selectors

```bash
obcmd amzadv-profile list --remote_identity_id 3433
```

Group the rows on `account_info.id` to ask "which advertiser account?", then
present that group's `country_code` values as the marketplace multi-select. For
identity `3433`, account `A16HZ3J3WEU71V` has four: US, MX, BR, CA — and the CA
row's display name is missing a trailing period, which is why the grouping key
is the ID.

[selectors.md](selectors.md) maps the other requirement keys to their commands.

## 6. Tables

From the card's `stages`, strip the common prefix and title-case the remainder:

| # | Table | stage_id | lands as |
|---|---|---|---|
| 1 | Advertisers | 1000 | `amzn_attribution_advertisers` |
| 2 | Metrics | 1001 | `amzn_attribution_metrics` |
| 3 | Publishers | 1002 | `amzn_attribution_publishers` |
| 4 | Metrics By Campaign | 1003 | `amzn_attribution_metrics_by_campaign` |
| 5 | Metrics By Adgroup | 1004 | `amzn_attribution_metrics_by_adgroup` |
| 6 | Products | 1005 | `amzn_attribution_products` |

The chosen IDs become `stage_ids`, **as a string**: `"stage_ids":"[1000,1001]"`.

## 7. Destination

```bash
obcmd storage list --fields id,name,status,storage_group_id
```

Use `storage_group_id`, not `id`. Destinations are read-only through this API —
create them in the Openbridge UI, or with `destination create` (see
`provisioning-openbridge-destinations`).

## 8. Name

```bash
obcmd subscription list --fields name --page_size 25
```

Match the house pattern if one is visible; otherwise
`<Product> - <Account label> <Marketplace>`.

## 9. Preview, confirm, create

One marketplace:

```bash
obcmd subscription create \
  --account 1234 --user 5678 --product 50 \
  --name "Amazon Attribution - LY Berditchev US" \
  --status active --date_start 2026-01-01T00:00:00Z \
  --remote_identity 3433 --storage_group 7788 \
  --product_parameters '{"stage_ids":"[1000,1001]","profile_id":"1043817530956285"}' \
  --dry-run
```

`--status` accepts `active`, `paused`, `cancelled` or `invalid`. Create as
`paused` when the pipeline should exist but not run yet. Drop `--dry-run` to
execute.

### The multi-marketplace fan-out

`profile_id` is singular, so three marketplaces is three subscriptions — same
product, same identity, same stages, same destination, one `profile_id` each.
Dry-run all three first and show the set:

```
3 marketplaces → 3 subscriptions:
  US  profile 1043817530956285  "Amazon Attribution - LY Berditchev US"
  MX  profile 1658663597711042  "Amazon Attribution - LY Berditchev MX"
  BR  profile 3160527526345509  "Amazon Attribution - LY Berditchev BR"
```

Take one confirmation for the set, then create them in order and report each ID
as it lands. If one fails mid-set, say which succeeded — a partially created set
that nobody enumerated is the failure that takes an hour to untangle.

## 10. Verify

```bash
obcmd subscription get --subscription_id 48213
obcmd subscription-parameter list --subscription_id 48213   # what was actually stored
obcmd job list --subscription_ids 48213 --fields id,status,report_date
```

`subscription-parameter list` returns **one aggregate resource** whose `id` is the
subscription ID — not a list of parameter rows.

The jobs appear within roughly ten seconds, two per stage. Until they exist,
`history trigger` cannot queue anything.

## The destination-product variant

A storage subscription uses a destination product and needs no stages:

```bash
obcmd product list --is_storage_product 1 --fields id,name,active
obcmd subscription create --account 1234 --user 5678 --product <storage_product_id> \
  --status active --date_start 2026-01-01 --remote_identity <identity_id> --dry-run
```

## Raw payload escape hatch

When the convenience flags cannot express the body, send the API shape directly.
`--payload` accepts inline JSON, `@file`, or `-` for stdin:

```bash
echo '{"data":{"type":"Subscription","attributes":{"status":"paused"}}}' \
  | obcmd subscription update --subscription_id 48213 --payload -
```

Prefer the flags. `--payload` bypasses the CLI's own validation, so a shape error
becomes an API 400 instead of a usage error you could have read locally.
