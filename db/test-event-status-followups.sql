-- MCP で実行するときは、最後の notice を raise exception に変えると結果が返る。
-- All fixtures are rolled back.
begin;
do $$
declare admin_id uuid; source_id uuid; u1 uuid:=gen_random_uuid(); u2 uuid:=gen_random_uuid(); e1 uuid; e2 uuid; e3 uuid; post_id uuid; checks int:=0; n int;
begin
 select user_id into admin_id from public.otaku_catalog_admins limit 1;
 select id into source_id from public.otaku_events where publication_status='published' and starts_at>now() limit 1;
 if admin_id is null or source_id is null then raise exception 'Need an admin and a future published event'; end if;
 insert into auth.users(id,email) values(u1,u1||'@status-test.invalid'),(u2,u2||'@status-test.invalid');
 insert into public.otaku_profiles(id,username,display_name) values(u1,'status_'||substr(replace(u1::text,'-',''),1,12),'Status U1'),(u2,'status_'||substr(replace(u2::text,'-',''),1,12),'Status U2');
 insert into public.otaku_notification_preferences(user_id,in_app_enabled,event_reminder_enabled) values(u1,true,true),(u2,true,true) on conflict(user_id) do update set in_app_enabled=true,event_reminder_enabled=true;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 insert into public.otaku_events(group_id,is_demo,title,venue,prefecture,city,source_url,source_kind,source_checked_at,publication_status,starts_at,ends_at)
 select group_id,is_demo,'[status test] E1',venue,prefecture,city,source_url,source_kind,now(),'published',now()+interval '12 hours',ends_at from public.otaku_events where id=source_id returning id into e1;
 insert into public.otaku_events(group_id,is_demo,title,venue,prefecture,city,source_url,source_kind,source_checked_at,publication_status,starts_at,ends_at)
 select group_id,is_demo,'[status test] E2',venue,prefecture,city,source_url,source_kind,now(),'published',now()+interval '12 hours',ends_at from public.otaku_events where id=source_id returning id into e2;
 insert into public.otaku_events(group_id,is_demo,title,venue,prefecture,city,source_url,source_kind,source_checked_at,publication_status,starts_at,ends_at)
 select group_id,is_demo,'[status test] E3',venue,prefecture,city,source_url,source_kind,now(),'published',now()+interval '3 days',ends_at from public.otaku_events where id=source_id returning id into e3;
 perform set_config('request.jwt.claim.sub',u1::text,true); execute 'set local role authenticated';
 insert into public.otaku_event_attendees(user_id,event_id) values(u1,e1),(u1,e2),(u1,e3); insert into public.otaku_event_favorites(user_id,event_id,notify) values(u1,e3,true);
 execute 'reset role'; perform set_config('request.jwt.claim.sub',admin_id::text,true);
 update public.otaku_events set event_status='cancelled',status_note='中止' where id=e1; perform otaku_private.run_event_reminders();
 if exists(select 1 from public.otaku_notifications where user_id=u1 and title='公演がまもなく始まります' and href='event.html?id='||e1) then raise exception 'FAIL E1 reminder'; end if; checks:=checks+1;
 perform otaku_private.run_event_reminders(); select count(*) into n from public.otaku_notifications where user_id=u1 and title='公演がまもなく始まります' and href='event.html?id='||e2; if n<>1 then raise exception 'FAIL E2 reminder'; end if; checks:=checks+1;
 update public.otaku_events set starts_at=starts_at+interval '1 day' where id=e3; select count(*) into n from public.otaku_notifications where user_id=u1 and title='公演情報変更のお知らせ' and href='event.html?id='||e3; if n<>1 then raise exception 'FAIL schedule notice'; end if; checks:=checks+1;
 update public.otaku_events set event_status='changed',status_note='変更' where id=e3; select count(*) into n from public.otaku_notifications where user_id=u1 and title='公演情報変更のお知らせ' and href='event.html?id='||e3; if n<>2 then raise exception 'FAIL status notice'; end if; checks:=checks+1;
 perform set_config('request.jwt.claim.sub',u2::text,true); execute 'set local role authenticated';
 begin insert into public.otaku_companion_posts(event_id,user_id,type,body) values(e1,u2,'looking_for_friend','cancelled'); raise exception 'FAIL cancelled accepted'; exception when sqlstate '23514' then if sqlerrm<>'event_cancelled' then raise; end if; checks:=checks+1; end;
 insert into public.otaku_companion_posts(event_id,user_id,type,body) values(e2,u2,'looking_for_friend','allowed') returning id into post_id; checks:=checks+1;
 raise notice 'PASS % checks',checks;
end $$;
rollback;
