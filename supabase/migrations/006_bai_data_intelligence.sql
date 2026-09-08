create table if not exists bai_user_plan_outcomes (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  segment_key text not null,
  pattern_key text not null,
  recommendation_kind text not null,
  recommendation_id text,
  proposed_value jsonb not null default '{}',
  outcome text not null,
  outcome_score integer,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  constraint bai_user_plan_outcomes_outcome_check
    check (outcome in ('generated', 'accepted', 'ignored', 'dismissed', 'completed', 'failed', 'broke', 'held')),
  constraint bai_user_plan_outcomes_score_check
    check (outcome_score is null or outcome_score between -100 and 100)
);

create index if not exists bai_user_plan_outcomes_user_created_idx
  on bai_user_plan_outcomes(anonymous_user_id, created_at desc);

create index if not exists bai_user_plan_outcomes_segment_pattern_idx
  on bai_user_plan_outcomes(segment_key, pattern_key, recommendation_kind, created_at desc);

create index if not exists bai_user_plan_outcomes_metadata_gin_idx
  on bai_user_plan_outcomes using gin(metadata);

create table if not exists bai_recommendation_decisions (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  segment_key text not null,
  pattern_key text not null,
  recommendation_kind text not null,
  macro_recommendation jsonb not null default '{}',
  micro_recommendation jsonb not null default '{}',
  final_recommendation jsonb not null default '{}',
  decision_source text not null,
  reason text not null,
  confidence integer not null default 20,
  evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  constraint bai_recommendation_decisions_source_check
    check (decision_source in ('macro', 'micro', 'experiment', 'fallback')),
  constraint bai_recommendation_decisions_confidence_check
    check (confidence between 0 and 100)
);

create index if not exists bai_recommendation_decisions_user_created_idx
  on bai_recommendation_decisions(anonymous_user_id, created_at desc);

create index if not exists bai_recommendation_decisions_segment_pattern_idx
  on bai_recommendation_decisions(segment_key, pattern_key, recommendation_kind, created_at desc);

create or replace view bai_global_plan_patterns as
select
  segment_key,
  pattern_key,
  recommendation_kind,
  proposed_value,
  count(*) filter (where outcome in ('generated')) as generated_count,
  count(*) filter (where outcome in ('accepted', 'completed', 'held')) as positive_count,
  count(*) filter (where outcome in ('ignored', 'dismissed', 'failed', 'broke')) as negative_count,
  count(*) as sample_size,
  round(
    100.0 * count(*) filter (where outcome in ('accepted', 'completed', 'held')) / greatest(count(*), 1),
    1
  ) as positive_rate,
  max(created_at) as last_seen_at
from bai_user_plan_outcomes
group by 1, 2, 3, 4;

create or replace view bai_user_plan_preferences as
select distinct on (anonymous_user_id, pattern_key, recommendation_kind)
  anonymous_user_id,
  pattern_key,
  recommendation_kind,
  proposed_value,
  outcome,
  outcome_score,
  metadata,
  created_at
from bai_user_plan_outcomes
where outcome in ('accepted', 'completed', 'held')
order by anonymous_user_id, pattern_key, recommendation_kind, created_at desc;

alter table bai_user_plan_outcomes enable row level security;
alter table bai_recommendation_decisions enable row level security;
