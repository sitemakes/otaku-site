create table public.otaku_saved_searches (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.otaku_profiles(id) on delete cascade,
 name text not null check(char_length(btrim(name)) between 1 and 80),
 query text not null default '' check(char_length(query)<=100),
 group_id uuid references public.otaku_idol_groups(id) on delete set null,
 month text check(month is null or month ~ '^[0-9]{4}-[0-9]{2}$'),
 created_at timestamptz not null default now()
);
alter table public.otaku_saved_searches enable row level security;
revoke all on public.otaku_saved_searches from anon,authenticated;
grant select,insert,delete on public.otaku_saved_searches to authenticated;
create policy "otaku users manage saved searches" on public.otaku_saved_searches for all to authenticated
using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
