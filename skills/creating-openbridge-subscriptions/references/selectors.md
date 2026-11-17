# Selector requirements, key by key

`subscription_info.spm_requirements` on the product card names the selectors a
product needs. `remote_identity_id` is always satisfied by `--remote_identity`;
every other key is a platform-side choice the user makes from a list.

Two reading rules cover most of this table:

- **Plural key, multi-select.** `marketplace_ids`, `ids` and `keywords` take a
  set inside one subscription. Singular keys — `profile_id`,
  `client_customer_id`, `account_id` — take one value, so covering several means
  several subscriptions.
- **Some lists need a selector you have not asked for yet.** `gcm-report list`
  requires `--profile_id`, and `googleads-managed-customer list` requires the
  manager account's customer ID. Nothing lists a report before its profile.

Every command below takes `--remote_identity_id`, from
`remote-identity-shared list`.

| Requirement key | Lists its options with | Products that ask for it | Shape |
|---|---|---|---|
| `profile_id` | `amzadv-profile list` | 50 Amazon Attribution, 70 Advertising Insights, 75 Brand Metrics, 79 Tactical Recommendations | one per subscription; a profile *is* a marketplace, so *n* countries is *n* subscriptions |
| `account_id` | `facebook-page list` | 2 Facebook Page Insights | the Facebook **Page ID**, not your Openbridge account |
| `account_id` + `fb_account_id` | `facebook-page list`, `facebook-ad-account list` | 34 Instagram Business IQ, 38 Instagram Stories | the card does not say which key takes which — confirm the pair with the user before sending |
| `ad_account_id` | `facebook-ad-account list` | 11 Facebook Marketing | cursor-paginated: follow `--next` |
| `account_id` + `advertiser_ids` + `managed` | — | 54 Amazon DSP, 85 Amazon DSP v3 | **neither is created through this flow** — DSP setup happens in the Openbridge UI. The row is here so the requirement is recognisable, not so it can be resolved. |
| `marketplace_ids` | `sp-marketplace list` | 94 Sales API | multi-select within one subscription |
| `client_customer_id` + `manager_customer_id` | `googleads-customer list`, then `googleads-managed-customer list --google_ads_customer_id <manager>` | 63 Google Ads | manager first, then the client it manages |
| `dfa_profile_id` + `dfa_report_id` | `gcm-profile list`, then `gcm-report list --profile_id <id>` | 4 Google DFA Reports | the report list is keyed by the profile |
| `shop_created_at` | `shopify-shop-graphql get` | 44 Shopify | read from the shop record, not asked of the user |
| `id_type` + `ids` | no list command — the user supplies ASINs or similar | 82 Catalog API | `ids` is a set |
| `keywords` | no list command — the user supplies them | 109 Catalog API keywords | a set |
| `dataset_id`, `snowflake*`, `databricks*` | destination products — see `provisioning-openbridge-destinations` | 37 BigQuery, 52 Snowflake, 73 Databricks External | connection details, not platform selectors |
| `notification_subscriptions`, `selected_tables`, `sqs_*` | no list command | 86 Amazon SP Notifications | unusual enough to walk through with the user field by field |

**Forty-four of the eighty-four active products declare no selector at all** —
the YouTube products, Google Analytics 360, and most of the SP-API report
products (53 Orders, 56 Inbound Fulfillment, 60 Inventory and the rest) need
only an identity and their stages. When `spm_requirements` is empty or holds
only `remote_identity_id`, step 5 of the procedure has nothing to ask.

`resolving-platform-ids` carries the detail for the lookups themselves — which
profile types exist, what proves an ID is visible to the identity, and the
validate calls that confirm a pairing before you send it.
