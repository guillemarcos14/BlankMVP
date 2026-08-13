create table if not exists onboarding_responses (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null unique,
  name text,
  age_range text,
  goal text,
  profile text,
  daily_hours numeric(4, 1),
  ai_goal text,
  weak_moment text,
  selected_plan text,
  locale text,
  app_version text,
  build_number text,
  platform text not null default 'ios',
  data_consent boolean not null default false,
  consent_text text,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists onboarding_responses_user_idx on onboarding_responses(anonymous_user_id);
create index if not exists onboarding_responses_submitted_idx on onboarding_responses(submitted_at desc);
