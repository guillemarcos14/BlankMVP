create table if not exists wearable_connections (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  provider text not null,
  status text not null default 'disconnected',
  scopes text[] not null default '{}',
  external_account_hash text,
  encrypted_access_token text,
  encrypted_refresh_token text,
  token_expires_at timestamptz,
  last_sync_at timestamptz,
  last_error text,
  disconnected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wearable_connections_provider_check
    check (provider in ('apple_health', 'health_connect', 'oura', 'whoop', 'garmin', 'fitbit_google_health', 'withings')),
  constraint wearable_connections_status_check
    check (status in ('connected', 'partial', 'no_data', 'stale', 'error', 'disconnected'))
);

create unique index if not exists wearable_connections_user_provider_idx
  on wearable_connections(anonymous_user_id, provider);

create index if not exists wearable_connections_user_status_idx
  on wearable_connections(anonymous_user_id, status);

create table if not exists wearable_feature_snapshots (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  connection_id uuid references wearable_connections(id) on delete set null,
  provider text not null,
  period_start timestamptz,
  period_end timestamptz,
  common_features jsonb not null default '{}',
  provider_features jsonb not null default '{}',
  source_confidence jsonb not null default '{}',
  freshness jsonb not null default '{}',
  raw_samples_sent boolean not null default false,
  sync_kind text not null default 'incremental',
  created_at timestamptz not null default now(),
  constraint wearable_feature_snapshots_provider_check
    check (provider in ('apple_health', 'health_connect', 'oura', 'whoop', 'garmin', 'fitbit_google_health', 'withings')),
  constraint wearable_feature_snapshots_sync_kind_check
    check (sync_kind in ('initial_30d', 'incremental', 'manual_refresh'))
);

create index if not exists wearable_feature_snapshots_user_created_idx
  on wearable_feature_snapshots(anonymous_user_id, created_at desc);

create index if not exists wearable_feature_snapshots_common_gin_idx
  on wearable_feature_snapshots using gin(common_features);

create table if not exists wearable_recommendation_outcomes (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  provider text,
  signal_type text,
  recommendation_id text,
  action_kind text not null,
  outcome text not null,
  confidence integer,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  constraint wearable_recommendation_outcomes_provider_check
    check (provider is null or provider in ('apple_health', 'health_connect', 'oura', 'whoop', 'garmin', 'fitbit_google_health', 'withings')),
  constraint wearable_recommendation_outcomes_action_kind_check
    check (action_kind in ('recovery_mode', 'sleep_boundary', 'preventive_block', 'morning_report', 'source_connect', 'other')),
  constraint wearable_recommendation_outcomes_outcome_check
    check (outcome in ('generated', 'accepted', 'ignored', 'dismissed', 'completed', 'failed'))
);

create index if not exists wearable_recommendation_outcomes_user_created_idx
  on wearable_recommendation_outcomes(anonymous_user_id, created_at desc);

create index if not exists wearable_recommendation_outcomes_metadata_gin_idx
  on wearable_recommendation_outcomes using gin(metadata);

alter table wearable_connections enable row level security;
alter table wearable_feature_snapshots enable row level security;
alter table wearable_recommendation_outcomes enable row level security;
