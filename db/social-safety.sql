-- Supabase migration: otaku_social_safety. Applies only to OTAKU LIVE objects.
create table public.otaku_user_blocks (
  blocker_id uuid not null references public.otaku_profiles(id) on delete cascade,
  blocked_id uuid not null references public.otaku_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker_id,blocked_id), check(blocker_id<>blocked_id)
);
create index otaku_blocks_target on public.otaku_user_blocks(blocked_id,blocker_id);
alter table public.otaku_user_blocks enable row level security;
revoke all on public.otaku_user_blocks from anon,authenticated;
grant select,insert,delete on public.otaku_user_blocks to authenticated;
create policy "otaku read own blocks" on public.otaku_user_blocks for select to authenticated using(blocker_id=(select auth.uid()));
create policy "otaku create own blocks" on public.otaku_user_blocks for insert to authenticated with check(blocker_id=(select auth.uid()));
create policy "otaku remove own blocks" on public.otaku_user_blocks for delete to authenticated using(blocker_id=(select auth.uid()));

-- A self-scoped boolean only; caller cannot inspect another user's block list.
create function otaku_private.can_interact(other_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and other_id is not null and not exists(
    select 1 from public.otaku_user_blocks
    where (blocker_id=auth.uid() and blocked_id=other_id) or (blocked_id=auth.uid() and blocker_id=other_id));
$$;
revoke all on function otaku_private.can_interact(uuid) from public,anon;
grant usage on schema otaku_private to authenticated;
grant execute on function otaku_private.can_interact(uuid) to authenticated;

create function otaku_private.block_guard() returns trigger
language plpgsql security invoker set search_path='' as $$
declare a uuid; b uuid;
begin
  if TG_OP='DELETE' then a:=old.blocker_id; b:=old.blocked_id; else a:=new.blocker_id; b:=new.blocked_id; new.created_at:=now(); end if;
  if auth.uid() is null or auth.uid()<>a then raise exception 'safety_not_allowed' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(a,b)::text||greatest(a,b)::text,0));
  if TG_OP='DELETE' then return old; end if; return new;
end $$;
create trigger otaku_block_guard before insert or delete on public.otaku_user_blocks for each row execute function otaku_private.block_guard();

alter table public.otaku_companion_posts add column closed_at timestamptz;
create function otaku_private.post_guard() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if auth.uid() is null or new.user_id<>auth.uid() then raise exception 'safety_not_allowed' using errcode='42501'; end if;
  if TG_OP='UPDATE' then
    if new.id<>old.id or new.user_id<>old.user_id or new.event_id<>old.event_id or new.created_at<>old.created_at then
      raise exception 'safety_identity_immutable' using errcode='23514';
    end if;
    if old.status='closed' and new.status<>'closed' then raise exception 'post_already_closed' using errcode='23514'; end if;
    if old.status='closed' then new.closed_at:=old.closed_at; else new.closed_at:=case when new.status='closed' then now() else null end; end if;
  else
    new.created_at:=now(); new.closed_at:=case when new.status='closed' then now() else null end;
    if not exists(select 1 from public.otaku_events where id=new.event_id and publication_status='published') then
      raise exception 'safety_event_unavailable' using errcode='23514'; end if;
  end if;
  new.body:=btrim(new.body);
  if new.body='' then raise exception 'safety_content_required' using errcode='23514'; end if;
  return new;
end $$;
create trigger otaku_post_guard before insert or update on public.otaku_companion_posts for each row execute function otaku_private.post_guard();
drop policy "otaku companion posts readable by authenticated" on public.otaku_companion_posts;
create policy "otaku visible companion posts" on public.otaku_companion_posts for select to authenticated
  using(user_id=(select auth.uid()) or (status='open' and otaku_private.can_interact(user_id)));
-- Keep owner-only UPDATE/INSERT policies; remove identity-changing column privileges.
revoke update on public.otaku_companion_posts from authenticated;
grant update(status,body,type,preferred_gender,preferred_age_min,preferred_age_max,same_oshi_ok) on public.otaku_companion_posts to authenticated;

