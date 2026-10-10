-- Purpose: prevent excessive posting and DM activity.
-- Applied: 2026-10-10. Additive migration only: otaku_rate_limits.
create or replace function otaku_private.enforce_rate_limit()
returns trigger language plpgsql security definer set search_path to ''
as $$
declare n bigint;
begin
  if auth.uid() is null then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('otaku-rate:'||TG_TABLE_NAME||':'||auth.uid()::text, 0));
  execute format('select count(*) from public.%I where %I = $1 and created_at > now() - $2::interval', TG_TABLE_NAME, TG_ARGV[0]) into n using auth.uid(), TG_ARGV[2];
  if n >= TG_ARGV[1]::int then raise exception 'rate_limited' using errcode = '23514'; end if;
  execute format('select count(*) from public.%I where %I = $1 and created_at > now() - $2::interval', TG_TABLE_NAME, TG_ARGV[0]) into n using auth.uid(), '1 day';
  if n >= TG_ARGV[3]::int then raise exception 'rate_limited' using errcode = '23514'; end if;
  return new;
end $$;
revoke all on function otaku_private.enforce_rate_limit() from public, anon, authenticated;

drop trigger if exists otaku_rate_limit on public.otaku_messages;
create trigger otaku_rate_limit before insert on public.otaku_messages for each row execute function otaku_private.enforce_rate_limit('sender_id','10','1 minute','300');
drop trigger if exists otaku_rate_limit on public.otaku_conversations;
create trigger otaku_rate_limit before insert on public.otaku_conversations for each row execute function otaku_private.enforce_rate_limit('requester_user_id','5','10 minutes','20');
drop trigger if exists otaku_rate_limit on public.otaku_companion_posts;
create trigger otaku_rate_limit before insert on public.otaku_companion_posts for each row execute function otaku_private.enforce_rate_limit('user_id','5','1 hour','10');
drop trigger if exists otaku_rate_limit on public.otaku_board_posts;
create trigger otaku_rate_limit before insert on public.otaku_board_posts for each row execute function otaku_private.enforce_rate_limit('user_id','5','10 minutes','30');
drop trigger if exists otaku_rate_limit on public.otaku_board_replies;
create trigger otaku_rate_limit before insert on public.otaku_board_replies for each row execute function otaku_private.enforce_rate_limit('user_id','5','1 minute','100');
drop trigger if exists otaku_rate_limit on public.otaku_goods_posts;
create trigger otaku_rate_limit before insert on public.otaku_goods_posts for each row execute function otaku_private.enforce_rate_limit('user_id','5','1 hour','10');
drop trigger if exists otaku_rate_limit on public.otaku_event_records;
create trigger otaku_rate_limit before insert on public.otaku_event_records for each row execute function otaku_private.enforce_rate_limit('user_id','5','10 minutes','20');
drop trigger if exists otaku_rate_limit on public.otaku_user_follows;
create trigger otaku_rate_limit before insert on public.otaku_user_follows for each row execute function otaku_private.enforce_rate_limit('follower_id','30','1 hour','100');

create index if not exists otaku_messages_rate_idx on public.otaku_messages(sender_id, created_at desc);
create index if not exists otaku_companion_posts_rate_idx on public.otaku_companion_posts(user_id, created_at desc);
create index if not exists otaku_board_posts_rate_idx on public.otaku_board_posts(user_id, created_at desc);
create index if not exists otaku_board_replies_rate_idx on public.otaku_board_replies(user_id, created_at desc);
create index if not exists otaku_goods_posts_rate_idx on public.otaku_goods_posts(user_id, created_at desc);
create index if not exists otaku_event_records_rate_idx on public.otaku_event_records(user_id, created_at desc);
create index if not exists otaku_user_follows_rate_idx on public.otaku_user_follows(follower_id, created_at desc);

-- Rollback:
-- drop trigger if exists otaku_rate_limit on public.otaku_messages;
-- drop trigger if exists otaku_rate_limit on public.otaku_conversations;
-- drop trigger if exists otaku_rate_limit on public.otaku_companion_posts;
-- drop trigger if exists otaku_rate_limit on public.otaku_board_posts;
-- drop trigger if exists otaku_rate_limit on public.otaku_board_replies;
-- drop trigger if exists otaku_rate_limit on public.otaku_goods_posts;
-- drop trigger if exists otaku_rate_limit on public.otaku_event_records;
-- drop trigger if exists otaku_rate_limit on public.otaku_user_follows;
-- drop function if exists otaku_private.enforce_rate_limit();
-- drop index if exists otaku_messages_rate_idx, otaku_companion_posts_rate_idx, otaku_board_posts_rate_idx, otaku_board_replies_rate_idx, otaku_goods_posts_rate_idx, otaku_event_records_rate_idx, otaku_user_follows_rate_idx;
