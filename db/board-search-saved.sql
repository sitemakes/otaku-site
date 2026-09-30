alter table public.otaku_board_posts
  add column if not exists resolved boolean not null default false;

revoke update on public.otaku_board_posts from authenticated;
grant update(title,body,category,resolved) on public.otaku_board_posts to authenticated;

create table if not exists public.otaku_saved_board_posts (
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  post_id uuid not null references public.otaku_board_posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index if not exists otaku_saved_board_posts_post_idx on public.otaku_saved_board_posts(post_id);
alter table public.otaku_saved_board_posts enable row level security;
revoke all on public.otaku_saved_board_posts from public, anon, authenticated;
grant select, insert, delete on public.otaku_saved_board_posts to authenticated;
drop policy if exists saved_board_select_own on public.otaku_saved_board_posts;
drop policy if exists saved_board_insert_own on public.otaku_saved_board_posts;
drop policy if exists saved_board_delete_own on public.otaku_saved_board_posts;
create policy saved_board_select_own on public.otaku_saved_board_posts
  for select to authenticated using ((select auth.uid()) = user_id);
create policy saved_board_insert_own on public.otaku_saved_board_posts
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy saved_board_delete_own on public.otaku_saved_board_posts
  for delete to authenticated using ((select auth.uid()) = user_id);

create or replace function otaku_private.board_guard()
returns trigger language plpgsql set search_path=''
as $$
begin
  if tg_op='UPDATE' and public.otaku_is_catalog_admin() then return new; end if;
  if auth.uid() is null or new.user_id<>auth.uid() then
    raise exception 'board_not_allowed' using errcode='42501';
  end if;
  if tg_op='UPDATE' and (to_jsonb(new)-array['body','title','category','resolved','updated_at'])
      is distinct from (to_jsonb(old)-array['body','title','category','resolved','updated_at']) then
    raise exception 'board_not_allowed' using errcode='42501';
  end if;
  if not otaku_private.board_target_visible(new.event_id,new.idol_id)
     or not otaku_private.board_category_valid(new.event_id,new.idol_id,new.category) then
    raise exception 'board_target_unavailable' using errcode='42501';
  end if;
  new.title:=btrim(new.title);
  new.body:=btrim(new.body);
  if new.title is null or length(new.title)>120 or new.body is null
     or new.body='' or length(new.body)>2000 then
    raise exception 'board_content_invalid' using errcode='23514';
  end if;
  if tg_op='INSERT' then new.hidden:=false; new.pinned:=false; new.resolved:=false; new.created_at:=now(); end if;
  new.updated_at:=now(); return new;
end $$;
