create table public.otaku_event_favorites (
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  event_id uuid not null references public.otaku_events(id) on delete cascade,
  created_at timestamptz not null default now(), primary key (user_id,event_id)
);
create table public.otaku_group_favorites (
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  group_id uuid not null references public.otaku_idol_groups(id) on delete cascade,
  created_at timestamptz not null default now(), primary key (user_id,group_id)
);
alter table public.otaku_event_favorites enable row level security;
alter table public.otaku_group_favorites enable row level security;
revoke all on public.otaku_event_favorites, public.otaku_group_favorites from anon,authenticated;
grant select,insert,delete on public.otaku_event_favorites, public.otaku_group_favorites to authenticated;
create policy "otaku users manage event favorites" on public.otaku_event_favorites for all to authenticated
using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create policy "otaku users manage group favorites" on public.otaku_group_favorites for all to authenticated
using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
