# obcmd output guarantees

What the CLI promises, so that calling code does not need defensive branches.

## Streams

- stdout carries data only.
- Errors and progress go to stderr, as JSON, always paired with a non-zero exit.
- Output is JSON when stdout is not a TTY or `--json` is passed; human tables
  otherwise. `--output json|text` overrides `--json`.
- Never parse the human table. It is presentation, not a contract.

## Shape

- Optional fields are present as `null`, never omitted.
- Empty collections are `[]`, never `null`.
- JSON:API responses are flattened to `{ id, ...attributes, <relationship>_id }`.
- **The top-level type never depends on how many records matched.** It comes from
  `response_shape` per command: `array` or `object`.
- `list` is always an array, even for one result.
- Most `get` commands are always an object. Three address a table rather than one
  record and are **always an array**, even for a single row:

  | Command | Why |
  |---|---|
  | `identity-meta get` | one row per metadata key on the identity |
  | `subscription-parameter get` | one row per requested subscription ID |
  | `history-limit get` | one row per (product, subproduct, stage) |

- A `get` declared `object` that matches more than one record fails with
  `unexpected_collection` rather than silently returning the first.

## Fields

- No command omits a field. A response carries every attribute the API returned;
  narrowing is yours to request with `--fields`.
- `default_fields` in `describe --json` picks columns for the human table only. It
  has no effect on JSON output.
- Field names are stable across patch and minor versions.
- IDs are serialized as the API serializes them: `id` is a string, foreign keys
  such as `storage_group_id` are integers. The CLI does not rewrite them —
  **compare with a cast, not by type.**

## Telling introspection from data

Introspection responses carry an `introspection` key (`tree`, `resource` or
`command`); data responses never do. `obcmd <resource> describe` prints help and
exits 0, so check that key before treating a response as records.
