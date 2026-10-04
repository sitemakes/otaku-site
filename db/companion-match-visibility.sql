drop policy if exists "otaku visible companion posts" on public.otaku_companion_posts;
create policy "otaku visible companion posts" on public.otaku_companion_posts
for select to authenticated using (
  user_id=(select auth.uid())
  or (status='open' and otaku_private.can_interact(user_id))
  or exists (
    select 1 from public.otaku_companion_matches m
    where m.post_id=otaku_companion_posts.id
      and m.matched_user_id=(select auth.uid())
      and otaku_private.can_interact(otaku_companion_posts.user_id)
  )
);
