-- 2026-10-10 に本番 DB で dry-run し、5項目通過（DM 11件目・別利用者・同行募集6件目・トリガー8個）
-- MCP で実行するときは、最後の notice を raise exception に変えると結果が返る。
-- All fixtures are rolled back.
begin;
do $$
declare
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); admin_id uuid; event_id uuid; post_id uuid; conv_id uuid; checks int:=0; i int;
begin
  select user_id into admin_id from public.otaku_catalog_admins limit 1;
  select id into event_id from public.otaku_events where publication_status='published' and starts_at>now() limit 1;
  if admin_id is null or event_id is null then raise exception 'Need an admin and a future published event'; end if;
  insert into auth.users(id,email) values(a,a||'@rate-test.invalid'),(b,b||'@rate-test.invalid'),(c,c||'@rate-test.invalid');
  insert into public.otaku_profiles(id,username,display_name) values
    (a,'rate_'||substr(replace(a::text,'-',''),1,12),'Rate A'),(b,'rate_'||substr(replace(b::text,'-',''),1,12),'Rate B'),(c,'rate_'||substr(replace(c::text,'-',''),1,12),'Rate C');
  perform set_config('request.jwt.claim.sub',a::text,true);
  insert into public.otaku_companion_posts(event_id,user_id,type,body) values(event_id,a,'looking_for_friend','rate test') returning id into post_id;
  perform set_config('request.jwt.claim.sub',b::text,true);
  execute 'set local role authenticated';
  insert into public.otaku_conversations(event_id,companion_post_id,owner_user_id,requester_user_id) values(event_id,post_id,a,b) returning id into conv_id;
  for i in 1..10 loop insert into public.otaku_messages(conversation_id,sender_id,content) values(conv_id,b,'rate test'); end loop;
  checks:=checks+1;
  begin insert into public.otaku_messages(conversation_id,sender_id,content) values(conv_id,b,'rate test'); raise exception 'FAIL B message 11 accepted'; exception when sqlstate '23514' then if sqlerrm<>'rate_limited' then raise; end if; checks:=checks+1; end;
  perform set_config('request.jwt.claim.sub',a::text,true);
  insert into public.otaku_messages(conversation_id,sender_id,content) values(conv_id,a,'rate test'); checks:=checks+1;
  for i in 1..4 loop insert into public.otaku_companion_posts(event_id,user_id,type,body) values(event_id,a,'looking_for_friend','rate test '||i); end loop;
  begin insert into public.otaku_companion_posts(event_id,user_id,type,body) values(event_id,a,'looking_for_friend','rate test 6'); raise exception 'FAIL A companion post 6 accepted'; exception when sqlstate '23514' then if sqlerrm<>'rate_limited' then raise; end if; checks:=checks+1; end;
  -- 未ログインの書き込みは既存の message_guard が safety_not_allowed で先に拒否するため確認しない。
  execute 'reset role';
  if (select count(*) from pg_trigger where tgname='otaku_rate_limit' and tgrelid in ('public.otaku_messages'::regclass,'public.otaku_conversations'::regclass,'public.otaku_companion_posts'::regclass,'public.otaku_board_posts'::regclass,'public.otaku_board_replies'::regclass,'public.otaku_goods_posts'::regclass,'public.otaku_event_records'::regclass,'public.otaku_user_follows'::regclass))<>8 then raise exception 'FAIL all rate limit triggers not installed'; end if;
  checks:=checks+1;
  raise notice 'PASS % checks',checks;
end $$;
rollback;
