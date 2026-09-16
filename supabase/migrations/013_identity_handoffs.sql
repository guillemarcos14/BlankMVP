-- One canonical identity for the web account, app install and assistant channel.
-- Netlify functions use the service role; clients never write these tables directly.
create table if not exists blankmind_identity_links (
  auth_user_id uuid primary key,
  phone_e164 text unique,
  app_install_id text unique,
  assistant_connect_code text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table blankmind_identity_links enable row level security;

create index if not exists blankmind_identity_links_phone_idx
  on blankmind_identity_links(phone_e164);

create table if not exists app_handoffs (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  auth_user_id uuid not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table app_handoffs enable row level security;

create index if not exists app_handoffs_active_idx
  on app_handoffs(token_hash, expires_at)
  where consumed_at is null;
