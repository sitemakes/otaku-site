create or replace function otaku_private.notify_board_reply()
returns trigger language plpgsql security definer set search_path=''
as $$
declare p public.otaku_board_posts; href text;
begin
  if auth.uid() is null or auth.uid()<>new.user_id then
    raise exception 'not_allowed' using errcode='42501';
  end if;
  select * into p from public.otaku_board_posts where id=new.post_id and not hidden;
  if not found then return new; end if;
  href:='board.html?'||case when p.event_id is not null then 'event='||p.event_id
    when p.idol_id is not null then 'idol='||p.idol_id else '' end||
    case when (p.event_id is not null or p.idol_id is not null) then '&' else '' end||
    'category='||p.category||'#post-'||p.id;
  with recipients as (
    select p.user_id as user_id
    union
    select r.user_id from public.otaku_board_replies r
    where r.post_id=new.post_id and not r.hidden
  )
  insert into public.otaku_notifications(user_id,kind,title,body,href)
  select r.user_id,'board','掲示板に返信があります',
    case when p.title<>'' then '「'||left(p.title,60)||'」に新しい返信がありました。'
      else '参加している投稿に新しい返信がありました。' end,href
  from recipients r
  join public.otaku_notification_preferences n on n.user_id=r.user_id
  where r.user_id<>new.user_id and n.in_app_enabled and n.board_enabled
    and not exists(select 1 from public.otaku_user_blocks b where
      (b.blocker_id=r.user_id and b.blocked_id=new.user_id)
      or (b.blocker_id=new.user_id and b.blocked_id=r.user_id));
  return new;
end $$;
revoke all on function otaku_private.notify_board_reply() from public,anon,authenticated;
