create extension if not exists pgcrypto;

create table if not exists membership_codes (
  id uuid primary key default gen_random_uuid(),
  activation_code text not null unique,
  code_hash text not null unique,
  status text not null check (status in ('trial_active', 'active', 'past_due', 'cancelled', 'expired')),
  plan text not null check (plan in ('trial', 'monthly', 'annual', 'family')),
  max_devices integer not null default 1,
  shopify_order_id text unique,
  shopify_order_name text,
  shopify_confirmation_number text,
  shopify_customer_id text,
  shopify_subscription_id text,
  customer_email text,
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists membership_devices (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null references membership_codes(id) on delete cascade,
  app_install_id text not null,
  platform text not null default 'ios',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (membership_id, app_install_id)
);

create index if not exists membership_codes_code_hash_idx on membership_codes(code_hash);
create index if not exists membership_codes_order_idx on membership_codes(shopify_order_id);
create index if not exists membership_devices_membership_idx on membership_devices(membership_id);
