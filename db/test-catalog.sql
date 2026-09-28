-- Execute against the configured project using SQL Editor / execute_sql.
-- Entire test is rolled back; no auth accounts or production fixtures are created.
begin;
select set_config('test.admin_id',(select user_id::text from public.otaku_catalog_admins limit 1),true);
select set_config('test.group_id',gen_random_uuid()::text,true);
select set_config('test.member_id',gen_random_uuid()::text,true);
select set_config('test.event_id',gen_random_uuid()::text,true);
select set_config('request.jwt.claim.sub',current_setting('test.admin_id'),true);
set local role authenticated;
do $$ begin
  if not public.otaku_is_catalog_admin() then raise exception 'FAIL admin recognition'; end if;
end $$;
insert into public.otaku_idol_groups(id,name,slug)
  values(current_setting('test.group_id')::uuid,'TEST '||current_setting('test.group_id'),current_setting('test.group_id'));
insert into public.otaku_idols(id,group_id,name) values(current_setting('test.member_id')::uuid,current_setting('test.group_id')::uuid,'TEST member');
insert into public.otaku_events(id,group_id,title,venue,starts_at) values(current_setting('test.event_id')::uuid,current_setting('test.group_id')::uuid,'TEST event','TEST venue',now()+interval '1 day');
do $$ begin
  begin
    update public.otaku_idol_groups set publication_status='published' where id=current_setting('test.group_id')::uuid;
    raise exception 'FAIL publication without source accepted';
  exception when check_violation then null; end;
  begin
    update public.otaku_idol_groups set source_url='javascript:alert(1)' where id=current_setting('test.group_id')::uuid;
    raise exception 'FAIL unsafe URL accepted';
  exception when check_violation then null; end;
  begin
    update public.otaku_events set ends_at=starts_at-interval '1 hour' where id=current_setting('test.event_id')::uuid;
    raise exception 'FAIL reversed dates accepted';
  exception when check_violation then null; end;
  begin
    update public.otaku_events set publication_status='published',source_url='https://example.com/',source_kind='official',source_checked_at=now() where id=current_setting('test.event_id')::uuid;
    raise exception 'FAIL unpublished parent accepted';
  exception when check_violation then null; end;
  begin
    update public.otaku_idols set group_id=(select id from public.otaku_idol_groups where is_demo limit 1) where id=current_setting('test.member_id')::uuid;
    raise exception 'FAIL demo mixed with real';
  exception when check_violation then null; end;
  begin
    insert into public.otaku_idols(group_id,name) values(current_setting('test.group_id')::uuid,' TEST member ');
    raise exception 'FAIL duplicate accepted';
  exception when unique_violation then null; end;
  begin
    delete from public.otaku_idol_groups where id=current_setting('test.group_id')::uuid;
    raise exception 'FAIL admin hard delete accepted';
  exception when insufficient_privilege then null; end;
end $$;

-- Anonymous users cannot see drafts or memberships and cannot write.
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
  if exists(select 1 from public.otaku_idol_groups where id=current_setting('test.group_id')::uuid)
     or exists(select 1 from public.otaku_idols where id=current_setting('test.member_id')::uuid)
     or exists(select 1 from public.otaku_events where id=current_setting('test.event_id')::uuid)
     or exists(select 1 from public.otaku_catalog_admins) then raise exception 'FAIL private rows visible'; end if;
  begin
    insert into public.otaku_idol_groups(name,slug) values('forbidden','forbidden');
    raise exception 'FAIL anonymous insert accepted';
  exception when insufficient_privilege then null; end;
end $$;

-- Ordinary authenticated callers cannot self-promote, modify catalog or read audit.
reset role;
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
set local role authenticated;
do $$ declare t text; n integer; begin
  if public.otaku_is_catalog_admin() then raise exception 'FAIL ordinary user is admin'; end if;
  if exists(select 1 from public.otaku_catalog_audit) then raise exception 'FAIL audit leak'; end if;
  begin
    insert into public.otaku_catalog_admins(user_id) values(auth.uid());
    raise exception 'FAIL self-promotion';
  exception when insufficient_privilege then null; end;
  foreach t in array array['otaku_idol_groups','otaku_idols','otaku_events'] loop
    execute format('update public.%I set source_url=''https://example.com/''',t);
    get diagnostics n=row_count;
    if n<>0 then raise exception 'FAIL unauthorized update'; end if;
  end loop;
  begin
    insert into public.otaku_idol_groups(name,slug) values('forbidden','forbidden');
    raise exception 'FAIL nonadmin insert accepted';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.otaku_idols(group_id,name) values(current_setting('test.group_id')::uuid,'forbidden');
    raise exception 'FAIL nonadmin member insert accepted';
  exception when insufficient_privilege or check_violation then null; end;
  begin
    insert into public.otaku_events(group_id,title,venue,starts_at) values(current_setting('test.group_id')::uuid,'forbidden','venue',now());
    raise exception 'FAIL nonadmin event insert accepted';
  exception when insufficient_privilege or check_violation then null; end;
end $$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('test.admin_id'),true);
set local role authenticated;
update public.otaku_idol_groups set publication_status='published',source_url='https://example.com/',source_kind='official',source_checked_at=now() where id=current_setting('test.group_id')::uuid;
update public.otaku_idols set publication_status='published',source_url='https://example.com/member',source_kind='official',source_checked_at=now() where id=current_setting('test.member_id')::uuid;
update public.otaku_events set publication_status='published',source_url='https://example.com/live',source_kind='organizer',source_checked_at=now() where id=current_setting('test.event_id')::uuid;
do $$ declare n integer; begin
  begin
    update public.otaku_idol_groups set publication_status='archived' where id=current_setting('test.group_id')::uuid;
    raise exception 'FAIL parent hidden with published children';
  exception when check_violation then null; end;
  update public.otaku_idol_groups set name='stale edit' where id=current_setting('test.group_id')::uuid and revision=1;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'FAIL stale update accepted'; end if;
  if (select count(*) from public.otaku_catalog_audit where record_id in (current_setting('test.group_id')::uuid,current_setting('test.member_id')::uuid,current_setting('test.event_id')::uuid)) <> 6 then raise exception 'FAIL audit count'; end if;
  begin
    update public.otaku_catalog_audit set actor_id=auth.uid();
    raise exception 'FAIL audit tampering';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
  if not exists(select 1 from public.otaku_events where id=current_setting('test.event_id')::uuid) then raise exception 'FAIL published event hidden'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('test.admin_id'),true);
set local role authenticated;
update public.otaku_events set publication_status='archived' where id=current_setting('test.event_id')::uuid;
update public.otaku_idols set publication_status='archived' where id=current_setting('test.member_id')::uuid;
update public.otaku_idol_groups set publication_status='archived' where id=current_setting('test.group_id')::uuid;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
  if exists(select 1 from public.otaku_events where id=current_setting('test.event_id')::uuid) then raise exception 'FAIL archived event visible'; end if;
end $$;
rollback;
select 'PASS: catalog roles, drafts, publishing, validation, duplicates, audit, concurrency, archive; all fixtures rolled back' as result;
