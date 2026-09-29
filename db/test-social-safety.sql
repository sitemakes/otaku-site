-- Run against the existing MVP after social-safety.sql. All fixtures roll back.
begin;
do $$
declare
  v_a uuid:=gen_random_uuid(); v_b uuid:=gen_random_uuid(); v_c uuid:=gen_random_uuid();
  v_admin uuid; v_event uuid; v_event2 uuid; v_post uuid; v_post2 uuid;
  v_conv uuid; v_msg uuid; v_report uuid; v_n integer; v_checks integer:=0;
begin
  select user_id into v_admin from public.otaku_catalog_admins limit 1;
  select id into v_event from public.otaku_events where publication_status='published' order by id limit 1;
  select id into v_event2 from public.otaku_events where publication_status='published' and id<>v_event order by id limit 1;
  if v_admin is null or v_event2 is null then raise exception 'Need an admin and two published events'; end if;
  insert into auth.users(id,email) values(v_a,v_a||'@safety-test.invalid'),(v_b,v_b||'@safety-test.invalid'),(v_c,v_c||'@safety-test.invalid');
  insert into public.otaku_profiles(id,username,display_name) values
    (v_a,'test_'||substr(replace(v_a::text,'-',''),1,12),'Safety A'),
    (v_b,'test_'||substr(replace(v_b::text,'-',''),1,12),'Safety B'),
    (v_c,'test_'||substr(replace(v_c::text,'-',''),1,12),'Safety C');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub',v_a::text,true);
  insert into public.otaku_companion_posts(event_id,user_id,type,body) values(v_event,v_a,'looking_for_friend','Test recruitment') returning id into v_post;
  insert into public.otaku_companion_posts(event_id,user_id,type,body) values(v_event,v_a,'looking_for_friend','Another recruitment') returning id into v_post2;
  begin
    update public.otaku_companion_posts set event_id=v_event2 where id=v_post;
    raise exception 'Identity update accepted';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  perform set_config('request.jwt.claim.sub',v_b::text,true);
  update public.otaku_companion_posts set status='closed' where id=v_post;
  get diagnostics v_n=row_count;
  if v_n<>0 then raise exception 'Non-owner closed post'; end if; v_checks:=v_checks+1;
  begin
    insert into public.otaku_conversations(event_id,companion_post_id,owner_user_id,requester_user_id) values(v_event2,v_post,v_a,v_b);
    raise exception 'Wrong event accepted';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  insert into public.otaku_conversations(event_id,companion_post_id,owner_user_id,requester_user_id) values(v_event,v_post,v_a,v_b) returning id into v_conv;
  insert into public.otaku_messages(conversation_id,sender_id,content) values(v_conv,v_b,'Selected report evidence') returning id into v_msg;
  begin
    insert into public.otaku_messages(conversation_id,sender_id,content) values(v_conv,v_a,'Impersonation');
    raise exception 'Forged sender accepted';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  perform set_config('request.jwt.claim.sub',v_c::text,true);
  if exists(select 1 from public.otaku_conversations where id=v_conv) or exists(select 1 from public.otaku_messages where id=v_msg) then raise exception 'Outsider read DM'; end if;
  v_checks:=v_checks+1;
  begin
    insert into public.otaku_messages(conversation_id,sender_id,content) values(v_conv,v_c,'Outsider');
    raise exception 'Outsider sent DM';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,conversation_id,reason) values(v_c,v_b,v_conv,'spam');
    raise exception 'Unrelated conversation report accepted';
  exception when check_violation then v_checks:=v_checks+1; end;
  perform set_config('request.jwt.claim.sub',v_a::text,true);
  update public.otaku_companion_posts set status='closed' where id=v_post returning 1 into v_n;
  if v_n<>1 or not exists(select 1 from public.otaku_companion_posts where id=v_post and closed_at is not null) then raise exception 'Close failed'; end if; v_checks:=v_checks+1;
  begin
    update public.otaku_companion_posts set status='open' where id=v_post;
    raise exception 'Closed post reopened';
  exception when check_violation then v_checks:=v_checks+1; end;
  insert into public.otaku_messages(conversation_id,sender_id,content) values(v_conv,v_a,'Existing DM stays usable after close');
  v_checks:=v_checks+1;
  perform set_config('request.jwt.claim.sub',v_c::text,true);
  if exists(select 1 from public.otaku_companion_posts where id=v_post) then raise exception 'Closed post still public'; end if; v_checks:=v_checks+1;
  begin
    insert into public.otaku_conversations(event_id,companion_post_id,owner_user_id,requester_user_id) values(v_event,v_post,v_a,v_c);
    raise exception 'New DM accepted on closed post';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  perform set_config('request.jwt.claim.sub',v_a::text,true);
  insert into public.otaku_user_blocks(blocker_id,blocked_id) values(v_a,v_b);
  if exists(select 1 from public.otaku_conversations where id=v_conv) or exists(select 1 from public.otaku_messages where conversation_id=v_conv) then raise exception 'Blocker sees blocked DM'; end if; v_checks:=v_checks+1;
  begin
    insert into public.otaku_messages(conversation_id,sender_id,content) values(v_conv,v_a,'Blocked sender');
    raise exception 'Blocker sent message';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  perform set_config('request.jwt.claim.sub',v_b::text,true);
  if exists(select 1 from public.otaku_companion_posts where id=v_post2) or exists(select 1 from public.otaku_conversations where id=v_conv) or exists(select 1 from public.otaku_messages where conversation_id=v_conv) then raise exception 'Blocked peer sees interaction'; end if;
  if exists(select 1 from public.otaku_user_blocks where blocker_id=v_a) then raise exception 'Peer sees private block list'; end if; v_checks:=v_checks+1;
  begin
    insert into public.otaku_messages(conversation_id,sender_id,content) values(v_conv,v_b,'Blocked peer send');
    raise exception 'Blocked peer sent message';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_conversations(event_id,companion_post_id,owner_user_id,requester_user_id) values(v_event,v_post2,v_a,v_b);
    raise exception 'Blocked peer started DM';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  delete from public.otaku_user_blocks where blocker_id=v_a and blocked_id=v_b;
  get diagnostics v_n=row_count;if v_n<>0 then raise exception 'Peer removed block'; end if; v_checks:=v_checks+1;
  begin
    insert into public.otaku_user_blocks(blocker_id,blocked_id) values(v_a,v_c);
    raise exception 'Forged blocker accepted';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_user_blocks(blocker_id,blocked_id) values(v_b,v_b);
    raise exception 'Self block accepted';
  exception when check_violation then v_checks:=v_checks+1; end;
  perform set_config('request.jwt.claim.sub',v_a::text,true);
  -- Reporting remains possible after blocking. Only selected message is saved.
  insert into public.otaku_reports(reporter_id,target_user_id,conversation_id,message_id,reason,details)
    values(v_a,v_b,v_conv,v_msg,'harassment','Report after blocking') returning id into v_report;
  if exists(select 1 from public.otaku_report_evidence where report_id=v_report) then raise exception 'Reporter can read evidence'; end if; v_checks:=v_checks+1;
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,conversation_id,message_id,reason) values(v_a,v_b,v_conv,v_msg,'spam');
    raise exception 'Duplicate pending report accepted';
  exception when check_violation then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,reason,status) values(v_a,v_c,'spam','resolved');
    raise exception 'Forged report status accepted';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,reason) values(v_b,v_c,'spam');
    raise exception 'Forged reporter accepted';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,reason) values(v_a,v_a,'spam');
    raise exception 'Self report accepted';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,reason) values(v_a,v_c,'other');
    raise exception 'Empty other details accepted';
  exception when check_violation then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,companion_post_id,reason) values(v_a,v_b,v_post2,'spam');
    raise exception 'Wrong post owner accepted';
  exception when check_violation then v_checks:=v_checks+1; end;
  update public.otaku_reports set status='resolved' where id=v_report;
  get diagnostics v_n=row_count;if v_n<>0 then raise exception 'Reporter moderated own report'; end if; v_checks:=v_checks+1;
  delete from public.otaku_user_blocks where blocker_id=v_a and blocked_id=v_b;
  if not exists(select 1 from public.otaku_conversations where id=v_conv) then raise exception 'Unblock did not restore DM'; end if; v_checks:=v_checks+1;
  perform set_config('request.jwt.claim.sub',v_b::text,true);
  if exists(select 1 from public.otaku_reports where id=v_report) then raise exception 'Target read report'; end if; v_checks:=v_checks+1;
  insert into public.otaku_reports(reporter_id,target_user_id,companion_post_id,reason) values(v_b,v_a,v_post2,'spam');
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,conversation_id,companion_post_id,reason) values(v_b,v_a,v_conv,v_post2,'fraud');
    raise exception 'Mismatched post/conversation accepted';
  exception when check_violation then v_checks:=v_checks+1; end;
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  if not exists(select 1 from public.otaku_reports where id=v_report) or
    not exists(select 1 from public.otaku_report_evidence where report_id=v_report and snapshot->'message'->>'content'='Selected report evidence') then raise exception 'Admin cannot inspect report evidence'; end if; v_checks:=v_checks+1;
  if exists(select 1 from public.otaku_messages where conversation_id=v_conv) then raise exception 'Admin read unrelated full DM'; end if; v_checks:=v_checks+1;
  update public.otaku_reports set status='reviewing' where id=v_report and revision=1;
  if not exists(select 1 from public.otaku_report_actions where report_id=v_report and actor_id=v_admin and to_status='reviewing') then raise exception 'Action history missing'; end if; v_checks:=v_checks+1;
  update public.otaku_reports set status='resolved' where id=v_report and revision=1;
  get diagnostics v_n=row_count;if v_n<>0 then raise exception 'Stale report update accepted'; end if; v_checks:=v_checks+1;
  begin
    update public.otaku_reports set details='Overwrite report' where id=v_report;
    raise exception 'Admin overwrote report content';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_report_evidence(report_id,snapshot) values(gen_random_uuid(),'{}');
    raise exception 'Client evidence forged';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  -- Twenty accepted reports per reporter/day, regardless of context.
  perform set_config('request.jwt.claim.sub',v_c::text,true);
  for i in 1..20 loop
    insert into public.otaku_reports(reporter_id,target_user_id,reason) values(v_c,v_a,'spam') returning id into v_report;
    perform set_config('request.jwt.claim.sub',v_admin::text,true);
    update public.otaku_reports set status='resolved' where id=v_report;
    perform set_config('request.jwt.claim.sub',v_c::text,true);
  end loop;
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,reason) values(v_c,v_b,'spam');
    raise exception 'Daily report limit accepted';
  exception when check_violation then
    if SQLERRM<>'report_rate_limit' then raise; end if; v_checks:=v_checks+1;
  end;
  execute 'set local role anon';
  perform set_config('request.jwt.claim.sub','',true);
  begin
    select count(*) into v_n from public.otaku_conversations where id=v_conv;
    if v_n<>0 then raise exception 'Anon sees DM'; end if; v_checks:=v_checks+1;
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    select count(*) into v_n from public.otaku_companion_posts where id=v_post2;
    if v_n<>0 then raise exception 'Anon sees posts'; end if; v_checks:=v_checks+1;
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    select count(*) into v_n from public.otaku_reports;
    raise exception 'Anon reports access accepted';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_user_blocks(blocker_id,blocked_id) values(v_a,v_b);
    raise exception 'Anon block accepted';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  execute 'reset role';
  perform set_config('otaku.test_checks',v_checks::text,true);
end $$;
select current_setting('otaku.test_checks')::integer as passed_checks, 'fixtures rolled back' as result;
rollback;
