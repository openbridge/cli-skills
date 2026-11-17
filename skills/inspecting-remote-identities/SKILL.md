---
name: inspecting-remote-identities
description: "Use when you need the remote_identity_id for a subscription, when choosing between remote-identity and remote-identity-shared, or when checking whether a third-party credential has been revoked (invalid_identity), before attaching an identity to anything"
license: MIT
---

# Inspecting Remote Identities

## Overview

Two list commands return identities and they answer different questions:
`remote-identity list` returns only what your account created,
`remote-identity-shared list` returns everything your account may *use*,
including identities other accounts shared with you. The core principle: **look
up identities with the shared list, and check `invalid_identity` before trusting
one.**

## When to use

- A subscription needs a `remote_identity` value and you have a platform name,
  not an ID.
- Data stopped arriving and a revoked credential is the suspect.
- You need the metadata stored on an identity (`identity-meta`).

**Not for:** creating or re-authorizing an identity — that needs a browser flow,
covered by `authorizing-remote-identities`. Not for turning an identity into
platform-side IDs such as an Amazon profile or a Google Ads customer; that is
`resolving-platform-ids`.

## Procedure

1. **Default to the shared list for lookups.**

   ```bash
   obcmd remote-identity-shared list --remote_identity_type 14 --invalid_identity 0 \
     --ordering=-id --fields id,name,remote_identity_type_id,invalid_identity,region
   ```

   `--invalid_identity 0` returns valid identities only, `1` returns revoked ones
   only. Omit the flag to see both.

   **`--ordering` is required for correctness on a full sweep, not just for
   presentation.** Without it, `--all` re-serves rows across pages: observed live,
   59 streamed rows carried only 44 distinct IDs, and the same sweep with
   `--ordering id` returned 59 distinct. Always sort a sweep, then confirm the
   distinct count:

   ```bash
   obcmd remote-identity-shared list --all --ordering id --fields id > ri.ndjson
   wc -l ri.ndjson; jq -r .id ri.ndjson | sort -u | wc -l    # must agree
   ```

   `--ordering=-id` reverses it, newest first. **Attach a leading-dash value with
   `=`.** Written `--ordering -id`, the parser reads `-id` as a flag and the
   command exits 2 with `unknown_flags`.

   Use `remote-identity list` only when the question is specifically "what did my
   own account create".

2. **Get the type ID from the product, not by guessing.** A product accepts
   identities of exactly one type:

   ```bash
   obcmd product get --product_id 50 --fields remote_identity_type_id
   obcmd identity-type list --name_contains "amazon" --fields id,name,auth_service
   ```

3. **Treat `invalid_identity: 1` as the explanation, not a detail.** A subscription
   attached to an invalid identity stops processing data. Poll for the whole set
   when triaging an account:

   ```bash
   obcmd remote-identity-shared list --invalid_identity 1 --fields id,name
   ```

   **Then find what that identity is attached to**, because the identity ID alone
   does not tell anyone which pipelines stopped:

   ```bash
   obcmd subscription list --remote_identity 90210 --fields id,name,status
   ```

   Report the affected subscriptions, not just the identity. One revoked
   credential can be shared by several subscriptions, and an invalid identity with
   no active subscription attached is noise rather than an outage.

   The fix is not available from the CLI: the user who owns that platform account
   must re-authorize through the Openbridge UI, or through the flow in
   `authorizing-remote-identities`.

4. **Read one identity when you need its full record.**

   ```bash
   obcmd remote-identity get --remote_identity_id 90210
   ```

   Credentials are never returned by this API. An absent secret is the contract,
   not a truncated response — do not go looking for it elsewhere.

5. **Read identity metadata when a product requires meta fields.**

   ```bash
   obcmd identity-meta get --remote_identity_id 90210 --fields key_name
   obcmd identity-meta get --remote_identity_id 90210 --key_name profile_id
   ```

   `identity-meta get` **always returns an array** — one row per key — even for a
   single key, and it includes `meta_value`. Narrow it with `--fields` when the
   values are not wanted. To sweep across identities instead, use
   `identity-meta list --remote_identity <id>`, which is page-paginated.

6. **To see what an identity is actually used for, read a live subscription's
   stored parameters.** This is the fastest way to learn which platform-side IDs a
   working pipeline pairs with an identity:

   ```bash
   obcmd subscription list --remote_identity 90210 --fields id,name
   obcmd subscription-parameter list --subscription_id 133390
   ```

7. **Check `required_meta_fields` on the product before concluding an identity is
   usable.**

   ```bash
   obcmd product get --product_id 50 --fields id,name,active,required_meta_fields
   ```

   An identity that is valid but missing a required meta key will fail at
   subscription time, not at lookup time.

## Rationalizations

| Thought | Reality |
|---|---|
| "`remote-identity list` is the canonical list" | It omits identities shared with you by other accounts — the ones most subscriptions use. Prefer the shared list. |
| "The identity exists, so the pipeline should work" | Existing and valid are different. Read `invalid_identity`. |
| "I will re-authorize it myself" | Consent is a browser flow owned by the platform account holder. You can only report what needs re-authorizing. |
| "`--all` returned everything, so that is the full list" | Not without `--ordering`. Rows repeat across pages; compare the row count to the distinct `id` count. |
| "An invalid identity means an outage" | Only if an active subscription is attached. Check `subscription list --remote_identity <id>` before reporting one. |
| "`identity-meta get` returned an array, so there are several identities" | It is one row per metadata key on one identity. The array is the declared shape, not a multi-record result. |
| "No credential in the response means the record is broken" | Credentials are never returned by this API, by design. |
| "Any valid identity of the right type will do" | The product's `required_meta_fields` must also be present on that identity. |
