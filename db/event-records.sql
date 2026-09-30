create table if not exists public.otaku_event_records (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.otaku_events(id) on delete cascade,
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  impression text,
  setlist text,
  attendance_note text,
  visibility text not null default 'public',
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, user_id),
  constraint otaku_event_records_visibility_check check (visibility in ('public','private')),
  constraint otaku_event_records_impression_check check (impression is null or char_length(btrim(impression)) between 1 and 3000),
  constraint otaku_event_records_setlist_check check (setlist is null or char_length(btrim(setlist)) between 1 and 5000),
  constraint otaku_event_records_attendance_check check (attendance_note is null or char_length(btrim(attendance_note)) between 1 and 2000)
);
create index if not exists otaku_event_records_event_updated_idx on public.otaku_event_records(event_id, updated_at desc);
create index if not exists otaku_event_records_user_idx on public.otaku_event_records(user_id);
alter table public.otaku_event_records enable row level security;
revoke all on public.otaku_event_records from public, anon, authenticated;
grant select on public.otaku_event_records to anon, authenticated;
grant insert, update, delete on public.otaku_event_records to authenticated;

drop policy if exists event_records_anon_read on public.otaku_event_records;
drop policy if exists event_records_authenticated_read on public.otaku_event_records;
drop policy if exists event_records_own_insert on public.otaku_event_records;
drop policy if exists event_records_own_update on public.otaku_event_records;
drop policy if exists event_records_own_delete on public.otaku_event_records;
create policy event_records_anon_read on public.otaku_event_records
  for select to anon using (visibility='public' and not hidden);
create policy event_records_authenticated_read on public.otaku_event_records
  for select to authenticated
  using (user_id=(select auth.uid()) or (visibility='public' and not hidden and otaku_private.can_interact(user_id)));
create policy event_records_own_insert on public.otaku_event_records
  for insert to authenticated with check (user_id=(select auth.uid()));
create policy event_records_own_update on public.otaku_event_records
  for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy event_records_own_delete on public.otaku_event_records
  for delete to authenticated using (user_id=(select auth.uid()));

revoke update on public.otaku_event_records from authenticated;
grant update(impression,setlist,attendance_note,visibility) on public.otaku_event_records to authenticated;

create or replace function otaku_private.event_record_guard()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare ended_at timestamptz;
begin
  if tg_op='UPDATE' and public.otaku_is_catalog_admin() then new.updated_at:=now(); return new; end if;
  if auth.uid() is null or new.user_id<>auth.uid() then raise exception 'event_record_not_allowed' using errcode='42501'; end if;
  if tg_op='UPDATE' and (to_jsonb(new)-array['impression','setlist','attendance_note','visibility','updated_at'])
      is distinct from (to_jsonb(old)-array['impression','setlist','attendance_note','visibility','updated_at']) then
    raise exception 'event_record_not_allowed' using errcode='42501';
  end if;
  select coalesce(ends_at,starts_at) into ended_at from public.otaku_events where id=new.event_id and publication_status='published';
  if ended_at is null or ended_at>now() then raise exception 'event_record_event_not_finished' using errcode='42501'; end if;
  new.impression:=nullif(btrim(new.impression),''); new.setlist:=nullif(btrim(new.setlist),''); new.attendance_note:=nullif(btrim(new.attendance_note),'');
  if new.impression is null and new.setlist is null and new.attendance_note is null then raise exception 'event_record_content_required' using errcode='23514'; end if;
  if tg_op='INSERT' then new.hidden:=false; new.created_at:=now(); end if;
  new.updated_at:=now(); return new;
end $$;
drop trigger if exists otaku_event_record_guard on public.otaku_event_records;
create trigger otaku_event_record_guard before insert or update on public.otaku_event_records
for each row execute function otaku_private.event_record_guard();
revoke all on function otaku_private.event_record_guard() from public, anon, authenticated;

alter table public.otaku_content_reports drop constraint if exists otaku_content_reports_kind_check;
alter table public.otaku_content_reports add constraint otaku_content_reports_kind_check
  check (kind=any(array['board','board_reply','goods','review','event_record']));

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
  elsif new.kind='event_record' then select jsonb_build_object('impression',impression,'setlist',setlist,'attendance_note',attendance_note,'event_id',event_id),user_id into s,author from public.otaku_event_records where id=new.target_id and not hidden and visibility='public';
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
    elsif r.kind='event_record' then update public.otaku_event_records set hidden=(action='hide') where id=r.target_id;
    else update public.otaku_reviews set visibility=case when action='hide' then 'hidden' else 'visible' end, moderation_reason=btrim(reason) where id=r.target_id; end if;
    if not found then raise exception 'content_not_found' using errcode='23514'; end if;
  end if;
  update public.otaku_content_reports set status=case when action='restore' then 'open' else 'resolved' end where id=report;
  insert into public.otaku_content_actions(report_id,actor_id,action,reason) values(report,auth.uid(),action,btrim(reason));
end $$;
