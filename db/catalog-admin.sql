-- Applied through Supabase apply_migration: otaku_catalog_admin.
-- Only OTAKU LIVE catalog objects are changed. Shared Auth and other apps are untouched.
create table public.otaku_catalog_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.otaku_catalog_admins enable row level security;
revoke all on public.otaku_catalog_admins from anon, authenticated;
grant select on public.otaku_catalog_admins to anon, authenticated;
create policy "otaku admins read own membership" on public.otaku_catalog_admins
  for select to authenticated using (user_id = (select auth.uid()));

create function public.otaku_is_catalog_admin() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists(select 1 from public.otaku_catalog_admins where user_id = (select auth.uid()));
$$;
revoke all on function public.otaku_is_catalog_admin() from public;
grant execute on function public.otaku_is_catalog_admin() to anon, authenticated;

create table public.otaku_catalog_audit (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  table_name text not null,
  record_id uuid not null,
  before_data jsonb,
  after_data jsonb not null,
  changed_at timestamptz not null default now()
);
alter table public.otaku_catalog_audit enable row level security;
revoke all on public.otaku_catalog_audit from anon, authenticated;
grant select on public.otaku_catalog_audit to authenticated;
create policy "otaku admins read catalog audit" on public.otaku_catalog_audit
  for select to authenticated using ((select public.otaku_is_catalog_admin()));

alter table public.otaku_idol_groups add column source_url text;
alter table public.otaku_idols add column source_url text;
alter table public.otaku_idols add column updated_at timestamptz not null default now();
do $$ declare t text; begin
  foreach t in array array['otaku_idol_groups','otaku_idols','otaku_events'] loop
    execute format('alter table public.%I add column is_demo boolean not null default false,
      add column publication_status text not null default ''draft'' check (publication_status in (''draft'',''published'',''archived'')),
      add column source_checked_at timestamptz,
      add column source_kind text check (source_kind in (''official'',''organizer'',''venue'',''ticketing'')),
      add column revision integer not null default 1', t);
  end loop;
end $$;
-- Only known seed groups and their existing children are classified as DEMO.
update public.otaku_idol_groups set is_demo=true, publication_status='published'
  where slug in ('demo-idol','neon-stars','sample48');
update public.otaku_idols set is_demo=true, publication_status='published'
  where group_id in (select id from public.otaku_idol_groups where is_demo);
update public.otaku_events set is_demo=true, publication_status='published'
  where group_id in (select id from public.otaku_idol_groups where is_demo) and title like '【DEMO】%';

create unique index otaku_groups_normalized_name on public.otaku_idol_groups (is_demo, lower(btrim(name)));
create unique index otaku_idols_normalized_name on public.otaku_idols (group_id, lower(btrim(name)));
create unique index otaku_events_identity on public.otaku_events
  (group_id, starts_at, lower(btrim(venue)), lower(btrim(title)));

create schema if not exists otaku_private;
revoke all on schema otaku_private from public, anon, authenticated;

create function otaku_private.validate_catalog() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare parent_demo boolean; parent_status text;
begin
  if TG_OP = 'UPDATE' then
    if new.id <> old.id or new.is_demo <> old.is_demo then
      raise exception 'catalog_identity_immutable' using errcode='23514';
    end if;
    new.revision := old.revision + 1;
  else new.revision := 1;
  end if;
  new.updated_at := now();
  if TG_TABLE_NAME = 'otaku_events' then
    new.title := btrim(new.title); new.venue := btrim(new.venue);
    if new.title = '' or new.venue = '' then raise exception 'catalog_name_required' using errcode='23514'; end if;
    if not isfinite(new.starts_at) or (new.ends_at is not null and not isfinite(new.ends_at)) then
      raise exception 'catalog_invalid_date' using errcode='23514';
    end if;
  else
    new.name := btrim(new.name);
    if new.name = '' then raise exception 'catalog_name_required' using errcode='23514'; end if;
  end if;
  if new.source_url is not null and (
    length(new.source_url) > 2048 or new.source_url !~ '^https://[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+(/[!-~]*)?$'
    or new.source_url ~ '[<>"''\\]'
  ) then raise exception 'catalog_invalid_source_url' using errcode='23514'; end if;
  if new.source_checked_at > now() or (new.source_checked_at is not null and not isfinite(new.source_checked_at)) then raise exception 'catalog_future_verification' using errcode='23514'; end if;
  if not new.is_demo and new.publication_status = 'published' and
    (new.source_url is null or new.source_kind is null or new.source_checked_at is null) then
    raise exception 'catalog_source_required' using errcode='23514';
  end if;
  if TG_TABLE_NAME <> 'otaku_idol_groups' then
    if new.group_id is null then raise exception 'catalog_group_required' using errcode='23514'; end if;
    select is_demo, publication_status into parent_demo, parent_status
      from public.otaku_idol_groups where id = new.group_id for share;
    if not found or parent_demo <> new.is_demo then
      raise exception 'catalog_group_type_mismatch' using errcode='23514';
    end if;
    if new.publication_status = 'published' and parent_status <> 'published' then
      raise exception 'catalog_publish_group_first' using errcode='23514';
    end if;
  elsif TG_OP = 'UPDATE' and new.publication_status <> 'published' and old.publication_status = 'published' then
    if exists(select 1 from public.otaku_idols where group_id = new.id and publication_status='published')
      or exists(select 1 from public.otaku_events where group_id = new.id and publication_status='published') then
      raise exception 'catalog_unpublish_children_first' using errcode='23514';
    end if;
  end if;
  return new;
end $$;

-- Definer is limited to appending audit rows; no caller receives write access to audit.
create function otaku_private.audit_catalog() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.otaku_catalog_admins where user_id=auth.uid()) then
    raise exception 'catalog_admin_required' using errcode='42501';
  end if;
  insert into public.otaku_catalog_audit(actor_id,table_name,record_id,before_data,after_data)
    values(auth.uid(),TG_TABLE_NAME,new.id,case when TG_OP='UPDATE' then to_jsonb(old) else null end,to_jsonb(new));
  return new;
end $$;
revoke all on function otaku_private.validate_catalog() from public, anon, authenticated;
revoke all on function otaku_private.audit_catalog() from public, anon, authenticated;

drop policy "otaku public groups readable" on public.otaku_idol_groups;
drop policy "otaku public idols readable" on public.otaku_idols;
drop policy "otaku public events readable" on public.otaku_events;
do $$ declare t text; begin
  foreach t in array array['otaku_idol_groups','otaku_idols','otaku_events'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select on public.%I to anon, authenticated',t);
    execute format('grant insert, update on public.%I to authenticated',t);
    execute format('create policy "otaku published catalog readable" on public.%I for select to anon, authenticated using (publication_status = ''published'' or (select public.otaku_is_catalog_admin()))',t);
    execute format('create policy "otaku admins insert catalog" on public.%I for insert to authenticated with check ((select public.otaku_is_catalog_admin()))',t);
    execute format('create policy "otaku admins update catalog" on public.%I for update to authenticated using ((select public.otaku_is_catalog_admin())) with check ((select public.otaku_is_catalog_admin()))',t);
    execute format('create trigger otaku_catalog_validate before insert or update on public.%I for each row execute function otaku_private.validate_catalog()',t);
    execute format('create trigger otaku_catalog_audit after insert or update on public.%I for each row execute function otaku_private.audit_catalog()',t);
  end loop;
end $$;
