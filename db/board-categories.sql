-- Categorized boards: global (both targets NULL), idol, and event.
alter table public.otaku_board_posts
  add column if not exists title text not null default '',
  add column if not exists category text not null default 'other',
  add column if not exists pinned boolean not null default false;

alter table public.otaku_board_posts
  drop constraint if exists otaku_board_one_target;

alter table public.otaku_board_posts
  drop constraint if exists otaku_board_posts_title_check,
  drop constraint if exists otaku_board_posts_category_check;

alter table public.otaku_board_posts
  add constraint otaku_board_posts_title_check
    check (char_length(title) <= 120),
  add constraint otaku_board_posts_category_check
    check (category = any (array[
      'general','fan','goods','venue','event_info','companion','seating','other'
    ]));

create or replace function otaku_private.board_target_visible(eid uuid, iid uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select (eid is null and iid is null)
    or (eid is not null and exists(
      select 1 from public.otaku_events e
      where e.id=eid and e.publication_status='published'))
    or (iid is not null and exists(
      select 1 from public.otaku_idols i
      join public.otaku_idol_groups g on g.id=i.group_id
      where i.id=iid and i.publication_status='published'
        and g.publication_status='published'));
$$;

create or replace function otaku_private.board_category_valid(eid uuid, iid uuid, cat text)
returns boolean language sql immutable set search_path=''
as $$
  select case
    when eid is null and iid is null then cat = any(array['general','fan','goods','venue','other'])
    when eid is not null then cat = any(array['event_info','venue','goods','companion','seating','other'])
    when iid is not null then cat = any(array['general','fan','goods','event_info','other'])
    else false end;
$$;

create or replace function otaku_private.board_guard()
returns trigger language plpgsql set search_path=''
as $$
begin
  if tg_op='UPDATE' and public.otaku_is_catalog_admin() then return new; end if;
  if auth.uid() is null or new.user_id<>auth.uid() then
    raise exception 'board_not_allowed' using errcode='42501';
  end if;
  if tg_op='UPDATE' and (to_jsonb(new)-array['body','title','category','updated_at'])
      is distinct from (to_jsonb(old)-array['body','title','category','updated_at']) then
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
  if tg_op='INSERT' then new.hidden:=false; new.pinned:=false; new.created_at:=now(); end if;
  new.updated_at:=now(); return new;
end $$;

create or replace function otaku_private.notify_board_post()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or auth.uid()<>new.user_id then
    raise exception 'not_allowed' using errcode='42501';
  end if;
  insert into public.otaku_notifications(user_id,kind,title,body,href)
  select distinct p.user_id,'board','掲示板に新しい投稿があります',
    '参加中の掲示板に新しい書き込みがありました。',
    'board.html?'||case when new.event_id is not null then 'event='||new.event_id
      when new.idol_id is not null then 'idol='||new.idol_id else '' end||
      case when (new.event_id is not null or new.idol_id is not null) then '&' else '' end||'category='||new.category
  from public.otaku_board_posts p
  join public.otaku_notification_preferences n on n.user_id=p.user_id
  where p.user_id<>new.user_id and n.in_app_enabled and n.board_enabled
    and p.category=new.category
    and ((new.event_id is not null and p.event_id=new.event_id)
      or (new.idol_id is not null and p.idol_id=new.idol_id)
      or (new.event_id is null and new.idol_id is null and p.event_id is null and p.idol_id is null))
    and not exists(select 1 from public.otaku_user_blocks b where
      (b.blocker_id=p.user_id and b.blocked_id=new.user_id)
      or (b.blocker_id=new.user_id and b.blocked_id=p.user_id));
  return new;
end $$;

revoke update on public.otaku_board_posts from authenticated;
grant update(title,body,category) on public.otaku_board_posts to authenticated;

create or replace function public.otaku_set_board_pinned(post_id uuid, next_pinned boolean)
returns boolean language plpgsql security definer set search_path=''
as $$
begin
  if not public.otaku_is_catalog_admin() then raise exception 'not_allowed' using errcode='42501'; end if;
  update public.otaku_board_posts set pinned=next_pinned where id=post_id;
  return found;
end $$;
revoke execute on function public.otaku_set_board_pinned(uuid,boolean) from public, anon;
grant execute on function public.otaku_set_board_pinned(uuid,boolean) to authenticated;
