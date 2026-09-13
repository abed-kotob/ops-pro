-- Ops Control Tower — core schema
--
-- Design notes:
--   * tenant_id is carried everywhere from day one. Retrofitting tenant isolation is far
--     more expensive than carrying an unused column.
--   * orders_snapshot keeps the full Warehance payload in `raw`. The API contract is not
--     yet verified, so we store everything and project typed columns in later migrations
--     as the real field names are confirmed.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- exceptions: the entire system in one table.
-- Rules write here. Notifications read here. Reporting reads its history.
-- ---------------------------------------------------------------------------
create table exceptions (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        text        not null default 'default',
  rule_key         text        not null,
  source           text        not null,
  external_id      text        not null,
  severity         text        not null check (severity in ('low','medium','high','urgent')),
  status           text        not null default 'open'
                     check (status in ('open','acked','resolved','suppressed')),
  assignee         text,
  payload          jsonb       not null default '{}'::jsonb,
  opened_at        timestamptz not null default now(),
  acked_at         timestamptz,
  resolved_at      timestamptz,
  last_notified_at timestamptz,
  notify_count     int         not null default 0
);

-- The most important line in the schema: at most one live exception per rule per entity.
-- This is what makes rule workflows idempotent and prevents alert storms.
create unique index exceptions_dedup
  on exceptions (tenant_id, rule_key, external_id)
  where status in ('open','acked');

-- Notifier queue: open exceptions never notified, oldest first.
create index exceptions_pending_notify
  on exceptions (tenant_id, last_notified_at, opened_at)
  where status = 'open';

-- Reporting: counts and time-to-resolve by rule over a window.
create index exceptions_reporting
  on exceptions (tenant_id, rule_key, opened_at desc);

-- ---------------------------------------------------------------------------
-- orders_snapshot: normalized Warehance mirror, for rule evaluation and trends.
-- ---------------------------------------------------------------------------
create table orders_snapshot (
  tenant_id        text        not null default 'default',
  order_id         text        not null,
  order_number     text,
  status           text,
  warehouse        text,
  shipping_method  text,
  carrier_service  text,
  on_hold          boolean     not null default false,
  ordered_at       timestamptz,
  shipped_at       timestamptz,
  tracking_number  text,
  last_scan_at     timestamptz,
  delivered_at     timestamptz,
  raw              jsonb       not null default '{}'::jsonb,
  synced_at        timestamptz not null default now(),
  primary key (tenant_id, order_id)
);

-- Drives order_unshipped: open, unheld orders ordered oldest first.
create index orders_open_unshipped
  on orders_snapshot (tenant_id, ordered_at)
  where shipped_at is null and on_hold = false;

-- Drives package_stalled: shipped but not yet delivered.
create index orders_in_transit
  on orders_snapshot (tenant_id, last_scan_at)
  where shipped_at is not null and delivered_at is null;

-- ---------------------------------------------------------------------------
-- rule_config: thresholds live in data, not in workflow nodes.
-- Threshold tuning is the real ongoing work, and it varies by warehouse and by
-- shipping method. NULL in a scope column means "applies to everything".
-- ---------------------------------------------------------------------------
create table rule_config (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        text        not null default 'default',
  rule_key         text        not null,
  warehouse        text,
  shipping_method  text,
  threshold_hours  numeric     not null,
  severity         text        not null check (severity in ('low','medium','high','urgent')),
  enabled          boolean     not null default true,
  notes            text,
  updated_at       timestamptz not null default now()
);

-- One config row per rule per scope combination.
create unique index rule_config_scope
  on rule_config (tenant_id, rule_key,
                  coalesce(warehouse, '*'), coalesce(shipping_method, '*'));

-- ---------------------------------------------------------------------------
-- notification_log: append-only record of what was sent where.
-- Kept separate from exceptions so re-notification history is not lost on resolve.
-- ---------------------------------------------------------------------------
create table notification_log (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     text        not null default 'default',
  exception_id  uuid        not null references exceptions(id) on delete cascade,
  channel       text        not null,   -- 'slack' | 'front' | 'twilio' | 'klaviyo'
  target        text,                   -- channel id, phone number, email
  sent_at       timestamptz not null default now(),
  succeeded     boolean     not null default true,
  detail        jsonb       not null default '{}'::jsonb
);

create index notification_log_by_exception
  on notification_log (exception_id, sent_at desc);

-- ---------------------------------------------------------------------------
-- Seed: starting thresholds. Expect these to be wrong — tune them against real
-- data before adding more rules. See docs/rules.md.
-- ---------------------------------------------------------------------------
insert into rule_config (rule_key, threshold_hours, severity, notes) values
  ('order_unshipped',          24, 'high',   'Start conservative; widen after a tuning week.'),
  ('shipping_method_unmapped',  0, 'urgent', 'Systemic: blocks every order using the method.'),
  ('order_hold_aging',         72, 'medium', 'Hold with no note update.'),
  ('package_stalled',          96, 'high',   'No carrier scan movement; needs a tracking source.'),
  ('inventory_blocking',       24, 'medium', 'Open order unshippable due to stock.'),
  ('sms_unanswered',         0.25, 'urgent', '15 minutes on the emergency line.'),
  ('task_overdue',             24, 'medium', 'PM task past due, not closed.');
