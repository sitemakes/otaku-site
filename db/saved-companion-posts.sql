create table public.otaku_saved_companion_posts (
 user_id uuid not null references public.otaku_profiles(id) on delete cascade,
 post_id uuid not null references public.otaku_companion_posts(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(user_id,post_id)
);
alter table public.otaku_saved_companion_posts enable row level security;
revoke all on public.otaku_saved_companion_posts from anon,authenticated;
grant select,insert,delete on public.otaku_saved_companion_posts to authenticated;
create policy "otaku users manage saved companion posts" on public.otaku_saved_companion_posts for all to authenticated
using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
