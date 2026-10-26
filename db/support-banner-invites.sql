-- Migration: otaku_support_banner_invites
-- Invite links for support-banner eligibility. Private rows are only accessed through
-- SECURITY DEFINER functions; authenticated users cannot read either table directly.

create table otaku_private.invites (
  user_id uuid primary key references public.otaku_profiles(id) on delete cascade,
  code text not null unique check (code ~ '^[a-z0-9]{10}$'),
  created_at timestamptz not null default now()
);
alter table otaku_private.invites enable row level security;
revoke all on otaku_private.invites from public, anon, authenticated;

create table otaku_private.invite_signups (
  invitee_id uuid primary key references public.otaku_profiles(id) on delete cascade,
  inviter_id uuid not null references public.otaku_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (invitee_id <> inviter_id)
);
create index invite_signups_inviter_created_idx
  on otaku_private.invite_signups(inviter_id, created_at desc);
alter table otaku_private.invite_signups enable row level security;
revoke all on otaku_private.invite_signups from public, anon, authenticated;

create or replace function public.otaku_my_invite_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  invite_code text;
  attempt integer;
begin
  if uid is null then raise exception 'not_allowed' using errcode = '42501'; end if;

  select i.code into invite_code from otaku_private.invites i where i.user_id = uid;
  if invite_code is not null then return invite_code; end if;

  for attempt in 1..5 loop
    invite_code := lower(encode(extensions.gen_random_bytes(5), 'hex'));
    begin
      insert into otaku_private.invites(user_id, code) values (uid, invite_code);
      return invite_code;
    exception when unique_violation then
      select i.code into invite_code from otaku_private.invites i where i.user_id = uid;
      if invite_code is not null then return invite_code; end if;
    end;
  end loop;

  raise exception 'invite_code_unavailable';
end;
$$;
revoke all on function public.otaku_my_invite_code() from public, anon, authenticated;
grant execute on function public.otaku_my_invite_code() to authenticated;

create or replace function public.otaku_claim_invite(invite_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  inviter uuid;
  profile_created_at timestamptz;
begin
  if uid is null then raise exception 'not_allowed' using errcode = '42501'; end if;

  select p.created_at into profile_created_at from public.otaku_profiles p where p.id = uid;
  if profile_created_at is null then return 'not_ready'; end if;

  if invite_code is null or invite_code !~ '^[a-z0-9]{10}$' then return 'invalid'; end if;
  select i.user_id into inviter from otaku_private.invites i where i.code = invite_code;
  if inviter is null or inviter = uid then return 'invalid'; end if;
  if exists (select 1 from otaku_private.invite_signups s where s.invitee_id = uid) then return 'already'; end if;
  if profile_created_at < now() - interval '7 days' then return 'too_late'; end if;

  insert into otaku_private.invite_signups(invitee_id, inviter_id)
  values (uid, inviter)
  on conflict (invitee_id) do nothing;
  if not found then return 'already'; end if;
  return 'ok';
end;
$$;
revoke all on function public.otaku_claim_invite(text) from public, anon, authenticated;
grant execute on function public.otaku_claim_invite(text) to authenticated;

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
  invites integer;
  active boolean;
  last_shown date;
begin
  select count(*) into attendance from public.otaku_event_attendees
    where user_id = uid and created_at >= now() - interval '60 days';
  select count(*) into records from public.otaku_event_records
    where user_id = uid and not hidden and created_at >= now() - interval '60 days';
  select count(*) into invites from otaku_private.invite_signups s
    where s.inviter_id = uid and s.created_at >= now() - interval '60 days'
      and (exists (select 1 from public.otaku_event_attendees a where a.user_id = s.invitee_id)
        or exists (select 1 from public.otaku_event_records r where r.user_id = s.invitee_id and not r.hidden));
  select exists (select 1 from public.otaku_support_banners
    where user_id = uid and (status = 'pending' or (status = 'approved' and show_on >= today))) into active;
  select max(show_on) into last_shown from public.otaku_support_banners
    where user_id = uid and status = 'approved' and show_on < today and show_on >= today - 30;
  return jsonb_build_object(
    'eligible', (attendance >= 3 or records >= 1 or invites >= 1) and not active and last_shown is null,
    'attendance_count', attendance,
    'record_count', records,
    'invite_count', invites,
    'has_active', active,
    'cooldown_until', case when last_shown is null then null else last_shown + 31 end
  );
end;
$$;
revoke all on function otaku_private.support_banner_eligibility(uuid) from public, anon, authenticated;

-- Rollback:
-- Restore otaku_private.support_banner_eligibility(uuid) from db/support-banners.sql.
-- drop function if exists public.otaku_claim_invite(text);
-- drop function if exists public.otaku_my_invite_code();
-- drop table if exists otaku_private.invite_signups;
-- drop table if exists otaku_private.invites;
