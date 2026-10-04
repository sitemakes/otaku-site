-- OTAKU LIVE only. A match is an owner-confirmed companion conversation.
create table if not exists public.otaku_companion_matches (
  post_id uuid primary key references public.otaku_companion_posts(id) on delete cascade,
  conversation_id uuid not null unique references public.otaku_conversations(id) on delete cascade,
  owner_user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  matched_user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint otaku_companion_matches_different_users check (owner_user_id <> matched_user_id)
);
create index if not exists otaku_companion_matches_owner_idx on public.otaku_companion_matches(owner_user_id,created_at desc);
create index if not exists otaku_companion_matches_matched_idx on public.otaku_companion_matches(matched_user_id,created_at desc);

alter table public.otaku_companion_matches enable row level security;
revoke all on public.otaku_companion_matches from public,anon,authenticated;
grant select,insert on public.otaku_companion_matches to authenticated;

drop policy if exists companion_matches_participants_read on public.otaku_companion_matches;
create policy companion_matches_participants_read on public.otaku_companion_matches
for select to authenticated using (
  ((select auth.uid())=owner_user_id and otaku_private.can_interact(matched_user_id))
  or ((select auth.uid())=matched_user_id and otaku_private.can_interact(owner_user_id))
);

drop policy if exists companion_matches_owner_insert on public.otaku_companion_matches;
create policy companion_matches_owner_insert on public.otaku_companion_matches
for insert to authenticated with check (
  (select auth.uid())=owner_user_id
  and otaku_private.can_interact(matched_user_id)
  and exists (
    select 1 from public.otaku_conversations c
    join public.otaku_companion_posts p on p.id=c.companion_post_id
    where c.id=otaku_companion_matches.conversation_id
      and p.id=otaku_companion_matches.post_id and p.status='open'
      and c.owner_user_id=otaku_companion_matches.owner_user_id
      and c.requester_user_id=otaku_companion_matches.matched_user_id
      and p.user_id=otaku_companion_matches.owner_user_id and p.event_id=c.event_id
  )
);

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
drop trigger if exists otaku_companion_match_guard on public.otaku_companion_matches;
create trigger otaku_companion_match_guard before insert on public.otaku_companion_matches
for each row execute function otaku_private.companion_match_guard();
revoke all on function otaku_private.companion_match_guard() from public,anon,authenticated;

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
revoke all on function otaku_private.close_companion_post_after_match() from public,anon,authenticated;

drop policy if exists "otaku participants can review each other" on public.otaku_reviews;
create policy "otaku matched participants can review each other" on public.otaku_reviews
for insert to authenticated with check (
  (select auth.uid()) is not null and (select auth.uid())=reviewer_id and reviewer_id<>reviewee_id
  and exists (
    select 1 from public.otaku_conversations c
    join public.otaku_companion_matches m on m.conversation_id=c.id
    join public.otaku_events e on e.id=c.event_id
    where c.id=otaku_reviews.conversation_id and e.starts_at<now()
      and ((c.owner_user_id=otaku_reviews.reviewer_id and c.requester_user_id=otaku_reviews.reviewee_id)
        or (c.requester_user_id=otaku_reviews.reviewer_id and c.owner_user_id=otaku_reviews.reviewee_id))
  )
);
