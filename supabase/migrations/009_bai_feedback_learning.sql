alter table bai_user_plan_outcomes
  drop constraint if exists bai_user_plan_outcomes_outcome_check;

alter table bai_user_plan_outcomes
  add constraint bai_user_plan_outcomes_outcome_check
  check (outcome in (
    'generated',
    'accepted',
    'activated',
    'edited',
    'cancelled',
    'ignored',
    'dismissed',
    'completed',
    'failed',
    'broke',
    'held',
    'relapse_after',
    'improved_after'
  ));

create table if not exists bai_recommendation_feedback (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  segment_key text not null,
  pattern_key text not null,
  recommendation_kind text not null,
  recommendation_id text,
  proposed_value jsonb not null default '{}',
  feedback_type text not null,
  user_note text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  constraint bai_recommendation_feedback_type_check
    check (feedback_type in ('helpful', 'not_helpful', 'too_strict', 'too_soft', 'wrong_context', 'good_recommendation'))
);

create index if not exists bai_recommendation_feedback_user_created_idx
  on bai_recommendation_feedback(anonymous_user_id, created_at desc);

create index if not exists bai_recommendation_feedback_pattern_idx
  on bai_recommendation_feedback(pattern_key, recommendation_kind, feedback_type, created_at desc);

create table if not exists bai_user_memory_signals (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  signal_type text not null,
  signal_value text not null,
  confidence integer not null default 35,
  source text not null default 'feedback',
  recommendation_id text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bai_user_memory_signals_confidence_check
    check (confidence between 0 and 100)
);

create unique index if not exists bai_user_memory_signals_unique_idx
  on bai_user_memory_signals(anonymous_user_id, signal_type, signal_value);

create index if not exists bai_user_memory_signals_user_updated_idx
  on bai_user_memory_signals(anonymous_user_id, updated_at desc);

create or replace view bai_learning_dashboard as
select
  coalesce(o.segment_key, f.segment_key) as segment_key,
  coalesce(o.pattern_key, f.pattern_key) as pattern_key,
  coalesce(o.recommendation_kind, f.recommendation_kind) as recommendation_kind,
  count(distinct o.id) as outcome_count,
  count(distinct f.id) as feedback_count,
  count(distinct o.id) filter (where o.outcome in ('accepted', 'activated', 'completed', 'held', 'improved_after')) as positive_count,
  count(distinct o.id) filter (where o.outcome in ('ignored', 'dismissed', 'failed', 'broke', 'cancelled', 'relapse_after')) as negative_count,
  count(distinct f.id) filter (where f.feedback_type = 'too_strict') as too_strict_count,
  count(distinct f.id) filter (where f.feedback_type = 'too_soft') as too_soft_count,
  count(distinct f.id) filter (where f.feedback_type = 'wrong_context') as wrong_context_count,
  greatest(count(distinct o.id), count(distinct f.id)) as sample_size,
  max(greatest(coalesce(o.created_at, 'epoch'::timestamptz), coalesce(f.created_at, 'epoch'::timestamptz))) as last_seen_at
from bai_user_plan_outcomes o
full outer join bai_recommendation_feedback f
  on o.recommendation_id is not null
  and f.recommendation_id is not null
  and o.recommendation_id = f.recommendation_id
group by 1, 2, 3;

alter table bai_recommendation_feedback enable row level security;
alter table bai_user_memory_signals enable row level security;
