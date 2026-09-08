create table if not exists bai_learning_changes (
  id uuid primary key default gen_random_uuid(),
  change_key text not null unique,
  scope text not null default 'user',
  anonymous_user_id text,
  segment_key text,
  pattern_key text,
  recommendation_kind text,
  change_type text not null,
  title text not null,
  summary text not null,
  reason text not null,
  evidence jsonb not null default '{}',
  impact jsonb not null default '{}',
  previous_value jsonb not null default '{}',
  new_value jsonb not null default '{}',
  autonomous_apply boolean not null default true,
  reversible boolean not null default true,
  severity text not null default 'info',
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  constraint bai_learning_changes_scope_check
    check (scope in ('user', 'segment', 'global')),
  constraint bai_learning_changes_type_check
    check (change_type in ('decision_source_changed', 'recommendation_changed', 'personal_override', 'exploration_started', 'pattern_promoted')),
  constraint bai_learning_changes_severity_check
    check (severity in ('info', 'notice', 'important')),
  constraint bai_learning_changes_status_check
    check (status in ('pending', 'reviewed', 'reverted', 'dismissed'))
);

create index if not exists bai_learning_changes_status_created_idx
  on bai_learning_changes(status, created_at desc);

create index if not exists bai_learning_changes_user_created_idx
  on bai_learning_changes(anonymous_user_id, created_at desc);

create index if not exists bai_learning_changes_segment_pattern_idx
  on bai_learning_changes(segment_key, pattern_key, recommendation_kind, created_at desc);

create index if not exists bai_learning_changes_evidence_gin_idx
  on bai_learning_changes using gin(evidence);

alter table bai_learning_changes enable row level security;
