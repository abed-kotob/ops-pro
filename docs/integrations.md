# Integration contracts

Record verified facts here. Everything below marked **UNVERIFIED** is an assumption that
must be confirmed against the live API before any workflow is built on it.

The plan's field names were written from the vendor's public description, not from a
response body. Treat them as a starting hypothesis.

---

## Warehance — UNVERIFIED

Docs: `https://developer.warehance.com/docs/getting-started`
API keys: generated in Warehance under Settings.

### Phase 0 verification checklist

Work through these in order. Each has a concrete artifact — paste the real response shape
into this file as you go.

- [ ] **Auth works.** Confirm the header name and format (`Authorization: Bearer …` vs
      `X-API-Key: …`).
      ```bash
      curl -sS -H "Authorization: Bearer $WAREHANCE_API_KEY" \
        https://api.warehance.com/v1/auth-check
      ```
- [ ] **Orders endpoint shape.** Pull one order. Record the real field names for: order id,
      order number, status, warehouse, requested shipping method, hold flag, created
      timestamp, shipped timestamp.
- [ ] **Pagination.** Cursor or offset? What page size? How do you fetch "orders modified
      since T"? Without a `modified_since` filter the reconciliation sweep has to pull
      everything, which changes the polling design.
- [ ] **Status vocabulary.** Enumerate every possible order status value. `order_unshipped`
      depends on knowing exactly which statuses mean "still needs to ship" — guessing here
      produces either false alerts or silent misses.
- [ ] **Hold semantics.** Is "on hold" a status, a boolean, or a separate notes/flags
      concept? Is there a hold reason and a hold timestamp? `order_hold_aging` needs the
      timestamp.
- [ ] **Shipping method mapping.** How are requested shipping methods mapped to carrier
      services? Is the mapping table readable via API? `shipping_method_unmapped` needs to
      detect a *missing* mapping, which requires reading the mapping itself.
- [ ] **Webhooks.** Which events exist? Order created/updated/shipped? Shipment events?
      What's the payload, and is there a signature to verify? Confirm whether retries
      happen on failure — this determines how aggressive the reconciliation sweep must be.
- [ ] **Rate limits.** Requests per minute, and what a 429 looks like. Record the numbers;
      the polling interval depends on them.
- [ ] **Carrier scan timestamps — the one that can change the plan.** Does a shipment
      expose the *last carrier scan time*, or only a tracking number and a terminal status?

### The carrier-scan decision

`package_stalled` means "shipped, but the carrier hasn't scanned it in N days." That needs
a per-scan timestamp, not just `shipped` / `delivered`.

- **If Warehance exposes last-scan time** → no extra vendor. Sync it into
  `orders_snapshot.last_scan_at` and the rule is a simple query.
- **If it does not** → register tracking numbers with a tracking provider and consume their
  webhooks. **EasyPost** (cheap per-tracker, good webhooks) or **AfterShip** (purpose-built
  for this, more expensive). This adds a vendor, a cost line, and a sync workflow.

Resolve this in Phase 0. It is cheap to answer now and expensive to discover in Phase 3.

---

## Front — UNVERIFIED

Needed for Phase 2.

- [ ] Confirm the plan tier includes API access and SMS channels.
- [ ] Conversation search by custom metadata — can a conversation be located by order
      number? This is what makes order-context enrichment possible.
- [ ] Comment API (internal note on a conversation, not a customer-visible reply). Getting
      this wrong sends an internal note to a customer.
- [ ] Rate limits.

## Twilio — UNVERIFIED

Needed for Phase 2. The scope email says "our current provider" — identify who that
actually is before assuming Twilio.

- [ ] Who is the current telephony provider, and can the emergency number live there?
- [ ] Can the number be connected to Front as an SMS channel, or does it need to port?
- [ ] Confirm the escalation path: n8n needs to place an outbound call or SMS on no-reply.

## Klaviyo — UNVERIFIED

Needed for Phase 3.

- [ ] Custom event API shape (`Order Delayed` with properties).
- [ ] Profile matching by email — confirm behavior when the profile does not yet exist.
- [ ] Separate sending subdomain for ops notifications, isolated from marketing.

## PM tool — NOT YET IDENTIFIED

Needed for Phase 4 only. Nothing earlier depends on it.

- [ ] Which tool holds company projects and due dates?
- [ ] Does it have an API with a "tasks past due, not closed" query?

If projects actually live in spreadsheets and people's heads, Phase 4 is an intake process,
not an integration. Establish this before building.
