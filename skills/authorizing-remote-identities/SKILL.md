---
name: authorizing-remote-identities
description: "Use when connecting a new third-party account (Amazon, Google, Facebook, Shopify, Snowflake and the rest) to Openbridge, or re-authorizing one whose credentials were revoked, before attempting to create a subscription that needs it"
license: MIT
---

# Authorizing Remote Identities

## Overview

A remote identity is the credential Openbridge holds for a third-party platform.
Creating one is a **browser flow a human must complete** — the CLI prepares the
state record and consumes the result, but it cannot grant consent. The core
principle: **build the authorize URL, hand it to the user, and wait for the
identity ID that comes back.**

## When to use

- A platform account has never been connected, and a subscription needs it.
- An identity shows `invalid_identity: 1` and must be re-authorized.
- A provider requires your own OAuth application (Snowflake, Shopify) before
  authorization can begin.

**Not for:** finding an identity that already exists, or checking whether one is
still valid — that is `inspecting-remote-identities`. Not for authenticating
*yourself* to Openbridge either; that is `authenticating-obcmd`.

## Create means create

Asked to create an identity, run the create path and nothing else. Do not list
the existing identities of that type, do not offer to re-authorize one, and do
not ask the user to choose between the two. The decision was in the instruction.

An identity of the same type already existing is not a conflict. One platform
holds many accounts, and one account gets authorized more than once for
different scopes — a Facebook identity granted ad-account scopes does not cover
Page Insights. A second record is the normal outcome, not a duplicate to avoid.

Take the re-authorize path only when the user asks for it — re-authorize,
repair, fix, reconnect — or names an identity that is already attached to
something. In a create, the one question worth asking is `return_url`, and it is
a choice between two things: a URL the user names, or
`https://app.openbridge.com/identities`.

## Procedure

1. **Find the identity type ID** for the provider. Every later step keys off it.

   ```bash
   obcmd identity-type list --name_contains snowflake --fields id,name,auth_service
   ```

   `auth_service` tells you which authorization service the provider uses. Filter
   exactly with `--name`, or by service with `--auth_service`.

2. **For Snowflake and Shopify only, store your own OAuth application first.**
   Other providers use Openbridge's registered application and skip this step.

   ```bash
   obcmd oauth-app create --remote_identity_type 19 \
     --account <account_id> --user <user_id> \
     --client_id "$CLIENT_ID" --client_secret "$CLIENT_SECRET" \
     --extra_params '{"account_authorization_url":"https://acct.snowflakecomputing.com"}' \
     --dry-run
   ```

   Take the secret from the environment, never from a literal in the command.
   `extra_params` is a JSON-encoded **string**: `account_authorization_url` for
   Snowflake, `shop_url` for Shopify. `client_secret` is write-only and never
   returned by `oauth-app get`.

   Creating with an `account` and `client_id` that already exist **updates** the
   record and returns 200 rather than 201 — so a re-run is an update, not a
   duplicate.

3. **Create the state record.** It carries the flow context and returns the token
   that identifies this authorization attempt.

   ```bash
   obcmd state create --remote_identity_type_id 19 --user_id <user_id> \
     --region global \
     --return_url https://app.openbridge.com/identities \
     --oauth_id <oauth_id>
   ```

   - `account_id` and `oauth: true` are injected server-side from your token. Do
     not try to set them.
   - **`return_url` has exactly two legitimate values: a URL the user names, or
     the Openbridge console identities page.**

     ```
     https://app.openbridge.com/identities
     ```

     Offer those two and nothing else. `/identities` is the page that lists the
     identities, so the `ri_id` appended on return lands somewhere that can show
     it. Do not construct any other console path — `/oauth/complete`,
     `/callback`, `/auth/return` and the like are invented routes, and a guessed
     path is as dead as a guessed host.

     The API hosts are `*.openbridge.io`; the console is
     `https://app.openbridge.com`. Do not derive one from the other. A URL that
     does not resolve still lets consent complete and the identity get created —
     it strands the person mid-flow on a broken page, and `ri_id` never arrives.
     Recover the ID with `remote-identity-shared list --ordering=-id`, but the
     user has already hit a dead end by then.
   - `--oauth_id` is required for Snowflake and Shopify, and omitted otherwise.
   - `--shop_url` carries the Shopify store URL.
   - **To re-authorize an existing identity, pass `--remote_identity_id`.** Without
     it the flow creates a second identity instead of repairing the one in use,
     and the subscriptions stay attached to the broken one. Omit it on a create —
     a second identity is the point there.
   - `--query_params` appends extra key/value pairs to `return_url` on completion —
     use it to carry your own correlation ID through the redirect.

4. **Hand the authorize URL to the user.** The token returned by `state create` is
   the `state` parameter:

   ```
   https://oauth.api.openbridge.io/oauth/initialize?state=<token>
   ```

   The user completes consent in a browser. Openbridge then redirects to
   `return_url` with `ri_id=<new identity id>`. That `ri_id` is the
   `remote_identity` value a subscription needs. You cannot complete this step on
   their behalf — say plainly that the link must be opened by whoever owns the
   platform account.

5. **Inspect the state record while a flow is in progress**, and clean up if it is
   abandoned.

   ```bash
   obcmd state get --token <token>
   obcmd state update --token <token> --state '{...}'    # replaces the state object
   obcmd state delete --token <token> --dry-run          # destructive; add --yes to run
   ```

   `state update` replaces the state object rather than merging into it — read it
   first and send the whole thing back.

6. **For a non-OAuth flow, use `generic-state create`.**

   ```bash
   obcmd generic-state create --state '{"...":"..."}'
   ```

   This endpoint is unauthenticated: no account context is injected and no
   credential is acquired or sent. It stores flow context only, so nothing about a
   successful call implies an identity now exists.

7. **Confirm the identity landed before building on it.**

   ```bash
   obcmd remote-identity-shared list --remote_identity_type 19 --invalid_identity 0 \
     --ordering=-id --fields id,name,invalid_identity
   ```

   The new ID at the top, with `invalid_identity: 0`, is the proof. Only then
   create or repoint the subscription.

## Rationalizations

| Thought | Reality |
|---|---|
| "I will create the identity through the API" | There is no identity create endpoint. Consent happens in a browser, by a human. |
| "A successful `state create` means the account is connected" | It means a flow is prepared. Nothing is connected until the user finishes and an `ri_id` comes back. |
| "Re-authorizing is just running the flow again" | Without `--remote_identity_id` you get a *second* identity, and the existing subscriptions keep failing against the old one. |
| "One of this type already exists — I should offer to re-authorize it instead" | The instruction said create. Offering the choice reopens a decision the user already made. |
| "Creating a second identity for the same platform must be a mistake" | Different account, or the same account with different scopes. Page Insights is not covered by an ad-account grant. |
| "`oauth-app create` twice will duplicate the app" | Same account and `client_id` updates in place and returns 200. |
| "The console must live on the same domain as the API" | API hosts are `*.openbridge.io`; the console is `https://app.openbridge.com`. A `return_url` that does not resolve dead-ends the person completing consent and loses the `ri_id`. |
| "`https://app.openbridge.com/oauth/complete` looks like the callback path" | It is a path you made up. The only console `return_url` is `https://app.openbridge.com/identities`; everything else comes from the user. |
| "I will put the client secret in the command" | argv is visible to every user on the machine. Read it from the environment. |
| "`generic-state create` is unauthenticated, so it is the easy path" | It acquires no credential at all. It only parks flow context. |
| "Snowflake works like the other providers" | Snowflake and Shopify need your own OAuth app recorded first, and `--oauth_id` on the state record. |
