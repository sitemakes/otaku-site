-- Notify attendees and favorites about published event changes.
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
  select a.user_id,'event',title_text,body_text,'event.html?id='||new.id from public.otaku_event_attendees a join public.otaku_notification_preferences p on p.user_id=a.user_id where a.event_id=new.id and p.in_app_enabled and p.event_reminder_enabled;
  insert into public.otaku_notifications(user_id,kind,title,body,href)
  select f.user_id,'event',title_text,body_text,'event.html?id='||new.id from public.otaku_event_favorites f join public.otaku_notification_preferences p on p.user_id=f.user_id where f.event_id=new.id and f.notify and p.in_app_enabled and p.event_reminder_enabled;
 end if;
 return new;
end $$;
revoke all on function otaku_private.notify_event_lifecycle() from public,anon,authenticated;
drop trigger if exists otaku_event_status_notify on public.otaku_events;
drop trigger if exists otaku_event_lifecycle_notify on public.otaku_events;
create trigger otaku_event_lifecycle_notify after insert or update on public.otaku_events for each row execute function otaku_private.notify_event_lifecycle();
