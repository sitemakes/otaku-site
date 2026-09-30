create table if not exists public.otaku_venue_guides (
  id uuid primary key default gen_random_uuid(),
  venue_name text not null,
  prefecture text,
  city text,
  nearest_station text,
  access_notes text,
  lockers text,
  toilets text,
  convenience_store text,
  meeting_spot text,
  official_url text not null,
  source_checked_at timestamptz not null,
  publication_status text not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references public.otaku_profiles(id),
  constraint otaku_venue_guides_status_check check (publication_status in ('draft','published','archived')),
  constraint otaku_venue_guides_name_check check (char_length(btrim(venue_name)) between 1 and 200),
  constraint otaku_venue_guides_prefecture_check check (prefecture is null or char_length(btrim(prefecture)) between 1 and 100),
  constraint otaku_venue_guides_city_check check (city is null or char_length(btrim(city)) between 1 and 100),
  constraint otaku_venue_guides_station_check check (nearest_station is null or char_length(btrim(nearest_station)) between 1 and 500),
  constraint otaku_venue_guides_access_check check (access_notes is null or char_length(btrim(access_notes)) between 1 and 1000),
  constraint otaku_venue_guides_lockers_check check (lockers is null or char_length(btrim(lockers)) between 1 and 1000),
  constraint otaku_venue_guides_toilets_check check (toilets is null or char_length(btrim(toilets)) between 1 and 1000),
  constraint otaku_venue_guides_store_check check (convenience_store is null or char_length(btrim(convenience_store)) between 1 and 1000),
  constraint otaku_venue_guides_meeting_check check (meeting_spot is null or char_length(btrim(meeting_spot)) between 1 and 1000),
  constraint otaku_venue_guides_url_length_check check (char_length(official_url) <= 2048),
  constraint otaku_venue_guides_url_check check (official_url ~ '^https://[^[:space:]<>"''\\]+$'),
  constraint otaku_venue_guides_checked_check check (source_checked_at <= now())
);
create unique index if not exists otaku_venue_guides_location_unique
  on public.otaku_venue_guides (lower(venue_name), lower(coalesce(prefecture,'')), lower(coalesce(city,'')));
create index if not exists otaku_venue_guides_published_idx
  on public.otaku_venue_guides (publication_status, lower(venue_name));
create index if not exists otaku_venue_guides_updated_by_idx
  on public.otaku_venue_guides (updated_by);

alter table public.otaku_venue_guides enable row level security;
revoke all on public.otaku_venue_guides from public, anon, authenticated;
grant select on public.otaku_venue_guides to anon, authenticated;
grant insert, update, delete on public.otaku_venue_guides to authenticated;

drop policy if exists venue_guides_read on public.otaku_venue_guides;
drop policy if exists venue_guides_anon_read on public.otaku_venue_guides;
drop policy if exists venue_guides_authenticated_read on public.otaku_venue_guides;
drop policy if exists venue_guides_admin_insert on public.otaku_venue_guides;
drop policy if exists venue_guides_admin_update on public.otaku_venue_guides;
drop policy if exists venue_guides_admin_delete on public.otaku_venue_guides;
create policy venue_guides_anon_read on public.otaku_venue_guides
  for select to anon using (publication_status = 'published');
create policy venue_guides_authenticated_read on public.otaku_venue_guides
  for select to authenticated
  using (publication_status = 'published' or (select public.otaku_is_catalog_admin()));
create policy venue_guides_admin_insert on public.otaku_venue_guides
  for insert to authenticated
  with check ((select public.otaku_is_catalog_admin()) and updated_by = (select auth.uid()));
create policy venue_guides_admin_update on public.otaku_venue_guides
  for update to authenticated
  using ((select public.otaku_is_catalog_admin()))
  with check ((select public.otaku_is_catalog_admin()) and updated_by = (select auth.uid()));
create policy venue_guides_admin_delete on public.otaku_venue_guides
  for delete to authenticated using ((select public.otaku_is_catalog_admin()));

create or replace function otaku_private.venue_guide_guard()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  if auth.uid() is null or not public.otaku_is_catalog_admin() then
    raise exception 'venue_guide_not_allowed' using errcode='42501';
  end if;
  new.venue_name := btrim(new.venue_name);
  new.prefecture := nullif(btrim(new.prefecture),'');
  new.city := nullif(btrim(new.city),'');
  new.nearest_station := nullif(btrim(new.nearest_station),'');
  new.access_notes := nullif(btrim(new.access_notes),'');
  new.lockers := nullif(btrim(new.lockers),'');
  new.toilets := nullif(btrim(new.toilets),'');
  new.convenience_store := nullif(btrim(new.convenience_store),'');
  new.meeting_spot := nullif(btrim(new.meeting_spot),'');
  new.official_url := btrim(new.official_url);
  if new.source_checked_at > now() then raise exception 'venue_guide_future_check' using errcode='23514'; end if;
  new.updated_by := auth.uid(); new.updated_at := now();
  if tg_op = 'INSERT' then new.created_at := now(); end if;
  return new;
end $$;
drop trigger if exists otaku_venue_guide_guard on public.otaku_venue_guides;
create trigger otaku_venue_guide_guard before insert or update on public.otaku_venue_guides
for each row execute function otaku_private.venue_guide_guard();
revoke all on function otaku_private.venue_guide_guard() from public, anon, authenticated;
