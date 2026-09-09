alter table wearable_connections
  drop constraint if exists wearable_connections_provider_check;

alter table wearable_connections
  add constraint wearable_connections_provider_check
  check (provider in ('apple_health', 'health_connect', 'oura', 'whoop', 'garmin', 'fitbit_google_health', 'withings', 'strava'));

alter table wearable_feature_snapshots
  drop constraint if exists wearable_feature_snapshots_provider_check;

alter table wearable_feature_snapshots
  add constraint wearable_feature_snapshots_provider_check
  check (provider in ('apple_health', 'health_connect', 'oura', 'whoop', 'garmin', 'fitbit_google_health', 'withings', 'strava'));

alter table wearable_recommendation_outcomes
  drop constraint if exists wearable_recommendation_outcomes_provider_check;

alter table wearable_recommendation_outcomes
  add constraint wearable_recommendation_outcomes_provider_check
  check (provider is null or provider in ('apple_health', 'health_connect', 'oura', 'whoop', 'garmin', 'fitbit_google_health', 'withings', 'strava'));

create table if not exists wellness_signal_events (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  signal_type text not null,
  value_number numeric,
  value_text text,
  source text not null default 'app',
  metadata jsonb not null default '{}',
  measured_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint wellness_signal_events_type_check
    check (signal_type in ('mood', 'energy', 'stress', 'caffeine', 'alcohol', 'sick', 'meditation', 'weather_context'))
);

create index if not exists wellness_signal_events_user_measured_idx
  on wellness_signal_events(anonymous_user_id, measured_at desc);

create index if not exists wellness_signal_events_type_idx
  on wellness_signal_events(signal_type, measured_at desc);

create index if not exists wellness_signal_events_metadata_gin_idx
  on wellness_signal_events using gin(metadata);

alter table wellness_signal_events enable row level security;
