-- OTAKU LIVE only. Avoid recursive RLS evaluation when an owner confirms a match.
create or replace function otaku_private.can_create_companion_match(
  p_post_id uuid,
  p_conversation_id uuid,
  p_owner_user_id uuid,
  p_matched_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) = p_owner_user_id
    and p_owner_user_id <> p_matched_user_id
    and otaku_private.can_interact(p_matched_user_id)
    and exists (
      select 1
      from public.otaku_conversations c
      join public.otaku_companion_posts p on p.id = c.companion_post_id
      where c.id = p_conversation_id
        and p.id = p_post_id
        and p.status = 'open'
        and (p.deadline_at is null or p.deadline_at > now())
        and c.owner_user_id = p_owner_user_id
        and c.requester_user_id = p_matched_user_id
        and p.user_id = p_owner_user_id
        and p.event_id = c.event_id
    );
$$;

revoke all on function otaku_private.can_create_companion_match(uuid, uuid, uuid, uuid)
from public, anon;
grant execute on function otaku_private.can_create_companion_match(uuid, uuid, uuid, uuid)
to authenticated;

drop policy if exists companion_matches_owner_insert on public.otaku_companion_matches;
create policy companion_matches_owner_insert
on public.otaku_companion_matches
for insert
to authenticated
with check (
  otaku_private.can_create_companion_match(
    post_id,
    conversation_id,
    owner_user_id,
    matched_user_id
  )
);
