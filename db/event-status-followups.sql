-- Purpose: follow up event status changes with schedule notices and cancelled-event guards.
-- Applied: 2026-10-10. Migration: otaku_event_status_followups.
-- Summary: suppress invalid reminders, notify schedule changes, and reject cancelled-event posts/DMs.

create or replace function otaku_private.run_event_reminders() returns integer
language plpgsql security definer set search_path to '' as $$
declare n integer:=0; begin
 insert into public.otaku_notifications(user_id,kind,title,body,href)
 select a.user_id,'event','公演がまもなく始まります',e.title||' は24時間以内に開催予定です。','event.html?id='||e.id::text
 from public.otaku_event_attendees a join public.otaku_events e on e.id=a.event_id
 join public.otaku_notification_preferences p on p.user_id=a.user_id
 where p.in_app_enabled and p.event_reminder_enabled and e.publication_status='published'
   and e.event_status not in ('cancelled','postponed')
   and e.starts_at between now() and now()+interval '24 hours'
   and not exists(select 1 from public.otaku_notifications x where x.user_id=a.user_id and x.kind='event' and x.title='公演がまもなく始まります' and x.href='event.html?id='||e.id::text and x.created_at>now()-interval '7 days');
 get diagnostics n=row_count; return n; end $$;
revoke all on function otaku_private.run_event_reminders() from public,anon,authenticated;

create or replace function otaku_private.notify_event_lifecycle() returns trigger
language plpgsql security definer set search_path='' as $$
declare title_text text; body_text text;
begin
 if auth.uid() is null or not public.otaku_is_catalog_admin() then raise exception 'catalog_admin_required' using errcode='42501'; end if;
 if TG_OP='INSERT' and new.publication_status='published' then
  insert into public.otaku_notifications(user_id,kind,title,body,href)
  select f.user_id,'event','お気に入りグループの新しい公演',new.title||'が公開されました。','event.html?id='||new.id from public.otaku_group_favorites f join public.otaku_notification_preferences p on p.user_id=f.user_id where f.group_id=new.group_id and f.notify and p.in_app_enabled and p.event_reminder_enabled; return new;
 end if;
 if TG_OP='UPDATE' and new.publication_status='published' and old.publication_status<>'published' then
  insert into public.otaku_notifications(user_id,kind,title,body,href)
  select f.user_id,'event','お気に入りグループの新しい公演',new.title||'が公開されました。','event.html?id='||new.id from public.otaku_group_favorites f join public.otaku_notification_preferences p on p.user_id=f.user_id where f.group_id=new.group_id and f.notify and p.in_app_enabled and p.event_reminder_enabled;
 end if;
 if TG_OP='UPDATE' and (new.event_status is distinct from old.event_status or new.status_note is distinct from old.status_note) then
  title_text:=case new.event_status when 'cancelled' then '公演中止のお知らせ' when 'postponed' then '公演延期のお知らせ' when 'changed' then '公演情報変更のお知らせ' else '公演情報更新のお知らせ' end;
  body_text:=coalesce(nullif(btrim(new.status_note),''),'公演情報が更新されました。公式出典をご確認ください。');
  insert into public.otaku_notifications(user_id,kind,title,body,href)
  select u.user_id,'event',title_text,body_text,'event.html?id='||new.id from (select a.user_id from public.otaku_event_attendees a where a.event_id=new.id union select f.user_id from public.otaku_event_favorites f where f.event_id=new.id and f.notify) u join public.otaku_notification_preferences p on p.user_id=u.user_id where p.in_app_enabled and p.event_reminder_enabled;
 end if; return new;
end $$;
revoke all on function otaku_private.notify_event_lifecycle() from public,anon,authenticated;

create or replace function otaku_private.notify_event_schedule_change() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.publication_status='published' and old.publication_status='published' and new.event_status is not distinct from old.event_status and new.status_note is not distinct from old.status_note and (new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at or new.venue is distinct from old.venue) then
  insert into public.otaku_notifications(user_id,kind,title,body,href)
  select u.user_id,'event','公演情報変更のお知らせ',new.title||' の日時・会場が変更されました。新しい日時: '||to_char(new.starts_at at time zone 'Asia/Tokyo','FMMM"月"FMDD"日" HH24:MI')||'（日本時間）、会場: '||new.venue||'。公式出典もご確認ください。','event.html?id='||new.id
  from (select a.user_id from public.otaku_event_attendees a where a.event_id=new.id union select f.user_id from public.otaku_event_favorites f where f.event_id=new.id and f.notify) u join public.otaku_notification_preferences p on p.user_id=u.user_id where p.in_app_enabled and p.event_reminder_enabled;
 end if; return new;
end $$;
revoke all on function otaku_private.notify_event_schedule_change() from public,anon,authenticated;
drop trigger if exists otaku_event_schedule_notify on public.otaku_events;
create trigger otaku_event_schedule_notify after update on public.otaku_events for each row execute function otaku_private.notify_event_schedule_change();

create or replace function otaku_private.reject_cancelled_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin if new.event_id is null then return new; end if; if exists(select 1 from public.otaku_events e where e.id=new.event_id and e.event_status='cancelled') then raise exception 'event_cancelled' using errcode='23514'; end if; return new; end $$;
revoke all on function otaku_private.reject_cancelled_event() from public,anon,authenticated;
drop trigger if exists otaku_cancelled_event_guard on public.otaku_companion_posts;
create trigger otaku_cancelled_event_guard before insert on public.otaku_companion_posts for each row execute function otaku_private.reject_cancelled_event();
drop trigger if exists otaku_cancelled_event_guard on public.otaku_conversations;
create trigger otaku_cancelled_event_guard before insert on public.otaku_conversations for each row execute function otaku_private.reject_cancelled_event();

-- Rollback:
-- drop trigger if exists otaku_event_schedule_notify on public.otaku_events;
-- drop trigger if exists otaku_cancelled_event_guard on public.otaku_companion_posts;
-- drop trigger if exists otaku_cancelled_event_guard on public.otaku_conversations;
-- drop function if exists otaku_private.notify_event_schedule_change();
-- drop function if exists otaku_private.reject_cancelled_event();
-- restore run_event_reminders and notify_event_lifecycle from db/event-status-notifications.sql and their current definitions above.
