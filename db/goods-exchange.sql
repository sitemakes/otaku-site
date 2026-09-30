create table public.otaku_goods_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  group_id uuid not null references public.otaku_idol_groups(id) on delete cascade,
  idol_id uuid references public.otaku_idols(id) on delete set null,
  event_id uuid references public.otaku_events(id) on delete set null,
  trade_type text not null check (trade_type=any(array['offer','want','trade'])),
  item_name text not null check (char_length(btrim(item_name)) between 1 and 120),
  description text not null check (char_length(btrim(description)) between 1 and 1500),
  delivery_method text not null check (delivery_method=any(array['meetup','mail','either'])),
  meetup_prefecture text check (meetup_prefecture is null or char_length(btrim(meetup_prefecture)) between 1 and 20),
  status text not null default 'open' check (status=any(array['open','negotiating','closed'])),
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index otaku_goods_posts_open_idx on public.otaku_goods_posts(status,created_at desc) where not hidden;
create index otaku_goods_posts_group_idx on public.otaku_goods_posts(group_id,status,created_at desc) where not hidden;
create index otaku_goods_posts_user_idx on public.otaku_goods_posts(user_id);
create index otaku_goods_posts_idol_idx on public.otaku_goods_posts(idol_id) where idol_id is not null;
create index otaku_goods_posts_event_idx on public.otaku_goods_posts(event_id) where event_id is not null;

alter table public.otaku_goods_posts enable row level security;
revoke all on public.otaku_goods_posts from public,anon,authenticated;
grant select,insert,delete on public.otaku_goods_posts to authenticated;
grant update(status) on public.otaku_goods_posts to authenticated;
create policy "otaku goods visible" on public.otaku_goods_posts for select to authenticated
using (not hidden and (status='open' or user_id=(select auth.uid())) and otaku_private.can_interact(user_id));
create policy "otaku goods own insert" on public.otaku_goods_posts for insert to authenticated
with check (user_id=(select auth.uid()));
create policy "otaku goods own update" on public.otaku_goods_posts for update to authenticated
using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "otaku goods own delete" on public.otaku_goods_posts for delete to authenticated
using (user_id=(select auth.uid()));

create function otaku_private.goods_post_guard()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  if tg_op='UPDATE' and public.otaku_is_catalog_admin()
     and (to_jsonb(new)-'hidden')=(to_jsonb(old)-'hidden') then new.updated_at:=now(); return new; end if;
  if auth.uid() is null or new.user_id<>auth.uid() then raise exception 'goods_not_allowed' using errcode='42501'; end if;
  if tg_op='UPDATE' then
    if (to_jsonb(new)-array['status','updated_at']) is distinct from (to_jsonb(old)-array['status','updated_at']) then raise exception 'goods_not_allowed' using errcode='42501'; end if;
    if old.status='closed' and new.status<>'closed' then raise exception 'goods_status_invalid' using errcode='23514'; end if;
  end if;
  if not exists(select 1 from public.otaku_idol_groups g where g.id=new.group_id and g.publication_status='published') then raise exception 'goods_group_unavailable' using errcode='42501'; end if;
  if new.idol_id is not null and not exists(select 1 from public.otaku_idols i where i.id=new.idol_id and i.group_id=new.group_id and i.publication_status='published') then raise exception 'goods_idol_unavailable' using errcode='42501'; end if;
  if new.event_id is not null and not exists(select 1 from public.otaku_events e where e.id=new.event_id and e.group_id=new.group_id and e.publication_status='published') then raise exception 'goods_event_unavailable' using errcode='42501'; end if;
  new.item_name:=btrim(new.item_name); new.description:=btrim(new.description); new.meetup_prefecture:=nullif(btrim(new.meetup_prefecture),'');
  if new.delivery_method in ('meetup','either') and new.meetup_prefecture is null then raise exception 'goods_meetup_required' using errcode='23514'; end if;
  if tg_op='INSERT' then new.status:='open'; new.hidden:=false; new.created_at:=now(); end if;
  new.updated_at:=now(); return new;
end $$;
revoke all on function otaku_private.goods_post_guard() from public,anon,authenticated;
create trigger otaku_goods_post_guard before insert or update on public.otaku_goods_posts for each row execute function otaku_private.goods_post_guard();

create table public.otaku_saved_goods_posts (
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  post_id uuid not null references public.otaku_goods_posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id,post_id)
);
create index otaku_saved_goods_post_idx on public.otaku_saved_goods_posts(post_id);
alter table public.otaku_saved_goods_posts enable row level security;
revoke all on public.otaku_saved_goods_posts from public,anon,authenticated;
grant select,insert,delete on public.otaku_saved_goods_posts to authenticated;
create policy "otaku saved goods own select" on public.otaku_saved_goods_posts for select to authenticated using (user_id=(select auth.uid()));
create policy "otaku saved goods own insert" on public.otaku_saved_goods_posts for insert to authenticated with check (user_id=(select auth.uid()));
create policy "otaku saved goods own delete" on public.otaku_saved_goods_posts for delete to authenticated using (user_id=(select auth.uid()));

alter table public.otaku_conversations alter column event_id drop not null;
alter table public.otaku_conversations alter column companion_post_id drop not null;
alter table public.otaku_conversations add column goods_post_id uuid references public.otaku_goods_posts(id) on delete cascade;
alter table public.otaku_conversations add constraint otaku_conversations_one_context check (
  (companion_post_id is not null and goods_post_id is null and event_id is not null)
  or (companion_post_id is null and goods_post_id is not null)
);
alter table public.otaku_conversations add constraint otaku_conversations_goods_post_requester_key unique(goods_post_id,requester_user_id);
create index otaku_conversations_goods_post_idx on public.otaku_conversations(goods_post_id);

