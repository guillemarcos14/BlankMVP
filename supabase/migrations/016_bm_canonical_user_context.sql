-- One durable namespace for app, account and assistant data.
alter table public.blankmind_identity_links
  add column if not exists anonymous_user_id text;

create unique index if not exists blankmind_identity_links_anonymous_user_idx
  on public.blankmind_identity_links(anonymous_user_id)
  where anonymous_user_id is not null;

update public.blankmind_identity_links identity
set anonymous_user_id = privacy.anonymous_user_id,
    updated_at = now()
from public.privacy_user_links privacy
where privacy.auth_user_id = identity.auth_user_id
  and identity.anonymous_user_id is null;

create table if not exists public.bm_user_context_snapshots (
  user_id uuid primary key references public.blankmind_identity_links(auth_user_id) on delete cascade,
  anonymous_user_id text,
  context jsonb not null default '{}',
  context_version bigint not null default 1,
  source text not null default 'app',
  updated_at timestamptz not null default now()
);

create index if not exists bm_user_context_snapshots_anonymous_idx
  on public.bm_user_context_snapshots(anonymous_user_id);

alter table public.bm_user_context_snapshots enable row level security;
revoke all on public.bm_user_context_snapshots from public, anon, authenticated;
grant select, insert, update, delete on public.bm_user_context_snapshots to service_role;
grant delete on public.assistant_semantic_conversations to service_role;

create or replace function public.upsert_bm_user_context(
  p_connect_code text,
  p_anonymous_user_id text,
  p_context jsonb,
  p_source text default 'app'
) returns table(user_id uuid, context_version bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  resolved_identity public.blankmind_identity_links%rowtype;
begin
  select * into resolved_identity
  from public.blankmind_identity_links
  where assistant_connect_code = p_connect_code
  for update;

  if resolved_identity.auth_user_id is null then
    raise exception 'bm_identity_not_found';
  end if;
  if resolved_identity.anonymous_user_id is not null
     and p_anonymous_user_id is not null
     and resolved_identity.anonymous_user_id <> p_anonymous_user_id then
    raise exception 'bm_anonymous_identity_conflict';
  end if;

  if p_anonymous_user_id is not null and resolved_identity.anonymous_user_id is null then
    update public.blankmind_identity_links
    set anonymous_user_id = p_anonymous_user_id, updated_at = now()
    where auth_user_id = resolved_identity.auth_user_id;
  end if;

  insert into public.bm_user_context_snapshots(user_id, anonymous_user_id, context, source)
  values (resolved_identity.auth_user_id, coalesce(p_anonymous_user_id, resolved_identity.anonymous_user_id), p_context, p_source)
  on conflict (user_id) do update
  set anonymous_user_id = coalesce(excluded.anonymous_user_id, bm_user_context_snapshots.anonymous_user_id),
      context = excluded.context,
      context_version = bm_user_context_snapshots.context_version + 1,
      source = excluded.source,
      updated_at = now();

  return query
  select snapshot.user_id, snapshot.context_version
  from public.bm_user_context_snapshots snapshot
  where snapshot.user_id = resolved_identity.auth_user_id;
end;
$$;

revoke all on function public.upsert_bm_user_context(text, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.upsert_bm_user_context(text, text, jsonb, text) to service_role;
