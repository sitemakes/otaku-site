create or replace function otaku_private.companion_match_guard()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare c public.otaku_conversations; p public.otaku_companion_posts;
begin
  if auth.uid() is null or new.owner_user_id<>auth.uid() or new.owner_user_id=new.matched_user_id then
    raise exception 'match_not_allowed' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.post_id::text,0));
  select * into c from public.otaku_conversations where id=new.conversation_id;
  select * into p from public.otaku_companion_posts where id=new.post_id;
  if c.id is null or p.id is null or p.status<>'open' or c.companion_post_id<>p.id
     or c.owner_user_id<>new.owner_user_id or c.requester_user_id<>new.matched_user_id
     or p.user_id<>new.owner_user_id or p.event_id<>c.event_id then
    raise exception 'match_invalid_context' using errcode='42501';
  end if;
  new.created_at:=now();
  return new;
end $$;

create or replace function otaku_private.close_companion_post_after_match()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  update public.otaku_companion_posts
  set status='closed'
  where id=new.post_id and user_id=auth.uid() and status='open';
  if not found then raise exception 'match_post_unavailable' using errcode='42501'; end if;
  return new;
end $$;

drop trigger if exists otaku_close_companion_post_after_match on public.otaku_companion_matches;
create trigger otaku_close_companion_post_after_match after insert on public.otaku_companion_matches
for each row execute function otaku_private.close_companion_post_after_match();

revoke all on function otaku_private.companion_match_guard() from public,anon,authenticated;
revoke all on function otaku_private.close_companion_post_after_match() from public,anon,authenticated;
