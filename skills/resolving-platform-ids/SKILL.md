---
name: resolving-platform-ids
description: "Use when a subscription or product parameter needs a platform-side identifier - an Amazon Advertising profile or advertiser, an SP-API marketplace or seller ID, a Google Ads customer, a Campaign Manager profile or report, a Search Ads 360 agency, a YouTube channel, a Facebook ad account or page, or a Shopify shop - before putting any such ID into product_parameters"
license: MIT
---

# Resolving Platform Ids

## Overview

Openbridge subscriptions need identifiers that live on the *other* platform:
Amazon profile IDs, Google Ads customer IDs, Facebook ad account IDs. Each
integration exposes a lookup that turns a remote identity into those IDs. The
core principle: **resolve every platform ID from the identity that will be used,
not from a dashboard, a URL or the user's memory.**

## When to use

- Filling `product_parameters` for a subscription and a platform ID is required.
- Checking that an identity can actually see the account the user named.
- Confirming a platform-side permission before blaming the pipeline.

**Not for:** finding the remote identity itself (`inspecting-remote-identities`),
or assembling the subscription once the IDs are known
(`creating-openbridge-subscriptions`).

## Procedure

1. **Start from a valid remote identity ID.** Every lookup takes
   `--remote_identity_id`, and all of them fail or return nothing useful against a
   revoked credential.

   ```bash
   obcmd remote-identity-shared list --remote_identity_type 14 --invalid_identity 0 \
     --fields id,name
   ```

2. **Run the lookup for that platform.** The full table — every command, its
   required flags, and what its output feeds — is in
   [references/platform-lookups.md](references/platform-lookups.md). The common
   case:

   ```bash
   obcmd amzadv-profile list --remote_identity_id 90210 --profile_types seller,vendor
   obcmd sp-marketplace list --remote_identity_id 90210
   obcmd googleads-customer list --remote_identity_id 90210
   ```

3. **Chain the lookups that take a platform ID of their own.** Several second-level
   lookups require the ID resolved in step 2, not the identity alone:
   `amzadv-advertiser list` and `gcm-report list` need a `--profile_id`,
   `googleads-managed-customer list` needs `--google_ads_customer_id`.

4. **Confirm which parameter the ID belongs to before writing it.** Parameter names
   differ per product; do not infer one from the lookup's field name.

   ```bash
   obcmd product-card get --product_id 50      # spm_requirements, stages, history_info
   obcmd product get --product_id 50 --fields required_meta_fields
   ```

   `product-card get` is the better first call: `subscription_info.spm_requirements`
   lists the required parameters, and `stages` pairs every `stage_id` with its
   payload name.

   Two are settled:

   - the ID from `amzadv-profile list` is the `profile_id` product parameter for
     Amazon Advertising subscriptions;
   - the ID from `facebook-page list` is the **`account_id`** product parameter for
     Facebook Page Insights — confirmed against a live subscription's stored
     parameters.

   **`account_id` in `product_parameters` never means the Openbridge account.**
   The create body carries both — `account` is yours, `account_id` is the
   platform's — and they are adjacent, similarly named, and both integers in
   appearance. Read the parameter off a working subscription when in doubt:

   ```bash
   obcmd subscription-parameter list --subscription_id 133390
   # {"id":"133390","account_id":"553114188104602","stage_ids":"[1001,1002]"}
   ```

5. **Validate before subscribing where the integration offers it.** These are
   reads — nothing is created, and a failure here is cheaper than a subscription
   that provisions and then produces nothing.

   ```bash
   obcmd amzadv-attribution validate --remote_identity_id 90210 --profile_id <profile_id>
   obcmd sp-asin validate --remote_identity_id 90210 --asins '["B000000000"]'
   obcmd amzadv-kdp get --remote_identity_id 90210 --profile_id <profile_id>
   ```

6. **Expect an array and read every row.** All of these lookups return arrays
   (`shopify-shop-graphql get`, `sp-seller-id get`, `amzadv-kdp get` and
   `amzadv-attribution validate` return objects). A single-element array is still
   an array. When more than one row comes back, ask the user which account they
   mean rather than taking the first.

7. **Serialize the calls.** Resolving IDs across several platforms is many
   requests against a 1,000-request / 5-minute budget shared with everything else.
   Run them one at a time, not concurrently.

## Rationalizations

| Thought | Reality |
|---|---|
| "The user gave me the profile ID, that is enough" | An ID the identity cannot see fails at subscription time or silently produces nothing. The lookup proves visibility. |
| "I will copy the ID out of the platform's dashboard URL" | It may belong to an account this identity has no access to, and some platforms show a different ID in the URL than the API expects. |
| "The lookup returned one row, so there is only one account" | It returned one row *for this identity*. Another identity may see others. |
| "`account_id` is the Openbridge account" | In `product_parameters` it is the platform's ID — a Facebook Page ID, for instance. `--account` is the Openbridge one. |
| "The field is called `profile_id`, so the parameter is `profile_id`" | True for Amazon Advertising; not a general rule. Check the product card. |
| "`validate` might change something" | These are reads. `sp-seller-id get` is a POST that reads, which is why it offers no `--dry-run`. |
| "I will fire all the lookups at once to save time" | They share one rate limit with every other Openbridge call. Serialize. |

## Supporting files

- [references/platform-lookups.md](references/platform-lookups.md) — every
  integration lookup by platform, with required flags and chaining order.
