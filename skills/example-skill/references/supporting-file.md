# Supporting File

This is what a supporting file looks like and where it goes:
`skills/<skill-name>/references/<topic>.md`, linked from `SKILL.md` with a relative
path.

## What belongs here

Material an agent needs *after* it has decided to act, not before:

- Flag tables, API surfaces, enum values
- Worked examples too long to sit inline
- Per-environment or per-tool detail that only some readers need

## What does not

The decisions. `SKILL.md` is what an agent reads to know *what to do*; if the
procedure lives out here, the skill body no longer shapes behaviour and the agent may
never follow the link.

A useful test: if removing this file changed what the agent *does* rather than how
well it does it, the content is in the wrong place.

## Why split at all

The bootstrap skill is in context every session, so its length is a standing tax.
Other skills are loaded on demand, so their length is paid only when relevant — but
an agent still has to read the whole `SKILL.md` before acting. Long reference
material inline delays every use of the skill.

Splitting also makes the skill readable by a human reviewing it, which is when most
errors in a skill are caught.

## Note

This file carries no confirmation phrase. Proving that supporting files are delivered
is [delivery-check](../../delivery-check/SKILL.md)'s job, and mixing the two would
mean this template could not be deleted or freely edited.
