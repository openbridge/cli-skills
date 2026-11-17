# Platform lookups by integration

Every command here is a read. All take `--remote_identity_id`; the second column
lists what *else* is required. Response shapes are from `obcmd describe --json` —
`array` unless noted.

## Amazon Advertising

| Command | Also needs | Returns / feeds |
|---|---|---|
| `amzadv-profile list` | `--profile_types seller,vendor` (optional), `--is_manager` (optional) | Advertising profiles. **The returned profile ID is the `profile_id` product parameter.** |
| `amzadv-advertiser list` | `--profile_id` | DSP advertisers for one profile |
| `amzadv-brand list` | `--profiles <csv>` (optional) | Brands visible to the profile |
| `amzadv-kdp get` | `--profile_id` | object — whether the profile is a Kindle Direct Publishing account |
| `amzadv-attribution validate` | `--profile_id` | object — whether attribution reporting works for the profile |
| `amzadv-dsp-map list` | — | DSP report field maps (no identity needed) |
| `amzadv-dsp-metric list` | — | DSP report metrics (no identity needed) |

Order: `amzadv-profile list` first; `advertiser`, `brand`, `kdp` and
`attribution` all consume its `profile_id`.

## Amazon Seller and Vendor (SP-API)

| Command | Also needs | Returns / feeds |
|---|---|---|
| `sp-marketplace list` | — | marketplaces the identity can sell in |
| `sp-seller-id get` | — | object — the selling partner ID. A POST that reads; no `--dry-run` is offered because nothing changes |
| `sp-asin validate` | `--asins '["B0...","B0..."]'` | object — whether those ASINs resolve for this identity |
| `sp-credential validate` | `--payload <json>` | object — validates a private SP-API application credential. Supply the full credential object with `--payload`, from a file or stdin, never inline in argv |
| `sp-notification-type list` | `--account_type seller\|vendor` | available notification types |
| `sp-notification create` | `--notification_type` (optional) | **mutating** — creates a notification subscription |
| `sp-notification update` | `--subscription_id` | **mutating** |
| `sp-notification delete` | `--subscription_id` | **destructive** — preview with `--dry-run`, then `--yes` |

`sp-notification` is the one integration group that writes. Treat it like any
other mutation: dry-run first.

## Google

| Command | Also needs | Returns / feeds |
|---|---|---|
| `googleads-customer list` | — | Google Ads customers the identity can reach |
| `googleads-managed-customer list` | `--google_ads_customer_id` | customers managed by that manager account |
| `gcm-profile list` | — | Campaign Manager 360 user profiles |
| `gcm-report list` | `--profile_id` | Campaign Manager 360 reports for a profile |
| `gsa-agency list` | — | Search Ads 360 agencies and advertisers |
| `youtube-channel list` | — | YouTube channels for the identity |
| `youtube-channel get` | `--channel_id` | object — metadata for one channel, looked up by URL |

Order: `googleads-customer` before `googleads-managed-customer`;
`gcm-profile` before `gcm-report`.

## Facebook

| Command | Also needs | Returns / feeds |
|---|---|---|
| `facebook-ad-account list` | `--next` (optional, continuation token) | ad accounts for the identity |
| `facebook-page list` | — | page profiles for the identity |

`facebook-ad-account list` paginates with Facebook's own `next` token rather than
with `--page` or `--all`. Pass the token back on the following call.

## Shopify

| Command | Also needs | Returns / feeds |
|---|---|---|
| `shopify-shop-graphql get` | — | object — shop info via the GraphQL Admin API |

Shopify identities require your own OAuth app and a `shop_url`; see
`authorizing-remote-identities`.
