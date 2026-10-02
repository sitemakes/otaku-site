-- Private per-user reactions for visible OTAKU LIVE board posts.
create table if not exists public.otaku_board_reactions (
  post_id uuid not null references public.otaku_board_posts(id) on delete cascade,
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists otaku_board_reactions_post_idx
  on public.otaku_board_reactions(post_id);

alter table public.otaku_board_reactions enable row level security;
revoke all on public.otaku_board_reactions from public, anon, authenticated;
grant select (post_id) on public.otaku_board_reactions to authenticated;
grant insert (post_id,user_id), delete on public.otaku_board_reactions to authenticated;

drop policy if exists board_reactions_select_visible on public.otaku_board_reactions;
drop policy if exists board_reactions_insert_own on public.otaku_board_reactions;
drop policy if exists board_reactions_delete_own on public.otaku_board_reactions;

create policy board_reactions_select_visible
on public.otaku_board_reactions for select to authenticated
using (
  exists (
    select 1 from public.otaku_board_posts p
    where p.id=post_id
      and not p.hidden
      and otaku_private.board_target_visible(p.event_id,p.idol_id)
  )
);

create policy board_reactions_insert_own
on public.otaku_board_reactions for insert to authenticated
with check (
  (select auth.uid()) is not null
  and user_id=(select auth.uid())
  and exists (
    select 1 from public.otaku_board_posts p
    where p.id=post_id
      and not p.hidden
      and otaku_private.board_target_visible(p.event_id,p.idol_id)
  )
);

create policy board_reactions_delete_own
on public.otaku_board_reactions for delete to authenticated
using ((select auth.uid()) is not null and user_id=(select auth.uid()));

-- Counts are exposed without revealing which users reacted.
create or replace view public.otaku_board_reaction_counts with (security_invoker=true) as
  select r.post_id, count(*)::bigint as reaction_count
  from public.otaku_board_reactions r
  join public.otaku_board_posts p on p.id=r.post_id
  where not p.hidden
    and otaku_private.board_target_visible(p.event_id,p.idol_id)
  group by r.post_id;

revoke all on public.otaku_board_reaction_counts from public, anon, authenticated;
grant select on public.otaku_board_reaction_counts to authenticated;
