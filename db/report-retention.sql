-- Keep user reports and their evidence after the reporter or the reported user withdraws,
-- matching the privacy policy (safety records are kept for 2 years after handling).
-- Migration name: otaku_report_retention. Additive: old frontends keep working.
--
-- Before: otaku_reports.reporter_id / target_user_id and otaku_content_reports.reporter_id
-- were ON DELETE CASCADE, so otaku_withdraw() erased reports filed by or against the user.
-- After: the user id is set to NULL and the report, evidence snapshot and action history stay.
-- The guard triggers let through only that FK cascade (status and every other column unchanged).

alter table public.otaku_reports alter column reporter_id drop not null;
alter table public.otaku_reports alter column target_user_id drop not null;
alter table public.otaku_content_reports alter column reporter_id drop not null;

-- Same constraint names: reports.js embeds otaku_profiles!otaku_reports_reporter_id_fkey.
alter table public.otaku_reports drop constraint otaku_reports_reporter_id_fkey,
  add constraint otaku_reports_reporter_id_fkey foreign key (reporter_id) references public.otaku_profiles(id) on delete set null;
alter table public.otaku_reports drop constraint otaku_reports_target_user_id_fkey,
  add constraint otaku_reports_target_user_id_fkey foreign key (target_user_id) references public.otaku_profiles(id) on delete set null;
alter table public.otaku_content_reports drop constraint otaku_content_reports_reporter_id_fkey,
  add constraint otaku_content_reports_reporter_id_fkey foreign key (reporter_id) references public.otaku_profiles(id) on delete set null;

create or replace function otaku_private.report_guard()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare c public.otaku_conversations; p public.otaku_companion_posts; m public.otaku_messages;
begin
  -- FK ON DELETE SET NULL when a profile, conversation, post or message is deleted (withdrawal):
  -- referenced ids may only become NULL; status and every other column stay unchanged.
  if TG_OP='UPDATE' and pg_trigger_depth()>1
    and (to_jsonb(new)-array['reporter_id','target_user_id','conversation_id','companion_post_id','message_id'])
      = (to_jsonb(old)-array['reporter_id','target_user_id','conversation_id','companion_post_id','message_id'])
    and (new.reporter_id is null or new.reporter_id=old.reporter_id)
    and (new.target_user_id is null or new.target_user_id=old.target_user_id)
    and (new.conversation_id is null or new.conversation_id=old.conversation_id)
    and (new.companion_post_id is null or new.companion_post_id=old.companion_post_id)
    and (new.message_id is null or new.message_id=old.message_id) then
    return new;
  end if;
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
end $function$;

create or replace function otaku_private.report_record()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare evidence jsonb;
begin
  -- Nothing to record unless the status changed (e.g. the FK cascade on withdrawal).
  if TG_OP='UPDATE' and new.status is not distinct from old.status then return new; end if;
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
end $function$;

-- Rollback: re-run both functions without the two early-return blocks marked above (the rest is
-- the live definition as of 2026-10-09), recreate the three FKs with ON DELETE CASCADE, and set
-- NOT NULL again. Reports whose ids became NULL must first be deleted or kept by not restoring
-- NOT NULL; decide that with a human before running it.
