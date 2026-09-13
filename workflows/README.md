# n8n workflows

Exported workflow JSON, one file per workflow. This directory is the versioned source of
truth for automation that otherwise exists only inside the n8n Cloud UI.

## Naming

`<phase>-<rule-or-purpose>.json` — e.g. `0-warehance-order-sync.json`,
`1-rule-order-unshipped.json`, `1-notifier-slack.json`.

The phase prefix makes import order obvious to someone rebuilding from scratch.

## Export process

1. In n8n: workflow → **⋯** → Download.
2. Run `scripts/check-secrets.sh` before staging the file.
3. Commit with a message describing the behavior change, not the node change —
   "raise unshipped threshold to 36h for FL warehouse" beats "update workflow".

## Credentials

Never inline a secret in a node. Create the credential in n8n's credential store and
reference it; the export then carries only an id and name, which is safe to commit.

The HTTP Request node is the usual offender — it is easy to paste a key straight into a
header value. `scripts/check-secrets.sh` specifically looks for that.

## Conventions

- **Idempotency.** Rule workflows upsert into `exceptions` and rely on the partial unique
  index to dedup. A rule must be safe to re-run at any time; if re-running it would create a
  second alert, it is wrong.

  Use exactly this form. The `where` clause is required — it is what makes `on conflict`
  match the partial index `exceptions_dedup`; without it Postgres cannot infer the index
  and the statement errors:

  ```sql
  insert into exceptions (rule_key, source, external_id, severity, payload)
  values ($1, $2, $3, $4, $5)
  on conflict (tenant_id, rule_key, external_id) where status in ('open','acked')
  do update set payload  = excluded.payload,
                severity = excluded.severity;
  ```

  Verified behavior: repeated runs update the live exception rather than creating a second
  one, and a recurrence *after* an exception is resolved correctly opens a new one.
- **Auto-resolve.** Every rule workflow also closes exceptions whose condition no longer
  holds. Detection without auto-resolution produces a backlog nobody clears.
- **Thresholds come from `rule_config`,** never hardcoded in a node. Tuning should not
  require editing and re-importing a workflow.
- **Reconciliation over trust.** Webhook-driven syncs get a scheduled sweep as a backstop.
  Webhooks are missed in practice, and a silently stale mirror produces silently missing
  alerts — the worst failure mode this system has.

## Status

Empty pending Phase 0. Workflows are not authored until the Warehance API contract in
`docs/integrations.md` is verified — building against guessed field names produces work
that has to be redone.
