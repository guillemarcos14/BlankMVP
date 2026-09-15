-- Dedicated conversation state. Compare-and-swap prevents two different inbound
-- messages from overwriting each other's semantic corrections.
create table if not exists public.assistant_semantic_conversations (
  anonymous_user_id text primary key check (anonymous_user_id ~ '^assistant:[a-f0-9]{32}$'),
  channel text not null check (channel in ('whatsapp', 'sms')),
  storage_version bigint not null default 0 check (storage_version >= 0),
  state jsonb not null default '{}'::jsonb check (jsonb_typeof(state) = 'object'),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default now()
);

alter table public.assistant_semantic_conversations enable row level security;
revoke all on public.assistant_semantic_conversations from public, anon, authenticated;
grant select, insert, update on public.assistant_semantic_conversations to service_role;

create or replace function public.commit_assistant_semantic_conversation(
  p_anonymous_user_id text,
  p_channel text,
  p_expected_version bigint,
  p_state jsonb,
  p_ttl_seconds integer default 7200
)
returns table(committed boolean, storage_version bigint, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_row public.assistant_semantic_conversations%rowtype;
begin
  if p_anonymous_user_id is null or p_anonymous_user_id !~ '^assistant:[a-f0-9]{32}$'
    or p_channel is null or p_channel not in ('whatsapp', 'sms')
    or p_expected_version is null or p_expected_version < 0
    or p_state is null or jsonb_typeof(p_state) <> 'object'
    or jsonb_typeof(p_state -> 'semantic_state') is distinct from 'object'
    or octet_length(p_state::text) > 65536 then
    return query select false, 0::bigint, 'invalid'::text;
    return;
  end if;

  insert into public.assistant_semantic_conversations (anonymous_user_id, channel)
  values (p_anonymous_user_id, p_channel)
  on conflict (anonymous_user_id) do nothing;

  select * into current_row
  from public.assistant_semantic_conversations c
  where c.anonymous_user_id = p_anonymous_user_id
  for update;

  if current_row.storage_version <> p_expected_version or current_row.channel <> p_channel then
    return query select false, current_row.storage_version, 'conflict'::text;
    return;
  end if;

  update public.assistant_semantic_conversations c
  set state = p_state,
      storage_version = current_row.storage_version + 1,
      updated_at = now(),
      expires_at = now() + make_interval(secs => greatest(60, least(coalesce(p_ttl_seconds, 7200), 7200)))
  where c.anonymous_user_id = p_anonymous_user_id;

  return query select true, current_row.storage_version + 1, 'committed'::text;
end;
$$;

revoke all on function public.commit_assistant_semantic_conversation(text, text, bigint, jsonb, integer) from public, anon, authenticated;
grant execute on function public.commit_assistant_semantic_conversation(text, text, bigint, jsonb, integer) to service_role;

-- A failed CAS has not delivered the reply. Make that provider message reclaimable
-- immediately instead of acknowledging its retry as a duplicate during the lease.
create or replace function public.release_assistant_inbound_message(
  p_anonymous_user_id text, p_message_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.assistant_inbound_messages
  set lease_expires_at = now()
  where anonymous_user_id = p_anonymous_user_id
    and message_id = p_message_id
    and status = 'processing';
  return found;
end;
$$;
revoke all on function public.release_assistant_inbound_message(text, text) from public, anon, authenticated;
grant execute on function public.release_assistant_inbound_message(text, text) to service_role;
