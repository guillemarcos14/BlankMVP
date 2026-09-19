-- Temporary Early Access namespace. It is intentionally isolated from BM Final.
create table if not exists public.waitlist_users (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  phone_e164 text not null unique,
  status text not null default 'active',
  data_consent boolean not null default false,
  whatsapp_consent boolean not null default false,
  consented_at timestamptz,
  opening_first_sent_at timestamptz,
  opening_second_sent_at timestamptz,
  opening_sent_at timestamptz,
  first_reply_at timestamptz,
  profile_useful_at timestamptz,
  deletion_requested_at timestamptz,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint waitlist_users_phone_check check (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  constraint waitlist_users_status_check check (status in ('active', 'paused', 'withdrawn'))
);

create table if not exists public.waitlist_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.waitlist_users(id) on delete cascade,
  provider text not null,
  provider_message_id text,
  direction text not null,
  message_kind text not null default 'text',
  body text not null default '',
  source_language text,
  created_at timestamptz not null default now(),
  constraint waitlist_messages_provider_check check (provider in ('meta', 'twilio', 'web', 'system')),
  constraint waitlist_messages_direction_check check (direction in ('inbound', 'outbound', 'system')),
  constraint waitlist_messages_kind_check check (message_kind in ('text', 'audio_transcript', 'opening', 'privacy')),
  constraint waitlist_messages_provider_id_key unique (provider, provider_message_id)
);

create index if not exists waitlist_messages_user_created_idx
  on public.waitlist_messages(user_id, created_at desc);

create table if not exists public.waitlist_facts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.waitlist_users(id) on delete cascade,
  field_key text not null,
  value jsonb not null,
  normalized_text text,
  source_message_id uuid references public.waitlist_messages(id) on delete set null,
  evidence_excerpt text not null default '',
  confidence numeric(4,3) not null default 1,
  status text not null default 'confirmed',
  supersedes_fact_id uuid references public.waitlist_facts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint waitlist_facts_confidence_check check (confidence >= 0 and confidence <= 1),
  constraint waitlist_facts_status_check check (status in ('confirmed', 'uncertain', 'superseded', 'rejected'))
);

create index if not exists waitlist_facts_current_idx
  on public.waitlist_facts(user_id, field_key, created_at desc)
  where status in ('confirmed', 'uncertain');

create table if not exists public.waitlist_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.waitlist_users(id) on delete cascade,
  event_name text not null,
  properties jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists waitlist_events_user_created_idx
  on public.waitlist_events(user_id, created_at desc);

create table if not exists public.waitlist_inbound_claims (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_message_id text not null,
  status text not null default 'processing',
  claimed_at timestamptz not null default now(),
  lease_expires_at timestamptz not null default (now() + interval '5 minutes'),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint waitlist_claims_provider_check check (provider in ('meta', 'twilio')),
  constraint waitlist_claims_status_check check (status in ('processing', 'completed')),
  constraint waitlist_claims_provider_message_key unique (provider, provider_message_id)
);

create index if not exists waitlist_inbound_claims_lease_idx
  on public.waitlist_inbound_claims(lease_expires_at)
  where status = 'processing';

alter table public.waitlist_users enable row level security;
alter table public.waitlist_messages enable row level security;
alter table public.waitlist_facts enable row level security;
alter table public.waitlist_events enable row level security;
alter table public.waitlist_inbound_claims enable row level security;

revoke all on public.waitlist_users from public, anon, authenticated;
revoke all on public.waitlist_messages from public, anon, authenticated;
revoke all on public.waitlist_facts from public, anon, authenticated;
revoke all on public.waitlist_events from public, anon, authenticated;
revoke all on public.waitlist_inbound_claims from public, anon, authenticated;

grant select, insert, update, delete on public.waitlist_users to service_role;
grant select, insert, update, delete on public.waitlist_messages to service_role;
grant select, insert, update, delete on public.waitlist_facts to service_role;
grant select, insert, update, delete on public.waitlist_events to service_role;
grant select, insert, update, delete on public.waitlist_inbound_claims to service_role;

create or replace function public.claim_waitlist_inbound(
  p_provider text,
  p_provider_message_id text,
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
  if p_provider not in ('meta', 'twilio')
     or nullif(trim(p_provider_message_id), '') is null then
    return query select false, 'invalid';
    return;
  end if;

  insert into public.waitlist_inbound_claims(provider, provider_message_id, lease_expires_at)
  values (p_provider, trim(p_provider_message_id), now() + make_interval(secs => lease_seconds))
  on conflict (provider, provider_message_id) do nothing;

  if found then
    return query select true, 'claimed';
    return;
  end if;

  update public.waitlist_inbound_claims
  set claimed_at = now(),
      lease_expires_at = now() + make_interval(secs => lease_seconds)
  where provider = p_provider
    and provider_message_id = trim(p_provider_message_id)
    and waitlist_inbound_claims.status = 'processing'
    and waitlist_inbound_claims.lease_expires_at <= now();

  if found then
    return query select true, 'reclaimed';
    return;
  end if;

  return query select false, 'duplicate';
end;
$$;

create or replace function public.complete_waitlist_inbound(
  p_provider text,
  p_provider_message_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.waitlist_inbound_claims
  set status = 'completed',
      completed_at = now(),
      lease_expires_at = now()
  where provider = p_provider
    and provider_message_id = trim(p_provider_message_id)
    and status = 'processing';
  return found;
end;
$$;

create or replace function public.release_waitlist_inbound(
  p_provider text,
  p_provider_message_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.waitlist_inbound_claims
  set lease_expires_at = now()
  where provider = p_provider
    and provider_message_id = trim(p_provider_message_id)
    and status = 'processing';
  return found;
end;
$$;

revoke all on function public.claim_waitlist_inbound(text, text, integer) from public, anon, authenticated;
revoke all on function public.complete_waitlist_inbound(text, text) from public, anon, authenticated;
revoke all on function public.release_waitlist_inbound(text, text) from public, anon, authenticated;
grant execute on function public.claim_waitlist_inbound(text, text, integer) to service_role;
grant execute on function public.complete_waitlist_inbound(text, text) to service_role;
grant execute on function public.release_waitlist_inbound(text, text) to service_role;

create or replace view public.waitlist_current_profile
with (security_invoker = true)
as
select
  users.id as user_id,
  users.auth_user_id,
  users.phone_e164,
  users.status,
  users.consented_at,
  users.profile_useful_at,
  coalesce(
    jsonb_object_agg(facts.field_key, facts.value order by facts.created_at)
      filter (where facts.field_key is not null),
    '{}'::jsonb
  ) as profile
from public.waitlist_users users
left join public.waitlist_facts facts
  on facts.user_id = users.id
 and facts.status = 'confirmed'
group by users.id;

revoke all on public.waitlist_current_profile from public, anon, authenticated;
grant select on public.waitlist_current_profile to service_role;