-- Locks serialize block/send and close/start races. These private triggers explicitly
-- authorize the actor before using their narrowly scoped privileged lookups.
create function otaku_private.conversation_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare p public.otaku_companion_posts;
begin
  if auth.uid() is null or new.requester_user_id<>auth.uid() or new.owner_user_id=auth.uid() then
    raise exception 'safety_not_allowed' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(new.owner_user_id,new.requester_user_id)::text||greatest(new.owner_user_id,new.requester_user_id)::text,0));
  select * into p from public.otaku_companion_posts where id=new.companion_post_id for share;
  if not found or p.status<>'open' or p.user_id<>new.owner_user_id or p.event_id<>new.event_id then
    raise exception 'safety_post_unavailable' using errcode='42501'; end if;
  if exists(select 1 from public.otaku_user_blocks where
    (blocker_id=new.owner_user_id and blocked_id=new.requester_user_id) or
    (blocker_id=new.requester_user_id and blocked_id=new.owner_user_id)) then
    raise exception 'safety_interaction_unavailable' using errcode='42501'; end if;
  if not exists(select 1 from public.otaku_events where id=new.event_id and publication_status='published') then
    raise exception 'safety_event_unavailable' using errcode='42501'; end if;
  new.created_at:=now(); return new;
end $$;
create trigger otaku_conversation_guard before insert on public.otaku_conversations for each row execute function otaku_private.conversation_guard();
drop policy "otaku conversation participants can read" on public.otaku_conversations;
create policy "otaku unblocked conversation participants" on public.otaku_conversations for select to authenticated
using(((select auth.uid())=owner_user_id and otaku_private.can_interact(requester_user_id)) or
      ((select auth.uid())=requester_user_id and otaku_private.can_interact(owner_user_id)));
drop policy "otaku requester can open valid conversation" on public.otaku_conversations;
create policy "otaku requester opens active unblocked post" on public.otaku_conversations for insert to authenticated
with check(requester_user_id=(select auth.uid()) and owner_user_id<>requester_user_id and otaku_private.can_interact(owner_user_id)
  and exists(select 1 from public.otaku_companion_posts p where p.id=otaku_conversations.companion_post_id
    and p.event_id=otaku_conversations.event_id and p.user_id=otaku_conversations.owner_user_id and p.status='open'));

create function otaku_private.message_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.otaku_conversations;
begin
  if auth.uid() is null or new.sender_id<>auth.uid() then raise exception 'safety_not_allowed' using errcode='42501'; end if;
  select * into c from public.otaku_conversations where id=new.conversation_id;
  if not found or auth.uid() not in (c.owner_user_id,c.requester_user_id) then raise exception 'safety_not_allowed' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(c.owner_user_id,c.requester_user_id)::text||greatest(c.owner_user_id,c.requester_user_id)::text,0));
  if exists(select 1 from public.otaku_user_blocks where
    (blocker_id=c.owner_user_id and blocked_id=c.requester_user_id) or
    (blocker_id=c.requester_user_id and blocked_id=c.owner_user_id)) then
    raise exception 'safety_interaction_unavailable' using errcode='42501'; end if;
  new.content:=btrim(new.content); if new.content='' then raise exception 'safety_content_required' using errcode='23514'; end if;
  new.created_at:=now(); return new;
end $$;
create trigger otaku_message_guard before insert on public.otaku_messages for each row execute function otaku_private.message_guard();
-- Existing messages SELECT/INSERT policies follow conversation RLS automatically.

alter table public.otaku_reports add column companion_post_id uuid references public.otaku_companion_posts(id) on delete set null,
  add column message_id uuid references public.otaku_messages(id) on delete set null,
  add column updated_at timestamptz not null default now(),
  add column revision integer not null default 1;
create index otaku_reports_context_post on public.otaku_reports(companion_post_id);
create index otaku_reports_context_message on public.otaku_reports(message_id);
create index otaku_reports_actor_date on public.otaku_reports(reporter_id,created_at);
create table public.otaku_report_evidence (
  report_id uuid primary key references public.otaku_reports(id) on delete cascade,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);
create table public.otaku_report_actions (
  id bigint generated always as identity primary key,
  report_id uuid not null references public.otaku_reports(id) on delete cascade,
  actor_id uuid not null,
  from_status text not null,
  to_status text not null,
  created_at timestamptz not null default now()
);
create index otaku_report_actions_report on public.otaku_report_actions(report_id);
alter table public.otaku_report_evidence enable row level security;
alter table public.otaku_report_actions enable row level security;
revoke all on public.otaku_report_evidence,public.otaku_report_actions from anon,authenticated;
grant select on public.otaku_report_evidence,public.otaku_report_actions to authenticated;
create policy "otaku admins read report evidence" on public.otaku_report_evidence for select to authenticated using((select public.otaku_is_catalog_admin()));
create policy "otaku admins read report actions" on public.otaku_report_actions for select to authenticated using((select public.otaku_is_catalog_admin()));

