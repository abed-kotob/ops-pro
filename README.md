# Ops Engine — Ops Control Tower

Exception engine for fulfillment operations. Detects problems in Warehance (orders that
haven't shipped, unmapped shipping methods, stalled packages), routes them to the people who
can fix them, tracks them to resolution, and rolls the trend up to management.

**This is not a dashboard.** The deliverable is: something is wrong → the right person is
told, once, in the tool they already use → it's tracked until resolved → the trend reports up.

## Architecture

```
SOURCES                    SPINE                      DESTINATIONS

Warehance  ──webhook──┐                          ┌──> Slack      (internal alerts)
           ──poll─────┤                          │
Carrier tracking ─────┼──> n8n ──> Supabase ─────┼──> Front      (customer context)
                      │   (rules)   (state,      │
PM tool (TBD) ────────┘             history)     ├──> Twilio     (emergency line)
                                                 │
                                                 └──> Klaviyo    (customer email)
```

**n8n does the moving. Supabase holds the truth.**

The system is glue-first: automation lives in n8n Cloud as configuration, not in a custom
application. The one piece of owned infrastructure is a Postgres database, because stateless
automation cannot dedup alerts or report trends.

## Why a database in a low-code system

Without memory of what was already sent, a 15-minute polling loop re-alerts on the same
stuck order 96 times a day and the channel gets muted within a week.

The partial unique index in `supabase/migrations/0001_init.sql` is what prevents that. It
permits only one *open* exception per rule per entity, which makes every rule workflow
safely idempotent — re-running one cannot create a duplicate alert.

## Repository layout

| Path | Contents |
|---|---|
| `supabase/migrations/` | Database schema |
| `workflows/` | Exported n8n workflow JSON, one file per workflow |
| `docs/rules.md` | Rule catalog — thresholds, severities, rationale |
| `docs/integrations.md` | Verified API contracts, auth, rate limits |
| `docs/runbooks/` | What a human does when each exception fires |
| `scripts/check-secrets.sh` | Pre-commit guard against committing credentials |

This repo is the versioned source of truth for configuration that otherwise exists only
inside SaaS UIs.

## Setup

1. Create a Supabase project. Apply `supabase/migrations/0001_init.sql`.
2. Create an n8n Cloud account. Add credentials for Warehance, Supabase, and Slack to the
   n8n **credential store** — never inline in a workflow.
3. Work through `docs/integrations.md` to verify the Warehance API contract before building
   any workflow against it.
4. Import workflows from `workflows/` as they are authored.

## Security

Exported n8n JSON must reference credentials by ID, never embed secret values. Run
`scripts/check-secrets.sh` before committing any workflow export — a leaked key in git
history is impractical to fully remove.

## Status

Phase 0 (foundation). See the project plan for phasing; the immediate blocker is verifying
the Warehance API contract, which every later phase depends on.
