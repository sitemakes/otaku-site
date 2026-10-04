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

drop policy if exists "otaku matched participants can review each other" on public.otaku_reviews;
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
