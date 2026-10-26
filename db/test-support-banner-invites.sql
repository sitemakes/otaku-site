-- Run after support-banners.sql and support-banner-invites.sql. Needs one published future event
-- and one published group. All fixtures roll back.
begin;
do $$
declare
  v_a uuid := gen_random_uuid(); v_b uuid := gen_random_uuid(); v_c uuid := gen_random_uuid();
  v_event uuid; v_group uuid; v_code text; v_code_again text; v_missing text;
  v_result text; v_eligibility jsonb; v_banner uuid; v_checks integer := 0;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  select id into v_event from public.otaku_events
    where publication_status = 'published' and not is_demo and starts_at > now()
    order by starts_at limit 1;
  select id into v_group from public.otaku_idol_groups
    where publication_status = 'published' and not is_demo order by id limit 1;
  if v_event is null or v_group is null then
    raise exception 'Need a published future event and a published group';
  end if;
  select lpad(n::text, 10, '0') into v_missing from generate_series(0, 100) n
    where not exists (select 1 from otaku_private.invites i where i.code = lpad(n::text, 10, '0'))
    order by n limit 1;
  if v_missing is null then raise exception 'Need an unused invite code for the test'; end if;

  insert into auth.users(id, email) values
    (v_a, v_a || '@banner-invite-test.invalid'),
    (v_b, v_b || '@banner-invite-test.invalid'),
    (v_c, v_c || '@banner-invite-test.invalid');
  insert into public.otaku_profiles(id, username, display_name) values
    (v_a, 'test_' || substr(replace(v_a::text, '-', ''), 1, 12), 'Invite A'),
    (v_b, 'test_' || substr(replace(v_b::text, '-', ''), 1, 12), 'Invite B'),
    (v_c, 'test_' || substr(replace(v_c::text, '-', ''), 1, 12), 'Invite C');
  update public.otaku_profiles set created_at = now() - interval '8 days' where id = v_c;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_a::text, true);
  v_code := public.otaku_my_invite_code();
  v_code_again := public.otaku_my_invite_code();
  if v_code is distinct from v_code_again or v_code !~ '^[a-z0-9]{10}$' then
    raise exception 'Invite code was not stable or valid: %, %', v_code, v_code_again;
  end if;
  v_checks := v_checks + 1;
  if public.otaku_claim_invite(v_code) <> 'invalid' then raise exception 'Self claim accepted'; end if;
  v_checks := v_checks + 1;
  if public.otaku_claim_invite(v_missing) <> 'invalid' then raise exception 'Missing code accepted'; end if;
  v_checks := v_checks + 1;

  perform set_config('request.jwt.claim.sub', v_b::text, true);
  if public.otaku_claim_invite(v_code) <> 'ok' then raise exception 'New invitee claim failed'; end if;
  v_checks := v_checks + 1;
  if public.otaku_claim_invite(v_code) <> 'already' then raise exception 'Repeated claim was not already'; end if;
  v_checks := v_checks + 1;

  perform set_config('request.jwt.claim.sub', v_c::text, true);
  if public.otaku_claim_invite(v_code) <> 'too_late' then raise exception 'Old profile claim was not too_late'; end if;
  v_checks := v_checks + 1;

  perform set_config('request.jwt.claim.sub', v_a::text, true);
  v_eligibility := public.otaku_support_banner_eligibility();
  if (v_eligibility ->> 'invite_count')::integer <> 0
     or (v_eligibility ->> 'eligible')::boolean then
    raise exception 'Inactive invitee affected eligibility: %', v_eligibility;
  end if;
  v_checks := v_checks + 1;

  perform set_config('request.jwt.claim.sub', v_b::text, true);
  insert into public.otaku_event_attendees(event_id, user_id) values (v_event, v_b);
  perform set_config('request.jwt.claim.sub', v_a::text, true);
  v_eligibility := public.otaku_support_banner_eligibility();
  if (v_eligibility ->> 'invite_count')::integer <> 1
     or not (v_eligibility ->> 'eligible')::boolean then
    raise exception 'Active invitee did not grant eligibility: %', v_eligibility;
  end if;
  v_checks := v_checks + 1;
  v_banner := public.otaku_submit_support_banner(
    v_group, null, 'event', v_today, '招待からの応援です', 'anonymous');
  if v_banner is null then raise exception 'Eligible invite submit failed'; end if;
  v_checks := v_checks + 1;

  begin
    perform 1 from otaku_private.invites limit 1;
    raise exception 'Authenticated read invites table';
  exception when insufficient_privilege then v_checks := v_checks + 1; end;
  begin
    perform 1 from otaku_private.invite_signups limit 1;
    raise exception 'Authenticated read invite_signups table';
  exception when insufficient_privilege then v_checks := v_checks + 1; end;

  raise notice 'support banner invite checks passed: %', v_checks;
end $$;
rollback;
