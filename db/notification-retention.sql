-- Delete OTAKU LIVE notifications 90 days after creation, as stated in the privacy policy
-- (通知・操作ログは90日). Migration name: otaku_notification_retention.
-- Runs daily at 03:30 JST via pg_cron. Only public.otaku_notifications is touched.
-- At apply time (2026-10-09) the table had 0 rows, so nothing existing was deleted.

create or replace function otaku_private.purge_expired_notifications()
 returns integer
 language plpgsql
 set search_path to ''
as $function$
declare n integer;
begin
  delete from public.otaku_notifications where created_at < now() - interval '90 days';
  get diagnostics n = row_count;
  return n;
end $function$;

revoke all on function otaku_private.purge_expired_notifications() from public, anon, authenticated;

select cron.schedule('otaku-notification-retention-daily', '30 18 * * *',
  'select otaku_private.purge_expired_notifications();');

-- Rollback:
--   select cron.unschedule('otaku-notification-retention-daily');
--   drop function otaku_private.purge_expired_notifications();
