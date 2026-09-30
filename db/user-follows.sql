create table if not exists public.otaku_user_follows (
  follower_id uuid not null references public.otaku_profiles(id) on delete cascade,
  followed_id uuid not null references public.otaku_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);
create index if not exists otaku_user_follows_followed_idx on public.otaku_user_follows(followed_id, created_at desc);
alter table public.otaku_user_follows enable row level security;
revoke all on public.otaku_user_follows from public, anon, authenticated;
grant select, insert, delete on public.otaku_user_follows to authenticated;
drop policy if exists user_follows_select_own on public.otaku_user_follows;
drop policy if exists user_follows_insert_own on public.otaku_user_follows;
drop policy if exists user_follows_delete_own on public.otaku_user_follows;
create policy user_follows_select_own on public.otaku_user_follows
  for select to authenticated using ((select auth.uid()) = follower_id);
create policy user_follows_insert_own on public.otaku_user_follows
  for insert to authenticated with check ((select auth.uid()) = follower_id);
create policy user_follows_delete_own on public.otaku_user_follows
  for delete to authenticated using ((select auth.uid()) = follower_id);

create or replace function otaku_private.follow_guard()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or new.follower_id <> auth.uid() or new.follower_id = new.followed_id
     or not otaku_private.can_interact(new.followed_id) then
    raise exception 'follow_not_allowed' using errcode='42501';
  end if;
  new.created_at := now();
  return new;
end $$;
drop trigger if exists otaku_follow_guard on public.otaku_user_follows;
create trigger otaku_follow_guard before insert on public.otaku_user_follows
for each row execute function otaku_private.follow_guard();
revoke all on function otaku_private.follow_guard() from public, anon, authenticated;
