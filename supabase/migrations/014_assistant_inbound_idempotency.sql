create table if not exists assistant_inbound_messages (
  id uuid primary key default gen_random_uuid(),
  anonymous_user_id text not null,
  channel text not null,
  message_id text not null,
  status text not null default 'processing',
  claimed_at timestamptz not null default now(),
  lease_expires_at timestamptz not null default (now() + interval '5 minutes'),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint assistant_inbound_messages_channel_check check (channel in ('whatsapp', 'sms')),
  constraint assistant_inbound_messages_status_check check (status in ('processing', 'completed')),
  constraint assistant_inbound_messages_identity_key unique (anonymous_user_id, message_id)
);

create index if not exists assistant_inbound_messages_lease_idx
  on assistant_inbound_messages(lease_expires_at)
  where status = 'processing';

alter table assistant_inbound_messages enable row level security;

create or replace function claim_assistant_inbound_message(
  p_anonymous_user_id text,
  p_channel text,
  p_message_id text,
  p_lease_seconds integer default 300
)
returns table(claimed boolean, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  lease_seconds integer := greatest(30, least(coalesce(p_lease_seconds, 300), 3600));
begin
  if nullif(trim(p_anonymous_user_id), '') is null
    or p_channel is null
    or p_channel not in ('whatsapp', 'sms')
    or nullif(trim(p_message_id), '') is null then
    return query select false, 'invalid';
    return;
  end if;

  insert into assistant_inbound_messages (
    anonymous_user_id, channel, message_id, claimed_at, lease_expires_at
  ) values (
    trim(p_anonymous_user_id), p_channel, trim(p_message_id), now(), now() + make_interval(secs => lease_seconds)
  )
  on conflict (anonymous_user_id, message_id) do nothing;

  if found then
    return query select true, 'claimed';
    return;
  end if;

  update assistant_inbound_messages
  set claimed_at = now(),
      lease_expires_at = now() + make_interval(secs => lease_seconds)
  where anonymous_user_id = trim(p_anonymous_user_id)
    and message_id = trim(p_message_id)
    and status = 'processing'
    and lease_expires_at <= now();

  if found then
    return query select true, 'reclaimed';
    return;
  end if;

  return query select false, 'duplicate';
end;
$$;

create or replace function complete_assistant_inbound_message(
  p_anonymous_user_id text,
  p_message_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update assistant_inbound_messages
  set status = 'completed',
      completed_at = now(),
      lease_expires_at = now()
  where anonymous_user_id = trim(p_anonymous_user_id)
    and message_id = trim(p_message_id)
    and status = 'processing';
  return found;
end;
$$;

revoke all on function claim_assistant_inbound_message(text, text, text, integer) from public, anon, authenticated;
revoke all on function complete_assistant_inbound_message(text, text) from public, anon, authenticated;
grant execute on function claim_assistant_inbound_message(text, text, text, integer) to service_role;
grant execute on function complete_assistant_inbound_message(text, text) to service_role;