create function otaku_private.report_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.otaku_conversations; p public.otaku_companion_posts; m public.otaku_messages;
begin
  if auth.uid() is null then raise exception 'safety_not_allowed' using errcode='42501'; end if;
  if TG_OP='UPDATE' then
    if not exists(select 1 from public.otaku_catalog_admins where user_id=auth.uid()) then raise exception 'safety_not_allowed' using errcode='42501'; end if;
    if (to_jsonb(new)-array['status','revision','updated_at']) is distinct from (to_jsonb(old)-array['status','revision','updated_at']) then
      raise exception 'safety_identity_immutable' using errcode='23514'; end if;
    new.revision:=old.revision+1; new.updated_at:=now(); return new;
  end if;
  if new.reporter_id<>auth.uid() or new.reporter_id=new.target_user_id or new.status<>'open' then
    raise exception 'safety_not_allowed' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('otaku-report:'||auth.uid()::text,0));
  if (select count(*) from public.otaku_reports where reporter_id=auth.uid() and created_at>now()-interval '24 hours')>=20 then
    raise exception 'report_rate_limit' using errcode='23514'; end if;
  if exists(select 1 from public.otaku_reports where reporter_id=auth.uid() and target_user_id=new.target_user_id
    and conversation_id is not distinct from new.conversation_id and companion_post_id is not distinct from new.companion_post_id
    and message_id is not distinct from new.message_id and status in ('open','reviewing')) then
    raise exception 'report_duplicate' using errcode='23514'; end if;
  if new.conversation_id is not null then
    select * into c from public.otaku_conversations where id=new.conversation_id;
    if not found or not ((c.owner_user_id=auth.uid() and c.requester_user_id=new.target_user_id) or
      (c.requester_user_id=auth.uid() and c.owner_user_id=new.target_user_id)) then
      raise exception 'report_invalid_context' using errcode='23514'; end if;
  end if;
  if new.companion_post_id is not null then
    select * into p from public.otaku_companion_posts where id=new.companion_post_id;
    if not found or p.user_id<>new.target_user_id then raise exception 'report_invalid_context' using errcode='23514'; end if;
    if new.conversation_id is not null and c.companion_post_id<>new.companion_post_id then
      raise exception 'report_invalid_context' using errcode='23514'; end if;
  end if;
  if new.message_id is not null then
    select * into m from public.otaku_messages where id=new.message_id;
    if not found or new.conversation_id is null or m.conversation_id<>new.conversation_id or m.sender_id<>new.target_user_id then
      raise exception 'report_invalid_context' using errcode='23514'; end if;
  end if;
  new.details:=nullif(btrim(new.details),'');
  if new.reason='other' and new.details is null then raise exception 'report_details_required' using errcode='23514'; end if;
  new.created_at:=now(); new.updated_at:=now(); new.revision:=1; return new;
end $$;
create function otaku_private.report_record() returns trigger
language plpgsql security definer set search_path='' as $$
declare evidence jsonb;
begin
  if auth.uid() is null then raise exception 'safety_not_allowed' using errcode='42501'; end if;
  if TG_OP='INSERT' then
    if new.reporter_id<>auth.uid() then raise exception 'safety_not_allowed' using errcode='42501'; end if;
    evidence:=jsonb_build_object('target_name',(select display_name from public.otaku_profiles where id=new.target_user_id),
      'post',(select jsonb_build_object('body',body,'event_id',event_id,'status',status) from public.otaku_companion_posts where id=new.companion_post_id),
      'message',(select jsonb_build_object('content',content,'created_at',created_at) from public.otaku_messages where id=new.message_id));
    insert into public.otaku_report_evidence(report_id,snapshot) values(new.id,evidence);
  elsif old.status<>new.status then
    if not exists(select 1 from public.otaku_catalog_admins where user_id=auth.uid()) then raise exception 'safety_not_allowed' using errcode='42501'; end if;
    insert into public.otaku_report_actions(report_id,actor_id,from_status,to_status) values(new.id,auth.uid(),old.status,new.status);
  end if;
  return new;
end $$;
create trigger otaku_report_guard before insert or update on public.otaku_reports for each row execute function otaku_private.report_guard();
create trigger otaku_report_record after insert or update on public.otaku_reports for each row execute function otaku_private.report_record();
revoke all on public.otaku_reports from anon,authenticated;
grant select,insert on public.otaku_reports to authenticated;
grant update(status) on public.otaku_reports to authenticated;
create policy "otaku admins read reports" on public.otaku_reports for select to authenticated using((select public.otaku_is_catalog_admin()));
create policy "otaku admins update report status" on public.otaku_reports for update to authenticated
using((select public.otaku_is_catalog_admin())) with check((select public.otaku_is_catalog_admin()));
-- Trigger helpers are never direct public APIs.
revoke all on function otaku_private.block_guard(),otaku_private.post_guard(),otaku_private.conversation_guard(),
  otaku_private.message_guard(),otaku_private.report_guard(),otaku_private.report_record() from public,anon,authenticated;
