# Starter prompts

Ask for the outcome. The agent picks the skill.

Every skill here declares when it applies, so you do not name it — "set up a
pipeline from Amazon Attribution into Redshift" loads
`creating-openbridge-subscriptions` on its own. Each prompt below is paired with
the skill it should pull in, so you can tell whether delivery is working: if the
agent answers one of these without saying `Using <skill> to …`, the skills are
not reaching it — run [the delivery check](#checking-the-install) first.

Replace bracketed parts. IDs, product names and account names are the difference
between an agent that acts and one that asks three questions first.

## First session

| Say | Loads |
|---|---|
| "What Openbridge skills do you have available?" | `using-skills` |
| "I need to pull a list of our active Openbridge subscriptions with obcmd. What's the command?" | `using-obcmd` |
| "Set obcmd up on this machine — I have not logged in yet." | `authenticating-obcmd` |
| "Show me everything obcmd can do with jobs." | `using-obcmd` |
| "My script keeps breaking on obcmd output — sometimes a table, sometimes JSON, and the error handling never catches anything." | `using-obcmd` |

## Authentication and account context

| Say | Loads |
|---|---|
| "obcmd just exited with code 4 and said not_authenticated. How do I fix it?" | `authenticating-obcmd` |
| "Every obcmd command returns 403 even though my token works in the UI." | `authenticating-obcmd` |
| "Switch obcmd to account [12345] and confirm the token actually allows it." | `authenticating-obcmd` |
| "Which Openbridge account am I pointed at right now?" | `authenticating-obcmd` |
| "Clear the cached obcmd credentials on this box." | `authenticating-obcmd` |

## Connecting a third-party account

| Say | Loads |
|---|---|
| "We need to connect a new Amazon Seller Central account to Openbridge so we can start pulling its data." | `authorizing-remote-identities` |
| "Our Shopify identity shows invalid_identity 1 — how do I get it working again without creating a duplicate?" | `authorizing-remote-identities` |
| "Start the OAuth authorization for a Google Ads account and give me the URL to hand to the client." | `authorizing-remote-identities` |
| "Register our own OAuth client for [Facebook] instead of using the shared Openbridge app." | `authorizing-remote-identities` |
| "How do I find the remote identity ID for our Amazon Advertising account in Openbridge?" | `inspecting-remote-identities` |
| "Check whether any of our Openbridge third-party credentials have gone stale." | `inspecting-remote-identities` |
| "Which identity is subscription [48213] actually using?" | `inspecting-remote-identities` |

## Destinations

| Say | Loads |
|---|---|
| "Create a new Redshift destination in Openbridge for the marketing warehouse." | `provisioning-openbridge-destinations` |
| "What destination types can we create, and which ones does this account already have?" | `provisioning-openbridge-destinations` |
| "`destination get` keeps coming back 202. Is it stuck, and should I just create it again?" | `provisioning-openbridge-destinations` |
| "I need the storage_group_id for our [BigQuery] destination before I create a subscription." | `provisioning-openbridge-destinations` |

## Building a pipeline

| Say | Loads |
|---|---|
| "Set up a new Openbridge pipeline from Amazon Attribution into our Redshift destination." | `creating-openbridge-subscriptions` |
| "Create a subscription for [Amazon Advertising Sponsored Products] on identity [9912] into storage group [771]." | `creating-openbridge-subscriptions` |
| "My `subscription create` keeps returning a 400 and I can't see what's wrong with the body." | `creating-openbridge-subscriptions` |
| "Show me what the create call would send without actually creating anything." | `creating-openbridge-subscriptions` |
| "Clone subscription [48213] onto a second Amazon profile." | `creating-openbridge-subscriptions` |

### Platform IDs the create call needs

| Say | Loads |
|---|---|
| "What's the profile_id I should put in product_parameters for our Amazon Advertising subscription?" | `resolving-platform-ids` |
| "The customer gave me a Google Ads account number from their dashboard — will that work for the subscription?" | `resolving-platform-ids` |
| "Find the SP-API marketplace and seller ID for identity [9912]." | `resolving-platform-ids` |
| "List the Facebook ad accounts this identity can see." | `resolving-platform-ids` |
| "Which Campaign Manager profile and report should this subscription point at?" | `resolving-platform-ids` |

## Changing a pipeline

| Say | Loads |
|---|---|
| "Pause the Openbridge subscription for [Brand X] until the account team sorts out their contract." | `updating-openbridge-subscriptions` |
| "Rename subscription [48213] to [Brand X – Attribution – prod]." | `updating-openbridge-subscriptions` |
| "Repoint subscription [48213] at our new Snowflake destination." | `updating-openbridge-subscriptions` |
| "Add the new payload to the stage_ids on subscription [48213]." | `updating-openbridge-subscriptions` |
| "I updated product_parameters on a subscription and now the profile_id seems to have vanished. What happened?" | `updating-openbridge-subscriptions` |
| "Cancel subscription [48213] — the client churned." | `updating-openbridge-subscriptions` |
| "Read back every product parameter stored on subscription [48213]." | `updating-openbridge-subscriptions` |

Bulk work is a shell loop, not a flag. Say so in the prompt: "pause every
subscription whose name contains [Brand X] — list them first and show me the
loop before running it."

## When a pipeline is broken

| Say | Loads |
|---|---|
| "Our Amazon subscription hasn't loaded anything since Tuesday. Can you find out why?" | `diagnosing-openbridge-pipelines` |
| "No data has arrived from subscription [48213] for three days. Work out why." | `diagnosing-openbridge-pipelines` |
| "`job list` is returning 403 for a subscription I definitely own." | `diagnosing-openbridge-pipelines` |
| "The healthcheck on [48213] is red. What is it telling me?" | `diagnosing-openbridge-pipelines` |
| "Yesterday's load came in short. Which transactions failed?" | `diagnosing-openbridge-pipelines` |

Diagnose before backfilling. A backfill over a broken pipeline queues work that
fails the same way.

## Backfills

| Say | Loads |
|---|---|
| "We're missing all of January for subscription [48213] — can you re-pull that month?" | `backfilling-openbridge-history` |
| "Re-run the last [90] days for subscription [48213]." | `backfilling-openbridge-history` |
| "I kicked off a huge backfill by mistake. How do I stop it?" | `backfilling-openbridge-history` |
| "What history runs are in flight on this account?" | `backfilling-openbridge-history` |
| "How far back can we go on [Amazon Advertising]?" | `backfilling-openbridge-history` |

## Reporting and export

| Say | Loads |
|---|---|
| "Export every subscription on this account to JSON so I can diff it next week." | `using-obcmd` |
| "Give me a table of active subscriptions with their product, destination and last job status." | `using-obcmd` + `diagnosing-openbridge-pipelines` |
| "Find every subscription pointed at the [old Redshift] destination." | `using-obcmd` |
| "Which of our identities have no subscriptions attached?" | `inspecting-remote-identities` |

## Checking the install

| Say | Loads |
|---|---|
| "I just installed this plugin in [Cursor]. How do I know it's actually working?" | `delivery-check` |
| "The bootstrap isn't showing up at the start of my [Copilot CLI] sessions." | `delivery-check` |

## Authoring a skill

| Say | Loads |
|---|---|
| "I want to add a skill to this collection. What structure should it have?" | `example-skill` |
| "Write a skill covering [how we rotate Snowflake keys]." | `example-skill` |

## A full walkthrough

New client, nothing set up. Five prompts, in order — each one ends where the
next begins.

1. "Log obcmd in and point it at account [12345]."
2. "Connect their Amazon Advertising account to Openbridge and give me the
   authorization URL."
3. "Once they've authorized, find the identity and the profile_id for their
   [US] profile."
4. "Create a Redshift destination called [client-x-prod] and wait for it to
   finish provisioning."
5. "Create the Sponsored Products subscription on that identity into that
   destination — dry run first, then create it, then backfill [60] days."

## What makes these work

- **Name the thing.** "Subscription 48213" beats "the broken one."
- **Say the outcome, not the command.** The skill knows the command and the
  order the API needs the IDs in. `obcmd subscription create --foo` in your
  prompt skips the part that keeps you out of a 400.
- **Ask for a dry run when it writes.** "Dry run first" is one phrase and it
  turns an irreversible call into a reviewable one.
- **One goal per prompt.** Chain them, as in the walkthrough above. A single
  prompt asking for a destination, a subscription and a backfill loads three
  skills at once and follows none of them closely.

## What no skill covers

obcmd has no commands for these, so no skill does either — they are console or
support work: billing, credits and auto-recharge; plans and pricing; team
members, invites and roles; notification preferences; browsing S3 contents;
changing a job's schedule; inviting a third party to authorize an identity on
your behalf.
