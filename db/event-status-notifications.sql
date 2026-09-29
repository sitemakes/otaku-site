-- Notify only attendees who enabled site event notifications when an admin changes status.
create or replace function otaku_private.notify_event_status() returns trigger
language plpgsql security definer set search_path='' as $$
declare title_text text; body_text text;
begin
  if auth.uid() is null or not public.otaku_is_catalog_admin() then
    raise exception 'catalog_admin_required' using errcode='42501';
  end if;
  if new.event_status is not distinct from old.event_status
     and new.status_note is not distinct from old.status_note then return new; end if;
  title_text := case new.event_status
    when 'cancelled' then '公演中止のお知らせ'
    when 'postponed' then '公演延期のお知らせ'
    when 'changed' then '公演情報変更のお知らせ'
    else '公演情報更新のお知らせ' end;
  body_text := coalesce(nullif(btrim(new.status_note),''),'公演情報が更新されました。公式出典をご確認ください。');
  insert into public.otaku_notifications(user_id,kind,title,body,href)
  select a.user_id,'event',title_text,body_text,'event.html?id='||new.id
  from public.otaku_event_attendees a
  join public.otaku_notification_preferences p on p.user_id=a.user_id
  where a.event_id=new.id and p.in_app_enabled and p.event_reminder_enabled
    and not exists(select 1 from public.otaku_user_blocks b where
      (b.blocker_id=a.user_id and b.blocked_id=auth.uid()) or
      (b.blocker_id=auth.uid() and b.blocked_id=a.user_id));
  return new;
end $$;
revoke all on function otaku_private.notify_event_status() from public,anon,authenticated;
drop trigger if exists otaku_event_status_notify on public.otaku_events;
create trigger otaku_event_status_notify after update on public.otaku_events
for each row execute function otaku_private.notify_event_status();