drop policy "otaku requester opens active unblocked post" on public.otaku_conversations;
create policy "otaku requester opens active unblocked post" on public.otaku_conversations for insert to authenticated with check (
  requester_user_id=(select auth.uid()) and owner_user_id<>requester_user_id and otaku_private.can_interact(owner_user_id)
  and (
    exists(select 1 from public.otaku_companion_posts p where p.id=companion_post_id and p.event_id=event_id and p.user_id=owner_user_id and p.status='open')
    or exists(select 1 from public.otaku_goods_posts g where g.id=goods_post_id and g.user_id=owner_user_id and g.status='open' and g.event_id is not distinct from event_id)
  )
);

create or replace function otaku_private.conversation_guard()
returns trigger language plpgsql security definer set search_path=''
as $$
declare p public.otaku_companion_posts; g public.otaku_goods_posts;
begin
  if auth.uid() is null or new.requester_user_id<>auth.uid() or new.owner_user_id=auth.uid() then raise exception 'safety_not_allowed' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(new.owner_user_id,new.requester_user_id)::text||greatest(new.owner_user_id,new.requester_user_id)::text,0));
  if new.companion_post_id is not null and new.goods_post_id is null then
    select * into p from public.otaku_companion_posts where id=new.companion_post_id for share;
    if not found or p.status<>'open' or p.user_id<>new.owner_user_id or p.event_id<>new.event_id then raise exception 'safety_post_unavailable' using errcode='42501'; end if;
  elsif new.goods_post_id is not null and new.companion_post_id is null then
    select * into g from public.otaku_goods_posts where id=new.goods_post_id for share;
    if not found or g.status<>'open' or g.user_id<>new.owner_user_id or g.event_id is distinct from new.event_id then raise exception 'safety_post_unavailable' using errcode='42501'; end if;
  else raise exception 'safety_post_unavailable' using errcode='42501'; end if;
  if exists(select 1 from public.otaku_user_blocks where (blocker_id=new.owner_user_id and blocked_id=new.requester_user_id) or (blocker_id=new.requester_user_id and blocked_id=new.owner_user_id)) then raise exception 'safety_interaction_unavailable' using errcode='42501'; end if;
  if new.event_id is not null and not exists(select 1 from public.otaku_events where id=new.event_id and publication_status='published') then raise exception 'safety_event_unavailable' using errcode='42501'; end if;
  new.created_at:=now(); return new;
end $$;

alter table public.otaku_content_reports drop constraint otaku_content_reports_kind_check;
alter table public.otaku_content_reports add constraint otaku_content_reports_kind_check check (kind=any(array['board','board_reply','goods','review']));

create or replace function otaku_private.content_report_guard()
returns trigger language plpgsql security definer set search_path=''
as $$
declare s jsonb; author uuid;
begin
  if auth.uid() is null or auth.uid()<>new.reporter_id then raise exception 'not_allowed' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('otaku-content-report:'||auth.uid(),0));
  if (select count(*) from public.otaku_content_reports where reporter_id=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'report_rate_limit' using errcode='23514'; end if;
  if new.kind='board' then select jsonb_build_object('title',title,'body',body,'event_id',event_id,'idol_id',idol_id),user_id into s,author from public.otaku_board_posts where id=new.target_id and not hidden and otaku_private.board_target_visible(event_id,idol_id);
  elsif new.kind='board_reply' then select jsonb_build_object('body',r.body,'post_id',r.post_id),r.user_id into s,author from public.otaku_board_replies r join public.otaku_board_posts p on p.id=r.post_id where r.id=new.target_id and not r.hidden and not p.hidden and otaku_private.board_target_visible(p.event_id,p.idol_id);
  elsif new.kind='goods' then select jsonb_build_object('item_name',item_name,'description',description,'trade_type',trade_type,'group_id',group_id),user_id into s,author from public.otaku_goods_posts where id=new.target_id and not hidden and status='open';
  else select jsonb_build_object('comment',comment,'rating',rating,'reviewee_id',reviewee_id),reviewer_id into s,author from public.otaku_reviews where id=new.target_id and visibility='visible'; end if;
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
  select * into r from public.otaku_content_reports where id=report for update; if not found then raise exception 'report_not_found' using errcode='23514'; end if;
  if action<>'resolve' then
    if r.kind='board' then update public.otaku_board_posts set hidden=(action='hide') where id=r.target_id;
    elsif r.kind='board_reply' then update public.otaku_board_replies set hidden=(action='hide') where id=r.target_id;
    elsif r.kind='goods' then update public.otaku_goods_posts set hidden=(action='hide') where id=r.target_id;
    else update public.otaku_reviews set visibility=case when action='hide' then 'hidden' else 'visible' end, moderation_reason=btrim(reason) where id=r.target_id; end if;
    if not found then raise exception 'content_not_found' using errcode='23514'; end if;
  end if;
  update public.otaku_content_reports set status=case when action='restore' then 'open' else 'resolved' end where id=report;
  insert into public.otaku_content_actions(report_id,actor_id,action,reason) values(report,auth.uid(),action,btrim(reason));
end $$;
