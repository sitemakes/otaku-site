-- MCP 縺ｧ螳溯｡後☆繧九→縺阪・縲∵怙蠕後・ notice 繧・raise exception 縺ｫ螟峨∴繧九→邨先棡縺瑚ｿ斐ｋ縲・-- All fixtures are rolled back.
begin;
do $$
declare
  admin_id uuid;
  source_id uuid;
  r_id uuid := gen_random_uuid();
  s_id uuid := gen_random_uuid();
  event_id uuid;
  post_id uuid;
  conversation_id uuid;
  n_before int;
  n_after int;
  checks int := 0;
begin
  select user_id into admin_id from public.otaku_catalog_admins limit 1;
  select id into source_id
    from public.otaku_events
   where publication_status = 'published' and starts_at > now()
   limit 1;
  if admin_id is null or source_id is null then
    raise exception 'Need an admin and a future published event';
  end if;

  insert into auth.users(id,email)
  values (r_id,r_id||'@notify-test.invalid'),(s_id,s_id||'@notify-test.invalid');
  insert into public.otaku_profiles(id,username,display_name)
  values
    (r_id,'notify_'||substr(replace(r_id::text,'-',''),1,12),'Notify R'),
    (s_id,'notify_'||substr(replace(s_id::text,'-',''),1,12),'Notify S');
  reset role;
  insert into public.otaku_notification_preferences
    (user_id,in_app_enabled,dm_enabled,board_enabled,event_reminder_enabled)
  values (r_id,true,true,true,true)
  on conflict(user_id) do update set
    in_app_enabled=true,dm_enabled=true,board_enabled=true,event_reminder_enabled=true;

  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  insert into public.otaku_events
    (group_id,is_demo,title,venue,prefecture,city,source_url,source_kind,
     source_checked_at,publication_status,starts_at,ends_at)
  select group_id,is_demo,'[notification preference test]',venue,prefecture,city,
    source_url,source_kind,now(),'published',now()+interval '3 days',ends_at
    from public.otaku_events where id=source_id
    returning id into event_id;

  perform set_config('request.jwt.claim.sub',r_id::text,true);
  execute 'set local role authenticated';
  insert into public.otaku_companion_posts(event_id,user_id,type,body)
    values(event_id,r_id,'looking_for_friend','notification preference test')
    returning id into post_id;
  perform set_config('request.jwt.claim.sub',s_id::text,true);
  insert into public.otaku_conversations(event_id,companion_post_id,owner_user_id,requester_user_id)
    values(event_id,post_id,r_id,s_id) returning id into conversation_id;
  insert into public.otaku_messages(conversation_id,sender_id,content)
    values(conversation_id,s_id,'DM 1');
  reset role;
  select count(*) into n_after from public.otaku_notifications
   where user_id=r_id and kind='dm';
  if n_after<>1 then raise exception 'FAIL DM enabled'; end if;
  checks:=checks+1;

  insert into public.otaku_notification_preferences(user_id,in_app_enabled,dm_enabled,board_enabled,event_reminder_enabled)
    values(r_id,true,false,true,true)
    on conflict(user_id) do update set in_app_enabled=true,dm_enabled=false,board_enabled=true,event_reminder_enabled=true;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub',s_id::text,true);
  insert into public.otaku_messages(conversation_id,sender_id,content) values(conversation_id,s_id,'DM 2');
  reset role;
  select count(*) into n_after from public.otaku_notifications where user_id=r_id and kind='dm';
  if n_after<>1 then raise exception 'FAIL DM kind disabled'; end if;
  checks:=checks+1;

  insert into public.otaku_notification_preferences(user_id,in_app_enabled,dm_enabled,board_enabled,event_reminder_enabled)
    values(r_id,false,true,true,true)
    on conflict(user_id) do update set in_app_enabled=false,dm_enabled=true,board_enabled=true,event_reminder_enabled=true;
  execute 'set local role authenticated';
  insert into public.otaku_messages(conversation_id,sender_id,content) values(conversation_id,s_id,'DM 3');
  reset role;
  select count(*) into n_after from public.otaku_notifications where user_id=r_id and kind='dm';
  if n_after<>1 then raise exception 'FAIL DM globally disabled'; end if;
  checks:=checks+1;

  insert into public.otaku_notification_preferences(user_id,in_app_enabled,dm_enabled,board_enabled,event_reminder_enabled)
    values(r_id,true,true,true,true)
    on conflict(user_id) do update set in_app_enabled=true,dm_enabled=true,board_enabled=true,event_reminder_enabled=true;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub',r_id::text,true);
  insert into public.otaku_board_posts(user_id,event_id,category,title,body)
    values(r_id,event_id,'event_info','R post','R board post') returning id into post_id;
  perform set_config('request.jwt.claim.sub',s_id::text,true);
  insert into public.otaku_board_posts(user_id,event_id,category,title,body)
    values(s_id,event_id,'event_info','S post 1','S board post 1');
  reset role;
  select count(*) into n_after from public.otaku_notifications where user_id=r_id and kind='board';
  if n_after<>1 then raise exception 'FAIL board post enabled'; end if;
  checks:=checks+1;

  insert into public.otaku_notification_preferences(user_id,in_app_enabled,dm_enabled,board_enabled,event_reminder_enabled)
    values(r_id,true,true,false,true)
    on conflict(user_id) do update set in_app_enabled=true,dm_enabled=true,board_enabled=false,event_reminder_enabled=true;
  execute 'set local role authenticated';
  insert into public.otaku_board_posts(user_id,event_id,category,title,body)
    values(s_id,event_id,'event_info','S post 2','S board post 2');
  reset role;
  select count(*) into n_after from public.otaku_notifications where user_id=r_id and kind='board';
  if n_after<>1 then raise exception 'FAIL board kind disabled'; end if;
  checks:=checks+1;

  insert into public.otaku_notification_preferences(user_id,in_app_enabled,dm_enabled,board_enabled,event_reminder_enabled)
    values(r_id,true,true,true,true)
    on conflict(user_id) do update set in_app_enabled=true,dm_enabled=true,board_enabled=true,event_reminder_enabled=true;
  execute 'set local role authenticated';
  insert into public.otaku_board_replies(post_id,user_id,body) values(post_id,s_id,'Reply 1');
  reset role;
  select count(*) into n_after from public.otaku_notifications where user_id=r_id and kind='board';
  if n_after<>2 then raise exception 'FAIL board reply enabled'; end if;
  checks:=checks+1;

  insert into public.otaku_notification_preferences(user_id,in_app_enabled,dm_enabled,board_enabled,event_reminder_enabled)
    values(r_id,true,true,false,true)
    on conflict(user_id) do update set in_app_enabled=true,dm_enabled=true,board_enabled=false,event_reminder_enabled=true;
  execute 'set local role authenticated';
  insert into public.otaku_board_replies(post_id,user_id,body) values(post_id,s_id,'Reply 2');
  reset role;
  select count(*) into n_after from public.otaku_notifications where user_id=r_id and kind='board';
  if n_after<>2 then raise exception 'FAIL board reply kind disabled'; end if;
  checks:=checks+1;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub',r_id::text,true);
  insert into public.otaku_event_attendees(user_id,event_id) values(r_id,event_id);
  reset role;
  insert into public.otaku_notification_preferences(user_id,in_app_enabled,dm_enabled,board_enabled,event_reminder_enabled)
    values(r_id,true,true,true,false)
    on conflict(user_id) do update set in_app_enabled=true,dm_enabled=true,board_enabled=true,event_reminder_enabled=false;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  update public.otaku_events set starts_at=starts_at+interval '1 day' where id=event_id;
  select count(*) into n_after from public.otaku_notifications where user_id=r_id and kind='event';
  if n_after<>0 then raise exception 'FAIL event reminder disabled'; end if;
  checks:=checks+1;
  insert into public.otaku_notification_preferences(user_id,in_app_enabled,dm_enabled,board_enabled,event_reminder_enabled)
    values(r_id,true,true,true,true)
    on conflict(user_id) do update set in_app_enabled=true,dm_enabled=true,board_enabled=true,event_reminder_enabled=true;
  update public.otaku_events set starts_at=starts_at+interval '1 day' where id=event_id;
  select count(*) into n_after from public.otaku_notifications where user_id=r_id and kind='event';
  if n_after<>1 then raise exception 'FAIL event reminder enabled'; end if;
  checks:=checks+1;

  raise notice 'PASS % checks', checks;
end $$;
rollback;
