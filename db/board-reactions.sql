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

-- Counts are stored separately so clients never need table-level access to user_id.
create table if not exists public.otaku_board_reaction_counts (
  post_id uuid primary key references public.otaku_board_posts(id) on delete cascade,
  reaction_count integer not null default 0 check (reaction_count >= 0)
);
alter table public.otaku_board_reaction_counts enable row level security;
revoke all on public.otaku_board_reaction_counts from public, anon, authenticated;
grant select on public.otaku_board_reaction_counts to authenticated;
drop policy if exists board_reaction_counts_visible on public.otaku_board_reaction_counts;
create policy board_reaction_counts_visible
on public.otaku_board_reaction_counts for select to authenticated
using (
  exists (
    select 1 from public.otaku_board_posts p
    where p.id=post_id
      and not p.hidden
      and otaku_private.board_target_visible(p.event_id,p.idol_id)
  )
);

create or replace function otaku_private.sync_board_reaction_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.otaku_board_reaction_counts(post_id,reaction_count)
    values (new.post_id,1)
    on conflict (post_id) do update
      set reaction_count=public.otaku_board_reaction_counts.reaction_count+1;
    return new;
  end if;
  update public.otaku_board_reaction_counts
    set reaction_count=greatest(reaction_count-1,0)
    where post_id=old.post_id;
  delete from public.otaku_board_reaction_counts where post_id=old.post_id and reaction_count=0;
  return old;
end;
$$;
revoke all on function otaku_private.sync_board_reaction_count() from public, anon, authenticated;
drop trigger if exists otaku_board_reaction_count_sync on public.otaku_board_reactions;
create trigger otaku_board_reaction_count_sync
after insert or delete on public.otaku_board_reactions
for each row execute function otaku_private.sync_board_reaction_count();

insert into public.otaku_board_reaction_counts(post_id,reaction_count)
select post_id,count(*)::integer from public.otaku_board_reactions group by post_id
on conflict (post_id) do update set reaction_count=excluded.reaction_count;

create or replace function public.otaku_toggle_board_reaction(target_post uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (
    select 1 from public.otaku_board_posts p
    where p.id=target_post and not p.hidden
      and otaku_private.board_target_visible(p.event_id,p.idol_id)
  ) then raise exception 'board_post_unavailable'; end if;
  if exists (select 1 from public.otaku_board_reactions where post_id=target_post and user_id=uid) then
    delete from public.otaku_board_reactions where post_id=target_post and user_id=uid;
    return false;
  end if;
  insert into public.otaku_board_reactions(post_id,user_id) values (target_post,uid);
  return true;
end;
$$;
revoke all on function public.otaku_toggle_board_reaction(uuid) from public, anon;
grant execute on function public.otaku_toggle_board_reaction(uuid) to authenticated;
