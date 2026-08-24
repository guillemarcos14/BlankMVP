create table if not exists digital_wellness_feature_payloads (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  schema_version integer not null default 1,
  period_start timestamptz,
  period_end timestamptz,
  payload jsonb not null,
  insight jsonb not null,
  platform text not null default 'ios',
  locale text,
  app_version text,
  build_number text,
  data_consent boolean not null default false,
  consent_text text,
  privacy_raw_health_samples_sent boolean,
  privacy_raw_sleep_stage_timestamps_sent boolean,
  privacy_exact_app_selection_sent boolean,
  privacy_exact_location_sent boolean,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists digital_wellness_feature_payloads_user_idx
  on digital_wellness_feature_payloads(anonymous_user_id);

create index if not exists digital_wellness_feature_payloads_submitted_idx
  on digital_wellness_feature_payloads(submitted_at desc);

create index if not exists digital_wellness_feature_payloads_payload_gin_idx
  on digital_wellness_feature_payloads using gin(payload);

alter table digital_wellness_feature_payloads enable row level security;
