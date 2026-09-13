# Runbook — `order_unshipped`

**Fires when:** an order was created more than the configured threshold ago, is still
unfulfilled, and is not flagged on hold.

**Severity:** high — posted to Slack immediately, no mention.

**Why it matters:** this is the single most expensive failure in fulfillment. The customer
is waiting, the SLA clock is running, and nobody has noticed. It is also the exact detection
work a person is doing manually today.

## Triage

Work down this list. Stop at the first that applies.

1. **Is it actually on hold, but the flag wasn't set?**
   A hold applied by phone or in a note, never recorded in Warehance, looks identical to a
   stuck order. → Set the hold flag properly, then `suppress` the exception.
   If this happens often, the hold process is the real problem, not this order.

2. **Is the shipping method mapped?**
   Check whether a `shipping_method_unmapped` exception exists for the same method. If so,
   this order is a symptom — fix the mapping and this resolves along with every other order
   using it.

3. **Is inventory available?**
   If the order cannot be picked, this is an inventory problem wearing a shipping problem's
   clothes. → Escalate to whoever owns purchasing, `ack` with a note.

4. **Is the warehouse aware?**
   If none of the above, it is sitting in the queue at the warehouse. → Contact them, get a
   commitment on a ship date, `ack` with that date in the note.

5. **Should the customer be told?**
   If the new ship date pushes past what the customer was promised, send a proactive delay
   note. Once Phase 3 is live this fires automatically; until then it is manual.

## Resolution

The rule auto-resolves: once the order ships, the next run sets `resolved`. You do not need
to close it by hand.

Use `suppress` — never `resolve` — for orders that are legitimately not going to ship soon
(customer-requested delay, pre-order, hold). `suppressed` is excluded from time-to-resolve,
so using `resolve` here quietly corrupts the metric Arsen is reading.

## When this fires too often

More than a handful a day usually means the threshold is wrong, not that operations are
failing. Before adding exclusions to the rule, check whether the threshold should differ by
warehouse or shipping method — that is what the scope columns in `rule_config` are for.

A rule that fires constantly is one everyone learns to ignore, which is worse than not
having it.
