-- Migration: otaku_support_banners
-- Additive only. Support banners: users who attend or record events can ask for a one-day
-- fan message card. Every write goes through SECURITY DEFINER functions; reads are limited by RLS.

create table public.otaku_support_banners (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  group_id uuid not null references public.otaku_idol_groups(id),
  idol_id uuid references public.otaku_idols(id),
  occasion text not null check (occasion in ('birthday','anniversary','event','other')),
  show_on date not null,
  message text not null check (char_length(btrim(message)) between 1 and 40),
  display_mode text not null default 'anonymous' check (display_mode in ('profile','anonymous')),
  status text not null default 'pending' check (status in ('pending','approved','rejected','hidden')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index otaku_support_banners_show_on_idx on public.otaku_support_banners(show_on, status);
create index otaku_support_banners_user_idx on public.otaku_support_banners(user_id, created_at desc);
alter table public.otaku_support_banners enable row level security;
revoke all on public.otaku_support_banners from anon, authenticated;
grant select on public.otaku_support_banners to authenticated;
create policy otaku_support_banners_select on public.otaku_support_banners
  for select to authenticated
  using (user_id = auth.uid() or public.otaku_is_catalog_admin());

create table public.otaku_support_banner_reports (
  id uuid primary key default gen_random_uuid(),
  banner_id uuid not null references public.otaku_support_banners(id) on delete cascade,
  reporter_id uuid not null references public.otaku_profiles(id) on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  created_at timestamptz not null default now(),
  unique (banner_id, reporter_id)
);
alter table public.otaku_support_banner_reports enable row level security;
revoke all on public.otaku_support_banner_reports from anon, authenticated;
grant select on public.otaku_support_banner_reports to authenticated;
create policy otaku_support_banner_reports_select on public.otaku_support_banner_reports
  for select to authenticated
  using (public.otaku_is_catalog_admin());

create or replace function otaku_private.support_banner_eligibility(uid uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  today date := (now() at time zone 'Asia/Tokyo')::date;
  attendance integer;
  records integer;
  active boolean;
  last_shown date;
begin
  select count(*) into attendance from public.otaku_event_attendees
    where user_id = uid and created_at >= now() - interval '60 days';
  select count(*) into records from public.otaku_event_records
    where user_id = uid and not hidden and created_at >= now() - interval '60 days';
  select exists (select 1 from public.otaku_support_banners
    where user_id = uid and (status = 'pending' or (status = 'approved' and show_on >= today))) into active;
  select max(show_on) into last_shown from public.otaku_support_banners
    where user_id = uid and status = 'approved' and show_on < today and show_on >= today - 30;
  return jsonb_build_object(
    'eligible', (attendance >= 3 or records >= 1) and not active and last_shown is null,
    'attendance_count', attendance,
    'record_count', records,
    'has_active', active,
    'cooldown_until', case when last_shown is null then null else last_shown + 31 end
  );
end;
$$;
revoke all on function otaku_private.support_banner_eligibility(uuid) from public, anon, authenticated;

create or replace function public.otaku_support_banner_eligibility()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  return otaku_private.support_banner_eligibility(auth.uid());
end;
$$;
revoke all on function public.otaku_support_banner_eligibility() from public, anon, authenticated;
grant execute on function public.otaku_support_banner_eligibility() to authenticated;

create or replace function public.otaku_submit_support_banner(
  target_group uuid, target_idol uuid, target_occasion text, target_show_on date,
  target_message text, target_display_mode text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Asia/Tokyo')::date;
  body text := btrim(coalesce(target_message, ''));
  new_id uuid;
begin
  if uid is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('otaku-support-banner:' || uid, 0));
  if not exists (select 1 from public.otaku_idol_groups g
      where g.id = target_group and g.publication_status = 'published' and not g.is_demo) then
    raise exception 'banner_invalid_target' using errcode = '23514';
  end if;
  if target_idol is not null and not exists (select 1 from public.otaku_idols i
      where i.id = target_idol and i.group_id = target_group and i.publication_status = 'published' and not i.is_demo) then
    raise exception 'banner_invalid_target' using errcode = '23514';
  end if;
  if target_show_on is null or target_show_on < today or target_show_on > today + 60 then
    raise exception 'banner_invalid_date' using errcode = '23514';
  end if;
  if char_length(body) not between 1 and 40
     or body ~* '(https?://|www\.|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+|\.(com|net|jp|org|io|me)\M|[0-9０-９][0-9０-９\-－]{8,})'
     or coalesce(target_occasion, '') not in ('birthday','anniversary','event','other')
     or coalesce(target_display_mode, '') not in ('profile','anonymous') then
    raise exception 'banner_invalid_message' using errcode = '23514';
  end if;
  if not (otaku_private.support_banner_eligibility(uid) ->> 'eligible')::boolean then
    raise exception 'banner_not_eligible' using errcode = '23514';
  end if;
  insert into public.otaku_support_banners(user_id, group_id, idol_id, occasion, show_on, message, display_mode, status)
  values (uid, target_group, target_idol, target_occasion, target_show_on, body, target_display_mode, 'pending')
  returning id into new_id;
  return new_id;
end;
$$;
revoke all on function public.otaku_submit_support_banner(uuid, uuid, text, date, text, text) from public, anon, authenticated;
grant execute on function public.otaku_submit_support_banner(uuid, uuid, text, date, text, text) to authenticated;

create or replace function public.otaku_review_support_banner(banner_id uuid, decision text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.otaku_is_catalog_admin() then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if coalesce(decision, '') not in ('approved','rejected','hidden') then
    raise exception 'banner_invalid_decision' using errcode = '23514';
  end if;
  update public.otaku_support_banners b
    set status = decision, reviewed_by = auth.uid(), reviewed_at = now()
    where b.id = otaku_review_support_banner.banner_id;
  if not found then raise exception 'banner_not_found' using errcode = '23514'; end if;
end;
$$;
revoke all on function public.otaku_review_support_banner(uuid, text) from public, anon, authenticated;
grant execute on function public.otaku_review_support_banner(uuid, text) to authenticated;

create or replace function public.otaku_todays_support_banners(target_group uuid default null)
returns table(id uuid, group_id uuid, group_name text, idol_name text, occasion text, show_on date, message text, display_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select b.id, b.group_id, g.name, i.name, b.occasion, b.show_on, b.message,
    case when b.display_mode = 'profile' and p.show_display_name and nullif(btrim(p.display_name), '') is not null
      then p.display_name else '匿名のファン' end
  from public.otaku_support_banners b
  join public.otaku_idol_groups g on g.id = b.group_id and g.publication_status = 'published' and not g.is_demo
  join public.otaku_profiles p on p.id = b.user_id
  left join public.otaku_idols i on i.id = b.idol_id
  where b.status = 'approved'
    and b.show_on = (now() at time zone 'Asia/Tokyo')::date
    and (b.idol_id is null or (i.publication_status = 'published' and not i.is_demo))
    and (target_group is null or b.group_id = target_group)
  order by md5(b.id::text || ((now() at time zone 'Asia/Tokyo')::date)::text)
  limit case when target_group is null then 3 else 10 end;
$$;
revoke all on function public.otaku_todays_support_banners(uuid) from public, anon, authenticated;
grant execute on function public.otaku_todays_support_banners(uuid) to anon, authenticated;

create or replace function public.otaku_report_support_banner(banner_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  owner uuid;
begin
  if uid is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('otaku-support-banner-report:' || uid, 0));
  select b.user_id into owner from public.otaku_support_banners b
    where b.id = otaku_report_support_banner.banner_id
      and b.status = 'approved' and b.show_on = (now() at time zone 'Asia/Tokyo')::date;
  if owner is null or owner = uid then raise exception 'report_invalid_context' using errcode = '42501'; end if;
  if (select count(*) from public.otaku_support_banner_reports r
      where r.reporter_id = uid and r.created_at > now() - interval '1 day') >= 20 then
    raise exception 'report_rate_limit' using errcode = '23514';
  end if;
  insert into public.otaku_support_banner_reports(banner_id, reporter_id, reason)
  values (otaku_report_support_banner.banner_id, uid, btrim(coalesce(reason, '')));
  update public.otaku_support_banners b set status = 'hidden'
    where b.id = otaku_report_support_banner.banner_id;
end;
$$;
revoke all on function public.otaku_report_support_banner(uuid, text) from public, anon, authenticated;
grant execute on function public.otaku_report_support_banner(uuid, text) to authenticated;

-- Rollback:
-- drop function if exists public.otaku_report_support_banner(uuid, text);
-- drop function if exists public.otaku_todays_support_banners(uuid);
-- drop function if exists public.otaku_review_support_banner(uuid, text);
-- drop function if exists public.otaku_submit_support_banner(uuid, uuid, text, date, text, text);
-- drop function if exists public.otaku_support_banner_eligibility();
-- drop function if exists otaku_private.support_banner_eligibility(uuid);
-- drop table if exists public.otaku_support_banner_reports;
-- drop table if exists public.otaku_support_banners;
