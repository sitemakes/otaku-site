begin;

do $$
declare
  report_key text := 'growth-report-test-key';
  stats jsonb;
  page_views integer;
begin
  perform public.otaku_count_page_view('event.html');
  perform public.otaku_count_page_view('/event.html?id=test');
  perform public.otaku_count_page_view('/not-allowed.html');

  select views into page_views from public.otaku_page_view_counts
    where day=(now() at time zone 'Asia/Tokyo')::date and path='event.html';
  if page_views<>2 then raise exception 'FAIL page view count'; end if;
  if exists (select 1 from public.otaku_page_view_counts where path='not-allowed.html') then
    raise exception 'FAIL disallowed page counted';
  end if;

  begin
    execute 'set local role anon';
    perform (select count(*) from public.otaku_page_view_counts);
    raise exception 'FAIL anon can select page views';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';

  begin
    perform public.otaku_growth_stats('wrong-key', 7);
    raise exception 'FAIL invalid report key accepted';
  exception when sqlstate '42501' then null;
  end;

  insert into otaku_private.report_keys(key_hash)
    values (encode(extensions.digest(report_key, 'sha256'), 'hex'));
  stats := public.otaku_growth_stats(report_key, 7);
  if stats->'current' is null or stats->'page_views' is null then
    raise exception 'FAIL growth stats shape';
  end if;
end $$;

rollback;
