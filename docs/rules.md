# Rule catalog

Each rule is one n8n workflow that finds violations and upserts into `exceptions`.
Thresholds live in the `rule_config` table, not in workflow nodes — see *Tuning* below.

| Rule key | Condition | Default | Severity | Phase |
|---|---|---|---|---|
| `order_unshipped` | Created > N hrs, still unfulfilled, not on hold | 24h | high | 1 |
| `shipping_method_unmapped` | Requested method has no carrier-service mapping | immediate | urgent | 1 |
| `order_hold_aging` | On hold > N days with no note update | 72h | medium | 3 |
| `package_stalled` | Shipped, last carrier scan > N days, not delivered | 96h | high | 3 |
| `inventory_blocking` | Open order unshippable due to stock | 24h | medium | 3 |
| `sms_unanswered` | Inbound emergency SMS, no Front reply in N min | 15m | urgent | 2 |
| `task_overdue` | PM task past due date, not closed | 24h | medium | 4 |

## Severity

Severity controls *routing*, not importance. It is the difference between interrupting
someone and appearing in a digest.

| Severity | Routing |
|---|---|
| `urgent` | Immediate Slack mention + escalation path |
| `high` | Immediate Slack post, no mention |
| `medium` | Batched into the daily digest |
| `low` | Weekly report only |

Anything that pages a human at `urgent` must be genuinely worth interrupting them for. The
fastest way to kill this system is to over-classify.

### Why `shipping_method_unmapped` is urgent

Every other rule describes one broken order. An unmapped shipping method silently blocks
*every* order using that method, and keeps blocking new ones until someone fixes the
mapping. It is a systemic fault reported through a per-order rule, so it gets the higher
severity despite often surfacing on a single order first.

## Tuning

**Threshold tuning is the actual work of this project.** Building a rule takes an hour;
getting its threshold right takes a week of watching real data.

`24h` for `order_unshipped` is a guess. It is wrong for at least: made-to-order SKUs,
weekend order batches, methods with a cutoff time, and any warehouse with a different SLA.
`rule_config` is scoped by warehouse and shipping method precisely so these can diverge
without touching a workflow.

### Process for adding a rule

1. Write the detection query and run it **read-only** against real data.
2. Eyeball the violations it returns. Are they genuinely problems? If more than ~1 in 10 is
   noise, the threshold or the condition is wrong — fix it before wiring notifications.
3. Only then connect the notifier.
4. Watch for a week. Count how many alerts led to an actual action. If that ratio is poor,
   tune before adding the next rule.

Ship one rule at a time. Two rules launched together cannot be tuned independently, because
you cannot tell which one is generating the noise.

## Resolution semantics

- `open` — detected, nobody has acknowledged it.
- `acked` — a human has seen it and owns it. Stops re-notification, still counts as live.
- `resolved` — the underlying condition is gone.
- `suppressed` — known and deliberately ignored (e.g. a customer asked to delay shipment).
  Distinct from `resolved` so it does not pollute the time-to-resolve metric.

Rules should auto-resolve: when a rule's next run finds the condition no longer true for an
entity with a live exception, it sets `resolved`. An exception a human must manually close
after the problem already fixed itself is an exception nobody will close.

`suppressed` is always set by a human, never by a rule.
