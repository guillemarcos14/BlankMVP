-- Links the authenticated web account to the anonymous product identity used by
-- the existing analytics/BAI tables. This keeps the public event model intact
-- while making account deletion complete and auditable.
create table if not exists privacy_user_links (
  auth_user_id uuid primary key,
  anonymous_user_id text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table privacy_user_links enable row level security;

create table if not exists referral_codes (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique,
  anonymous_user_id text not null unique,
  code text not null unique,
  created_at timestamptz not null default now()
);

create index if not exists referral_codes_code_idx on referral_codes(code);
alter table referral_codes enable row level security;
