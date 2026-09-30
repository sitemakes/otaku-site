create table public.otaku_board_replies (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.otaku_board_posts(id) on delete cascade,
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  body text not null,
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint otaku_board_replies_body_check
    check (char_length(btrim(body)) between 1 and 1000)
);

create index otaku_board_replies_post_created_idx
  on public.otaku_board_replies(post_id, created_at);
create index otaku_board_replies_user_idx
  on public.otaku_board_replies(user_id);

alter table public.otaku_board_replies enable row level security;
revoke all on public.otaku_board_replies from public, anon, authenticated;
grant select, insert, delete on public.otaku_board_replies to authenticated;

create policy "otaku board replies visible"
on public.otaku_board_replies for select to authenticated
using (
  not hidden
  and otaku_private.can_interact(user_id)
  and exists (
    select 1 from public.otaku_board_posts p
    where p.id=post_id and not p.hidden
      and otaku_private.board_target_visible(p.event_id,p.idol_id)
      and otaku_private.can_interact(p.user_id)
  )
);

create policy "otaku board replies own insert"
on public.otaku_board_replies for insert to authenticated
with check (
  (select auth.uid())=user_id
  and exists (
    select 1 from public.otaku_board_posts p
    where p.id=post_id and not p.hidden
      and otaku_private.board_target_visible(p.event_id,p.idol_id)
      and otaku_private.can_interact(p.user_id)
  )
);

create policy "otaku board replies own delete"
on public.otaku_board_replies for delete to authenticated
using ((select auth.uid())=user_id);

create function otaku_private.board_reply_guard()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  if tg_op='UPDATE' and public.otaku_is_catalog_admin()
     and (to_jsonb(new)-'hidden')=(to_jsonb(old)-'hidden') then
    new.updated_at:=now(); return new;
  end if;
  if tg_op<>'INSERT' or auth.uid() is null or new.user_id<>auth.uid() then
    raise exception 'board_reply_not_allowed' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.otaku_board_posts p
    where p.id=new.post_id and not p.hidden
      and otaku_private.board_target_visible(p.event_id,p.idol_id)
      and otaku_private.can_interact(p.user_id)
  ) then raise exception 'board_reply_target_unavailable' using errcode='42501'; end if;
  new.body:=btrim(new.body);
  if new.body is null or new.body='' or length(new.body)>1000 then
    raise exception 'board_reply_content_invalid' using errcode='23514';
  end if;
  new.hidden:=false; new.created_at:=now(); new.updated_at:=now(); return new;
end $$;
revoke all on function otaku_private.board_reply_guard() from public,anon,authenticated;

create trigger otaku_board_reply_guard
before insert or update on public.otaku_board_replies
for each row execute function otaku_private.board_reply_guard();

create function otaku_private.notify_board_reply()
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
  insert into public.otaku_notifications(user_id,kind,title,body,href)
  select p.user_id,'board','掲示板に返信があります',
    case when p.title<>'' then '「'||left(p.title,60)||'」に返信がありました。'
      else '投稿に返信がありました。' end,href
  from public.otaku_notification_preferences n
  where n.user_id=p.user_id and p.user_id<>new.user_id
    and n.in_app_enabled and n.board_enabled
    and not exists(select 1 from public.otaku_user_blocks b where
      (b.blocker_id=p.user_id and b.blocked_id=new.user_id)
      or (b.blocker_id=new.user_id and b.blocked_id=p.user_id));
  return new;
end $$;
revoke all on function otaku_private.notify_board_reply() from public,anon,authenticated;

create trigger otaku_board_reply_notify
after insert on public.otaku_board_replies
for each row execute function otaku_private.notify_board_reply();

alter table public.otaku_content_reports
  drop constraint if exists otaku_content_reports_kind_check;
alter table public.otaku_content_reports
  add constraint otaku_content_reports_kind_check
  check (kind=any(array['board','board_reply','review']));

create or replace function otaku_private.content_report_guard()
returns trigger language plpgsql security definer set search_path=''
as $$
declare s jsonb; author uuid;
begin
  if auth.uid() is null or auth.uid()<>new.reporter_id then raise exception 'not_allowed' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('otaku-content-report:'||auth.uid(),0));
  if (select count(*) from public.otaku_content_reports where reporter_id=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'report_rate_limit' using errcode='23514'; end if;
  if new.kind='board' then
    select jsonb_build_object('title',title,'body',body,'event_id',event_id,'idol_id',idol_id),user_id
      into s,author from public.otaku_board_posts
      where id=new.target_id and not hidden and otaku_private.board_target_visible(event_id,idol_id);
  elsif new.kind='board_reply' then
    select jsonb_build_object('body',r.body,'post_id',r.post_id),r.user_id into s,author
      from public.otaku_board_replies r join public.otaku_board_posts p on p.id=r.post_id
      where r.id=new.target_id and not r.hidden and not p.hidden
        and otaku_private.board_target_visible(p.event_id,p.idol_id);
  else
    select jsonb_build_object('comment',comment,'rating',rating,'reviewee_id',reviewee_id),reviewer_id
      into s,author from public.otaku_reviews where id=new.target_id and visibility='visible';
  end if;
  if s is null or author=auth.uid() or not otaku_private.can_interact(author) then raise exception 'report_invalid_context' using errcode='42501'; end if;
  new.snapshot:=s; new.status:='open'; new.created_at:=now(); return new;
end $$;

create or replace function public.otaku_moderate_content(report uuid, action text, reason text)
returns void language plpgsql security definer set search_path=''
as $$
declare r public.otaku_content_reports;
begin
  if auth.uid() is null or not public.otaku_is_catalog_admin() then raise exception 'not_allowed' using errcode='42501'; end if;
  if action not in ('hide','restore','resolve') or action is null or reason is null or char_length(btrim(reason)) not between 1 and 500 then raise exception 'invalid_action' using errcode='23514'; end if;
  select * into r from public.otaku_content_reports where id=report for update;
  if not found then raise exception 'report_not_found' using errcode='23514'; end if;
  if action<>'resolve' then
    if r.kind='board' then update public.otaku_board_posts set hidden=(action='hide') where id=r.target_id;
    elsif r.kind='board_reply' then update public.otaku_board_replies set hidden=(action='hide') where id=r.target_id;
    else update public.otaku_reviews set visibility=case when action='hide' then 'hidden' else 'visible' end, moderation_reason=btrim(reason) where id=r.target_id;
    end if;
    if not found then raise exception 'content_not_found' using errcode='23514'; end if;
  end if;
  update public.otaku_content_reports set status=case when action='restore' then 'open' else 'resolved' end where id=report;
  insert into public.otaku_content_actions(report_id,actor_id,action,reason) values(report,auth.uid(),action,btrim(reason));
end $$;
