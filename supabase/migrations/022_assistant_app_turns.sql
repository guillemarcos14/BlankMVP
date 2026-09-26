create table if not exists public.assistant_app_turns (
  id uuid primary key,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  user_text text not null check (char_length(user_text) between 1 and 4000),
  assistant_text text,
  action_id text,
  action_label text,
  status text not null default 'processing' check (status in ('processing', 'completed', 'failed')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint assistant_app_turns_reply_check check (
    (status = 'completed' and assistant_text is not null and completed_at is not null)
    or status <> 'completed'
  )
);

create index if not exists assistant_app_turns_user_created_idx
  on public.assistant_app_turns(auth_user_id, created_at desc);

alter table public.assistant_app_turns enable row level security;
revoke all on public.assistant_app_turns from public, anon, authenticated;
grant select, insert, update on public.assistant_app_turns to service_role;
