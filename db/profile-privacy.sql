-- Enforce profile / attendance / oshi visibility settings in the database.
--
-- Before this change otaku_profiles, otaku_event_attendees and
-- otaku_user_favorites were readable in full by every signed-in user, so the
-- show_* settings were only applied by the UI and could be bypassed through
-- the REST API.
--
-- Applied in two migrations so the old frontend keeps working in between:
--   otaku_profile_privacy_additive  (part 1) -> deploy frontend -> otaku_profile_privacy_enforce (part 2)
-- Nothing is deleted. Rolling back part 2 = re-grant table SELECT and restore the two
-- "readable by authenticated" policies (see bottom of file).

-- ===== Part 1: additive (safe with the old frontend) =====

-- Own full profile row, including fields hidden from others.
create or replace function public.otaku_my_profile()
returns setof public.otaku_profiles
language sql stable security definer set search_path = ''
as $$
  select * from public.otaku_profiles where id = (select auth.uid());
$$;
revoke all on function public.otaku_my_profile() from public, anon;
grant execute on function public.otaku_my_profile() to authenticated;

-- Attendee count for a published event without exposing who attends.
create or replace function public.otaku_event_attendee_count(target_event uuid)
returns integer
language sql stable security definer set search_path = ''
as $$
  select count(*)::integer
  from public.otaku_event_attendees a
  where a.event_id = target_event
    and exists (
      select 1 from public.otaku_events e
      where e.id = target_event
        and (e.publication_status = 'published' or public.otaku_is_catalog_admin())
    );
$$;
revoke all on function public.otaku_event_attendee_count(uuid) from public, anon;
grant execute on function public.otaku_event_attendee_count(uuid) to authenticated;

-- The public profile view must keep working once the sensitive base columns
-- are no longer selectable, so it now runs with the owner's rights. It is
-- the masking layer: others only see fields the owner chose to show; the
-- owner sees their own row unmasked. Same columns and order as before.
create or replace view public.otaku_public_profiles with (security_invoker = false) as
select id,
  case when show_username     or id = (select auth.uid()) then username     end as username,
  case when show_display_name or id = (select auth.uid()) then display_name end as display_name,
  case when show_avatar       or id = (select auth.uid()) then avatar_url   end as avatar_url,
  case when show_age          or id = (select auth.uid()) then age_range    end as age_range,
  case when show_gender       or id = (select auth.uid()) then gender       end as gender,
  case when show_prefecture   or id = (select auth.uid()) then prefecture   end as prefecture,
  case when show_bio          or id = (select auth.uid()) then bio          end as bio,
  case when show_favorites    or id = (select auth.uid()) then same_oshi_policy end as same_oshi_policy,
  show_favorites,
  show_attendance
from public.otaku_profiles
where (select auth.uid()) is not null;
revoke all on public.otaku_public_profiles from public, anon;
grant select on public.otaku_public_profiles to authenticated;

-- ===== Part 2: enforce (apply after the frontend using part 1 is deployed) =====

-- Others may only read non-sensitive columns. username / display_name /
-- avatar_url / same_oshi_policy stay readable because posts, DMs and
-- companion listings embed them.
revoke select on public.otaku_profiles from authenticated;
grant select (id, username, display_name, avatar_url, same_oshi_policy,
  show_username, show_display_name, show_avatar, show_age, show_gender,
  show_prefecture, show_bio, show_favorites, show_attendance,
  created_at, updated_at)
  on public.otaku_profiles to authenticated;

drop policy if exists "otaku attendees readable by authenticated" on public.otaku_event_attendees;
create policy "otaku attendees own or public" on public.otaku_event_attendees
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (select 1 from public.otaku_profiles p where p.id = otaku_event_attendees.user_id and p.show_attendance)
  );

drop policy if exists "otaku favorites readable by authenticated" on public.otaku_user_favorites;
create policy "otaku favorites own or public" on public.otaku_user_favorites
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (select 1 from public.otaku_profiles p where p.id = otaku_user_favorites.user_id and p.show_favorites)
  );

-- Rollback of part 2 (only if needed):
--   grant select on public.otaku_profiles to authenticated;
--   drop policy "otaku attendees own or public" on public.otaku_event_attendees;
--   create policy "otaku attendees readable by authenticated" on public.otaku_event_attendees for select to authenticated using (true);
--   drop policy "otaku favorites own or public" on public.otaku_user_favorites;
--   create policy "otaku favorites readable by authenticated" on public.otaku_user_favorites for select to authenticated using (true);
