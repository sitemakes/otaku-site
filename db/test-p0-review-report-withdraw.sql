-- P0 remaining checks: companion review after the event, report privacy for a
-- non-admin target, and scoped withdrawal. Needs one published event. All fixtures roll back.
begin;
do $$
declare
  v_a uuid:=gen_random_uuid(); v_b uuid:=gen_random_uuid(); v_c uuid:=gen_random_uuid();
  v_admin uuid; v_src_event uuid; v_past uuid; v_future uuid; v_post uuid; v_post_f uuid; v_conv uuid; v_conv_f uuid;
  v_review uuid; v_report uuid; v_n integer; v_checks integer:=0;
  v_sc_before bigint; v_sc_after bigint;
begin
  select id into v_src_event from public.otaku_events where publication_status='published' and group_id is not null limit 1;
  select user_id into v_admin from public.otaku_catalog_admins limit 1;
  if v_src_event is null or v_admin is null then raise exception 'Need an admin and a published event'; end if;
  select (select count(*) from public.profiles)+(select count(*) from public.students)
    +(select count(*) from public.conversations)+(select count(*) from public.messages) into v_sc_before;

  insert into auth.users(id,email) values(v_a,v_a||'@p0-test.invalid'),(v_b,v_b||'@p0-test.invalid'),(v_c,v_c||'@p0-test.invalid');
  insert into public.otaku_profiles(id,username,display_name) values
    (v_a,'test_'||substr(replace(v_a::text,'-',''),1,12),'P0 A'),
    (v_b,'test_'||substr(replace(v_b::text,'-',''),1,12),'P0 B'),
    (v_c,'test_'||substr(replace(v_c::text,'-',''),1,12),'P0 C');
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  insert into public.otaku_events(group_id,is_demo,title,venue,prefecture,city,starts_at,publication_status,source_url,source_kind,source_checked_at)
    select group_id,is_demo,'[公開前テスト] past',venue,prefecture,city,now()+interval '10 days','published',source_url,source_kind,now() from public.otaku_events where id=v_src_event returning id into v_past;
  insert into public.otaku_events(group_id,is_demo,title,venue,prefecture,city,starts_at,publication_status,source_url,source_kind,source_checked_at)
    select group_id,is_demo,'[公開前テスト] future',venue,prefecture,city,now()+interval '20 days','published',source_url,source_kind,now() from public.otaku_events where id=v_src_event returning id into v_future;
  -- Recruit, talk and match before the event, as in the real flow; each row is written by its author.
  perform set_config('request.jwt.claim.sub',v_a::text,true);
  insert into public.otaku_companion_posts(event_id,user_id,type,body) values(v_past,v_a,'looking_for_friend','[公開前テスト]') returning id into v_post;
  insert into public.otaku_companion_posts(event_id,user_id,type,body) values(v_future,v_a,'looking_for_friend','[公開前テスト]') returning id into v_post_f;
  perform set_config('request.jwt.claim.sub',v_b::text,true);
  insert into public.otaku_conversations(event_id,companion_post_id,owner_user_id,requester_user_id) values(v_past,v_post,v_a,v_b) returning id into v_conv;
  insert into public.otaku_conversations(event_id,companion_post_id,owner_user_id,requester_user_id) values(v_future,v_post_f,v_a,v_b) returning id into v_conv_f;
  insert into public.otaku_messages(conversation_id,sender_id,content) values(v_conv,v_b,'[公開前テスト] DM');
  perform set_config('request.jwt.claim.sub',v_a::text,true);
  insert into public.otaku_companion_matches(post_id,conversation_id,owner_user_id,matched_user_id) values(v_post,v_conv,v_a,v_b),(v_post_f,v_conv_f,v_a,v_b);
  -- The first event then takes place.
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  update public.otaku_events set starts_at=now()-interval '2 days' where id=v_past;

  execute 'set local role authenticated';

  -- 1. Reviews
  perform set_config('request.jwt.claim.sub',v_b::text,true);
  begin
    insert into public.otaku_reviews(conversation_id,reviewer_id,reviewee_id,rating) values(v_conv_f,v_b,v_a,5);
    raise exception 'FAIL review before the event accepted';
  exception when insufficient_privilege or check_violation then v_checks:=v_checks+1; end;
  begin
    insert into public.otaku_reviews(conversation_id,reviewer_id,reviewee_id,rating) values(v_conv,v_a,v_b,1);
    raise exception 'FAIL forged reviewer accepted';
  exception when insufficient_privilege or check_violation then v_checks:=v_checks+1; end;
  insert into public.otaku_reviews(conversation_id,reviewer_id,reviewee_id,rating,punctuality,communication,courtesy,comment)
    values(v_conv,v_b,v_a,5,5,5,5,'[公開前テスト] review') returning id into v_review;
  v_checks:=v_checks+1;
  begin
    insert into public.otaku_reviews(conversation_id,reviewer_id,reviewee_id,rating) values(v_conv,v_b,v_a,4);
    raise exception 'FAIL duplicate review accepted';
  exception when unique_violation then v_checks:=v_checks+1; end;
  update public.otaku_reviews set visibility='hidden' where id=v_review;
  get diagnostics v_n=row_count;
  if v_n<>0 then raise exception 'FAIL reviewer moderated own review'; end if; v_checks:=v_checks+1;
  perform set_config('request.jwt.claim.sub',v_c::text,true);
  begin
    insert into public.otaku_reviews(conversation_id,reviewer_id,reviewee_id,rating) values(v_conv,v_c,v_a,1);
    raise exception 'FAIL outsider review accepted';
  exception when insufficient_privilege or check_violation then v_checks:=v_checks+1; end;
  if not exists(select 1 from public.otaku_reviews where id=v_review) then raise exception 'FAIL visible review not readable'; end if; v_checks:=v_checks+1;
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  update public.otaku_reviews set visibility='hidden',moderation_reason='[公開前テスト]' where id=v_review;
  get diagnostics v_n=row_count;
  if v_n<>1 then raise exception 'FAIL admin could not hide review'; end if; v_checks:=v_checks+1;
  perform set_config('request.jwt.claim.sub',v_c::text,true);
  if exists(select 1 from public.otaku_reviews where id=v_review) then raise exception 'FAIL hidden review readable by third party'; end if; v_checks:=v_checks+1;
  perform set_config('request.jwt.claim.sub',v_a::text,true);
  if not exists(select 1 from public.otaku_reviews where id=v_review) then raise exception 'FAIL reviewee cannot see own hidden review'; end if; v_checks:=v_checks+1;

  -- 2. Report about a non-admin target
  if exists(select 1 from public.otaku_catalog_admins where user_id in (v_a,v_b,v_c)) then raise exception 'fixture is admin'; end if;
  perform set_config('request.jwt.claim.sub',v_b::text,true);
  begin
    insert into public.otaku_reports(reporter_id,target_user_id,conversation_id,reason,details) values(v_a,v_b,v_conv,'spam','forged');
    raise exception 'FAIL forged reporter accepted';
  exception when insufficient_privilege or check_violation then v_checks:=v_checks+1; end;
  insert into public.otaku_reports(reporter_id,target_user_id,conversation_id,reason,details)
    values(v_b,v_a,v_conv,'harassment','[公開前テスト] details') returning id into v_report;
  if not exists(select 1 from public.otaku_reports where id=v_report) then raise exception 'FAIL reporter cannot read own report'; end if; v_checks:=v_checks+1;
  perform set_config('request.jwt.claim.sub',v_a::text,true);
  if exists(select 1 from public.otaku_reports where id=v_report)
     or exists(select 1 from public.otaku_report_evidence where report_id=v_report)
     or exists(select 1 from public.otaku_report_actions where report_id=v_report) then raise exception 'FAIL target sees report'; end if; v_checks:=v_checks+1;
  update public.otaku_reports set status='dismissed' where id=v_report;
  get diagnostics v_n=row_count;
  if v_n<>0 then raise exception 'FAIL target changed report status'; end if; v_checks:=v_checks+1;
  if exists(select 1 from public.otaku_notifications where user_id=v_a and (body ilike '%通報%' or title ilike '%通報%')) then raise exception 'FAIL target notified of report'; end if; v_checks:=v_checks+1;
  perform set_config('request.jwt.claim.sub',v_c::text,true);
  if exists(select 1 from public.otaku_reports where id=v_report) then raise exception 'FAIL outsider sees report'; end if; v_checks:=v_checks+1;

  -- 3. Withdrawal of B (the reviewer, reporter and DM sender)
  perform set_config('request.jwt.claim.sub',v_b::text,true);
  begin
    perform public.otaku_withdraw('wrong');
    raise exception 'FAIL withdrawal without confirmation';
  exception when insufficient_privilege then v_checks:=v_checks+1; end;
  perform public.otaku_withdraw('OTAKU LIVEを退会する');
  execute 'reset role';
  if exists(select 1 from public.otaku_profiles where id=v_b)
     or exists(select 1 from public.otaku_conversations where requester_user_id=v_b or owner_user_id=v_b)
     or exists(select 1 from public.otaku_messages where sender_id=v_b)
     or exists(select 1 from public.otaku_reviews where reviewer_id=v_b or reviewee_id=v_b)
     or exists(select 1 from public.otaku_companion_matches where matched_user_id=v_b) then raise exception 'FAIL withdrawal left OTAKU data'; end if; v_checks:=v_checks+1;
  if not exists(select 1 from auth.users where id=v_b) then raise exception 'FAIL shared auth user deleted'; end if; v_checks:=v_checks+1;
  if not exists(select 1 from public.otaku_profiles where id=v_a) or not exists(select 1 from public.otaku_companion_posts where id=v_post) then raise exception 'FAIL other user data deleted'; end if; v_checks:=v_checks+1;
  select (select count(*) from public.profiles)+(select count(*) from public.students)
    +(select count(*) from public.conversations)+(select count(*) from public.messages) into v_sc_after;
  if v_sc_after<>v_sc_before then raise exception 'FAIL student-chat rows changed'; end if; v_checks:=v_checks+1;
  -- Since otaku_report_retention the report and its evidence stay with the reporter id cleared.
  if not exists(select 1 from public.otaku_reports where id=v_report and reporter_id is null and target_user_id=v_a)
     or not exists(select 1 from public.otaku_report_evidence where report_id=v_report) then raise exception 'FAIL report not kept after withdrawal'; end if; v_checks:=v_checks+1;
  raise notice 'PASS % checks', v_checks;
end $$;
rollback;
