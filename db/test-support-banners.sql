-- Run after support-banners.sql. Needs one catalog admin, one published group, three published future events
-- and one finished published event.
-- All fixtures roll back.
begin;
do $$
declare
  v_a uuid := gen_random_uuid(); v_b uuid := gen_random_uuid(); v_c uuid := gen_random_uuid();
  v_admin uuid; v_group uuid; v_events uuid[]; v_banner uuid; v_banner_b uuid; v_past uuid; v_n integer; v_checks integer := 0;
  v_today date := (now() at time zone 'Asia/Tokyo')::date; v_name text;
begin
  select user_id into v_admin from public.otaku_catalog_admins limit 1;
  select id into v_group from public.otaku_idol_groups where publication_status = 'published' and not is_demo order by id limit 1;
  select array_agg(id) into v_events from (select id from public.otaku_events
    where publication_status = 'published' and not is_demo and starts_at > now() order by starts_at limit 3) e;
  select id into v_past from public.otaku_events
    where publication_status = 'published' and not is_demo and starts_at < now() - interval '1 day' order by starts_at desc limit 1;
  if v_admin is null or v_group is null or coalesce(array_length(v_events, 1), 0) < 3 or v_past is null then
    raise exception 'Need an admin, a published group, three published future events and one finished event';
  end if;
  insert into auth.users(id, email) values (v_a, v_a || '@banner-test.invalid'), (v_b, v_b || '@banner-test.invalid'), (v_c, v_c || '@banner-test.invalid');
  insert into public.otaku_profiles(id, username, display_name) values
    (v_a, 'test_' || substr(replace(v_a::text, '-', ''), 1, 12), 'Banner A'),
    (v_b, 'test_' || substr(replace(v_b::text, '-', ''), 1, 12), 'Banner B'),
    (v_c, 'test_' || substr(replace(v_c::text, '-', ''), 1, 12), 'Banner C');

  execute 'set local role authenticated';
  -- A: not eligible yet
  perform set_config('request.jwt.claim.sub', v_a::text, true);
  begin
    perform public.otaku_submit_support_banner(v_group, null, 'birthday', v_today, 'おめでとう', 'anonymous');
    raise exception 'Ineligible submit accepted';
  exception when others then if sqlerrm <> 'banner_not_eligible' then raise; end if; v_checks := v_checks + 1; end;

  -- A: three attendances make A eligible
  insert into public.otaku_event_attendees(event_id, user_id) select unnest(v_events), v_a;
  if not (public.otaku_support_banner_eligibility() ->> 'eligible')::boolean then raise exception 'Eligibility not granted'; end if;
  v_checks := v_checks + 1;
  begin
    perform public.otaku_submit_support_banner(v_group, null, 'birthday', v_today, '詳細は https://example.com へ', 'anonymous');
    raise exception 'URL accepted';
  exception when others then if sqlerrm <> 'banner_invalid_message' then raise; end if; v_checks := v_checks + 1; end;
  begin
    perform public.otaku_submit_support_banner(v_group, null, 'birthday', v_today, repeat('あ', 41), 'anonymous');
    raise exception '41 chars accepted';
  exception when others then if sqlerrm <> 'banner_invalid_message' then raise; end if; v_checks := v_checks + 1; end;
  begin
    perform public.otaku_submit_support_banner(v_group, null, 'birthday', v_today + 61, 'おめでとう', 'anonymous');
    raise exception 'Far date accepted';
  exception when others then if sqlerrm <> 'banner_invalid_date' then raise; end if; v_checks := v_checks + 1; end;
  v_banner := public.otaku_submit_support_banner(v_group, null, 'birthday', v_today, 'お誕生日おめでとう！', 'anonymous');
  begin
    perform public.otaku_submit_support_banner(v_group, null, 'event', v_today + 1, 'がんばって', 'anonymous');
    raise exception 'Second active banner accepted';
  exception when others then if sqlerrm <> 'banner_not_eligible' then raise; end if; v_checks := v_checks + 1; end;
  select count(*) into v_n from public.otaku_support_banners where id = v_banner;
  if v_n <> 1 then raise exception 'Owner cannot read own banner'; end if; v_checks := v_checks + 1;
  select count(*) into v_n from public.otaku_todays_support_banners(v_group) where id = v_banner;
  if v_n <> 0 then raise exception 'Pending banner is visible'; end if; v_checks := v_checks + 1;

  -- B: cannot read A's row, cannot review, cannot write directly
  perform set_config('request.jwt.claim.sub', v_b::text, true);
  select count(*) into v_n from public.otaku_support_banners where id = v_banner;
  if v_n <> 0 then raise exception 'Other user read banner row'; end if; v_checks := v_checks + 1;
  begin
    perform public.otaku_review_support_banner(v_banner, 'approved');
    raise exception 'Non-admin review accepted';
  exception when others then if sqlerrm <> 'not_allowed' then raise; end if; v_checks := v_checks + 1; end;
  begin
    update public.otaku_support_banners set status = 'approved' where id = v_banner;
    raise exception 'Direct update accepted';
  exception when insufficient_privilege then v_checks := v_checks + 1; end;

  -- anon cannot read the table
  execute 'set local role anon';
  begin
    perform 1 from public.otaku_support_banners limit 1;
    raise exception 'Anon read banners table';
  exception when insufficient_privilege then v_checks := v_checks + 1; end;
  select count(*) into v_n from public.otaku_todays_support_banners(v_group);
  v_checks := v_checks + 1;

  -- admin approves
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.otaku_review_support_banner(v_banner, 'approved');
  select display_name into v_name from public.otaku_todays_support_banners(v_group) where id = v_banner;
  if v_name is distinct from '匿名のファン' then raise exception 'Approved banner missing or name leaked: %', v_name; end if;
  v_checks := v_checks + 1;

  -- owner cannot report own banner; B reports and the banner is hidden
  perform set_config('request.jwt.claim.sub', v_a::text, true);
  begin
    perform public.otaku_report_support_banner(v_banner, '自分の');
    raise exception 'Self report accepted';
  exception when others then if sqlerrm <> 'report_invalid_context' then raise; end if; v_checks := v_checks + 1; end;
  perform set_config('request.jwt.claim.sub', v_b::text, true);
  select count(*) into v_n from public.otaku_support_banner_reports;
  if v_n <> 0 then raise exception 'Non-admin read reports'; end if; v_checks := v_checks + 1;
  perform public.otaku_report_support_banner(v_banner, '不適切です');
  select count(*) into v_n from public.otaku_todays_support_banners(v_group) where id = v_banner;
  if v_n <> 0 then raise exception 'Reported banner still visible'; end if; v_checks := v_checks + 1;

  -- C: an event record makes C eligible; profile display name is shown when allowed
  perform set_config('request.jwt.claim.sub', v_c::text, true);
  insert into public.otaku_event_records(event_id, user_id, impression, visibility) values (v_past, v_c, 'よかった', 'private');
  v_banner_b := public.otaku_submit_support_banner(v_group, null, 'event', v_today, '今日もがんばって', 'profile');
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.otaku_review_support_banner(v_banner_b, 'approved');
  select display_name into v_name from public.otaku_todays_support_banners(v_group) where id = v_banner_b;
  if v_name is distinct from 'Banner C' then raise exception 'Profile display name not shown: %', v_name; end if;
  v_checks := v_checks + 1;

  raise notice 'support banner checks passed: %', v_checks;
end $$;
rollback;
