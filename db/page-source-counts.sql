-- Migration: otaku_page_source_counts

create table public.otaku_page_source_counts (
  day date not null,
  source text not null,
  campaign text not null default '',
  views integer not null default 0,
  primary key (day, source, campaign)
);
alter table public.otaku_page_source_counts enable row level security;
revoke all on public.otaku_page_source_counts from anon, authenticated;

create or replace function public.otaku_count_page_source(target_source text, target_campaign text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_source text := lower(trim(coalesce(target_source, '')));
  normalized_campaign text;
  today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if normalized_source <> all (array['threads', 'instagram', 'x']) then return; end if;
  normalized_campaign := case when target_campaign ~ '^[A-H]$' then target_campaign else '' end;

  insert into public.otaku_page_source_counts(day, source, campaign, views)
  values (today, normalized_source, normalized_campaign, 1)
  on conflict (day, source, campaign) do update
    set views = public.otaku_page_source_counts.views + 1
    where public.otaku_page_source_counts.views < 10000;
end;
$$;
revoke all on function public.otaku_count_page_source(text, text) from public;
grant execute on function public.otaku_count_page_source(text, text) to anon, authenticated;

create or replace function public.otaku_growth_stats(report_key text, days integer default 7)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  computed_hash text := encode(extensions.digest(report_key, 'sha256'), 'hex');
  period_days integer := greatest(1, least(coalesce(days, 7), 90));
  today date := (now() at time zone 'Asia/Tokyo')::date;
  current_from date := today - period_days + 1;
  previous_from date := today - (period_days * 2) + 1;
  current_to date := today;
  previous_to date := current_from - 1;
  result jsonb;
begin
  if not exists (select 1 from otaku_private.report_keys rk where rk.key_hash = computed_hash) then
    raise exception 'report_key_invalid' using errcode = '42501';
  end if;

  result := jsonb_build_object(
    'period', jsonb_build_object('from', current_from, 'to', current_to),
    'current', jsonb_build_object(
      'new_profiles', (select count(*) from public.otaku_profiles where (created_at at time zone 'Asia/Tokyo')::date between current_from and current_to),
      'event_attendees', (select count(*) from public.otaku_event_attendees where (created_at at time zone 'Asia/Tokyo')::date between current_from and current_to),
      'companion_posts', (select count(*) from public.otaku_companion_posts where (created_at at time zone 'Asia/Tokyo')::date between current_from and current_to),
      'conversations', (select count(*) from public.otaku_conversations where (created_at at time zone 'Asia/Tokyo')::date between current_from and current_to),
      'messages', (select count(*) from public.otaku_messages where (created_at at time zone 'Asia/Tokyo')::date between current_from and current_to),
      'board_posts', (select count(*) from public.otaku_board_posts where (created_at at time zone 'Asia/Tokyo')::date between current_from and current_to),
      'board_replies', (select count(*) from public.otaku_board_replies where (created_at at time zone 'Asia/Tokyo')::date between current_from and current_to),
      'goods_posts', (select count(*) from public.otaku_goods_posts where (created_at at time zone 'Asia/Tokyo')::date between current_from and current_to),
      'event_records', (select count(*) from public.otaku_event_records where (created_at at time zone 'Asia/Tokyo')::date between current_from and current_to),
      'page_views', (select coalesce(sum(views), 0) from public.otaku_page_view_counts where day between current_from and current_to),
      'source_views', (select coalesce(sum(views), 0) from public.otaku_page_source_counts where day between current_from and current_to)
    ),
    'previous', jsonb_build_object(
      'new_profiles', (select count(*) from public.otaku_profiles where (created_at at time zone 'Asia/Tokyo')::date between previous_from and previous_to),
      'event_attendees', (select count(*) from public.otaku_event_attendees where (created_at at time zone 'Asia/Tokyo')::date between previous_from and previous_to),
      'companion_posts', (select count(*) from public.otaku_companion_posts where (created_at at time zone 'Asia/Tokyo')::date between previous_from and previous_to),
      'conversations', (select count(*) from public.otaku_conversations where (created_at at time zone 'Asia/Tokyo')::date between previous_from and previous_to),
      'messages', (select count(*) from public.otaku_messages where (created_at at time zone 'Asia/Tokyo')::date between previous_from and previous_to),
      'board_posts', (select count(*) from public.otaku_board_posts where (created_at at time zone 'Asia/Tokyo')::date between previous_from and previous_to),
      'board_replies', (select count(*) from public.otaku_board_replies where (created_at at time zone 'Asia/Tokyo')::date between previous_from and previous_to),
      'goods_posts', (select count(*) from public.otaku_goods_posts where (created_at at time zone 'Asia/Tokyo')::date between previous_from and previous_to),
      'event_records', (select count(*) from public.otaku_event_records where (created_at at time zone 'Asia/Tokyo')::date between previous_from and previous_to),
      'page_views', (select coalesce(sum(views), 0) from public.otaku_page_view_counts where day between previous_from and previous_to),
      'source_views', (select coalesce(sum(views), 0) from public.otaku_page_source_counts where day between previous_from and previous_to)
    ),
    'page_views', coalesce((select jsonb_agg(jsonb_build_object('path', path, 'views', views) order by views desc, path)
      from (select path, sum(views)::integer as views from public.otaku_page_view_counts where day between current_from and current_to group by path) v), '[]'::jsonb),
    'sources', coalesce((select jsonb_agg(jsonb_build_object('source', source, 'campaign', campaign, 'views', views) order by views desc, source, campaign)
      from (select source, campaign, sum(views)::integer as views from public.otaku_page_source_counts where day between current_from and current_to group by source, campaign) s), '[]'::jsonb)
  );
  return result;
end;
$$;
revoke all on function public.otaku_growth_stats(text, integer) from public;
grant execute on function public.otaku_growth_stats(text, integer) to anon;

-- Rollback:
-- Restore otaku_growth_stats to the definition in db/growth-report.sql.
-- drop function if exists public.otaku_count_page_source(text, text);
-- drop table if exists public.otaku_page_source_counts;
