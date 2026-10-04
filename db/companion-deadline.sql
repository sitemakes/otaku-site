alter table public.otaku_companion_posts add column if not exists deadline_at timestamptz;
revoke update on public.otaku_companion_posts from authenticated;
grant update(status,body,type,preferred_gender,preferred_age_min,preferred_age_max,same_oshi_ok,deadline_at) on public.otaku_companion_posts to authenticated;

create or replace function otaku_private.post_guard()
returns trigger language plpgsql set search_path=''
as $$
begin
  if auth.uid() is null or new.user_id<>auth.uid() then raise exception 'safety_not_allowed' using errcode='42501'; end if;
  if TG_OP='UPDATE' then
    if new.id<>old.id or new.user_id<>old.user_id or new.event_id<>old.event_id or new.created_at<>old.created_at then
      raise exception 'safety_identity_immutable' using errcode='23514';
    end if;
    if old.status='closed' and new.status<>'closed' then raise exception 'post_already_closed' using errcode='23514'; end if;
    if old.status='closed' then new.closed_at:=old.closed_at; else new.closed_at:=case when new.status='closed' then now() else null end; end if;
    if new.deadline_at is distinct from old.deadline_at and new.deadline_at is not null and
       (new.deadline_at<=now() or not exists(select 1 from public.otaku_events where id=new.event_id and new.deadline_at<starts_at)) then
      raise exception 'invalid_companion_deadline' using errcode='23514';
    end if;
  else
    new.created_at:=now(); new.closed_at:=case when new.status='closed' then now() else null end;
    if not exists(select 1 from public.otaku_events where id=new.event_id and publication_status='published') then
      raise exception 'safety_event_unavailable' using errcode='23514';
    end if;
    if new.deadline_at is not null and
       (new.deadline_at<=now() or not exists(select 1 from public.otaku_events where id=new.event_id and new.deadline_at<starts_at)) then
      raise exception 'invalid_companion_deadline' using errcode='23514';
    end if;
  end if;
  new.body:=btrim(new.body);
  if new.body='' then raise exception 'safety_content_required' using errcode='23514'; end if;
  return new;
end $$;
revoke all on function otaku_private.post_guard() from public,anon,authenticated;

drop policy if exists "otaku visible companion posts" on public.otaku_companion_posts;
create policy "otaku visible companion posts" on public.otaku_companion_posts for select to authenticated using(
  user_id=(select auth.uid())
  or (status='open' and (deadline_at is null or deadline_at>now()) and otaku_private.can_interact(user_id))
  or exists(select 1 from public.otaku_companion_matches m where m.post_id=otaku_companion_posts.id and m.matched_user_id=(select auth.uid()) and otaku_private.can_interact(otaku_companion_posts.user_id))
);

create or replace function otaku_private.conversation_guard()
returns trigger language plpgsql security definer set search_path=''
as $$
declare p public.otaku_companion_posts; g public.otaku_goods_posts;
begin
  if auth.uid() is null or new.requester_user_id<>auth.uid() or new.owner_user_id=auth.uid() then raise exception 'safety_not_allowed' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(new.owner_user_id,new.requester_user_id)::text||greatest(new.owner_user_id,new.requester_user_id)::text,0));
  if new.companion_post_id is not null and new.goods_post_id is null then
    select * into p from public.otaku_companion_posts where id=new.companion_post_id for share;
    if not found or p.status<>'open' or (p.deadline_at is not null and p.deadline_at<=now()) or p.user_id<>new.owner_user_id or p.event_id<>new.event_id then raise exception 'safety_post_unavailable' using errcode='42501'; end if;
  elsif new.goods_post_id is not null and new.companion_post_id is null then
    select * into g from public.otaku_goods_posts where id=new.goods_post_id for share;
    if not found or g.status<>'open' or g.user_id<>new.owner_user_id or g.event_id is distinct from new.event_id then raise exception 'safety_post_unavailable' using errcode='42501'; end if;
  else raise exception 'safety_post_unavailable' using errcode='42501'; end if;
  if exists(select 1 from public.otaku_user_blocks where (blocker_id=new.owner_user_id and blocked_id=new.requester_user_id) or (blocker_id=new.requester_user_id and blocked_id=new.owner_user_id)) then raise exception 'safety_interaction_unavailable' using errcode='42501'; end if;
  if new.event_id is not null and not exists(select 1 from public.otaku_events where id=new.event_id and publication_status='published') then raise exception 'safety_event_unavailable' using errcode='42501'; end if;
  new.created_at:=now(); return new;
end $$;
revoke all on function otaku_private.conversation_guard() from public,anon,authenticated;

drop policy if exists companion_matches_owner_insert on public.otaku_companion_matches;
create policy companion_matches_owner_insert on public.otaku_companion_matches for insert to authenticated with check(
  (select auth.uid())=owner_user_id and otaku_private.can_interact(matched_user_id) and exists(
    select 1 from public.otaku_conversations c join public.otaku_companion_posts p on p.id=c.companion_post_id
    where c.id=otaku_companion_matches.conversation_id and p.id=otaku_companion_matches.post_id and p.status='open'
      and (p.deadline_at is null or p.deadline_at>now()) and c.owner_user_id=otaku_companion_matches.owner_user_id
      and c.requester_user_id=otaku_companion_matches.matched_user_id and p.user_id=otaku_companion_matches.owner_user_id and p.event_id=c.event_id
  )
);
