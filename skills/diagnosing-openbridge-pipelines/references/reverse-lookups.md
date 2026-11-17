# Reverse lookups: what is attached to this?

Triage questions are almost always backwards from how the API is shaped. These
are the joins that answer them. Every one is a read.

## Which subscriptions use this identity?

The question that turns a revoked credential into a list of affected pipelines.

```bash
obcmd subscription list --remote_identity 90210 --fields id,name,status
```

An invalid identity with no `active` subscription attached is **not an outage** —
run this before reporting one. Conversely, one identity can be shared by several
subscriptions, so a single re-authorization can fix all of them at once.

Sweeping the whole account:

```bash
obcmd remote-identity-shared list --all --ordering id --invalid_identity 1 --fields id,name
obcmd subscription list --status active --all --fields id,name,remote_identity_id
```

Then intersect locally on `remote_identity_id`. Do not eyeball it — in a live
account of 59 identities and 20 active subscriptions, reading the two tables by
eye missed two of the six affected subscriptions.

## Which subscriptions feed this destination?

A destination is itself a subscription, and it carries **two** numbers:

| Field from `storage list` | What it is |
|---|---|
| `id` | the destination's own subscription ID |
| `storage_group_id` | the handle that **source** subscriptions point at |

So the join goes through `storage_group_id`, never through `id`:

```bash
obcmd storage list --fields id,name,status,storage_group_id
obcmd subscription list --storage_group 7096 --all --fields id,name,status,product_id
```

Observed live: destination subscription `129213` is storage group `7096`, and that
group had three `cancelled` subscriptions plus the destination itself — so the
revoked credential on it was breaking nothing downstream.

Note the result includes the destination subscription itself. A destination whose
only hit is its own row has nothing feeding it.

## Which subscriptions use this product?

```bash
obcmd subscription list --product 2 --all --fields id,name,status
obcmd subscription list --product 2 --status_not invalid --fields id,name,status
```

`--status_not` excludes one status; there is no multi-value form. Counting by
status locally is usually more informative than a filtered query:

```bash
obcmd subscription list --product 2 --all --fields id,status \
  | jq -s 'group_by(.status) | map({status: .[0].status, n: length})'
```

## What parameters does a working subscription store?

The empirical answer to "what does this product need", and the fastest one.

```bash
obcmd subscription list --product 2 --status_not invalid --fields id,name
obcmd subscription-parameter list --subscription_id 133390
```

Returns the stored keys verbatim — including which optional parameters live
pipelines actually set. Remember that an `account_id` here is a platform-side ID,
not the Openbridge account.

## Which identity type does a product require, by name?

`subscription list` and `product get` both report
`remote_identity_type_id` as a number. The card names it:

```bash
obcmd product-card get --product_id 2    # remote_identity_type_name
obcmd identity-type list --all --fields id,name
```

Keeping a local `identity-type` map is worth one call when labelling more than a
couple of identities.

## Caution on every sweep

These joins all rely on `--all`, and page-based sweeps can repeat rows when no
sort is applied. Sort with the command's ordering flag where it has one, and
deduplicate by `id` where it does not — `subscription list` has no sort flag.
Compare row count against distinct `id` count before trusting any total.
