-- OTAKU LIVE only. Auth users and other applications are never deleted.
revoke update on public.otaku_notifications from authenticated;
grant update(read_at) on public.otaku_notifications to authenticated;
revoke update on public.otaku_board_posts from authenticated;
grant update(title,body,category) on public.otaku_board_posts to authenticated;
drop policy "otaku board visible posts" on public.otaku_board_posts;
create policy "otaku board visible posts" on public.otaku_board_posts for select to authenticated
using (otaku_private.board_target_visible(event_id,idol_id) and otaku_private.can_interact(user_id));
create or replace function otaku_private.review_moderation_audit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.otaku_is_catalog_admin() then raise exception 'not_allowed' using errcode='42501'; end if;
 if old.visibility is distinct from new.visibility or old.moderation_reason is distinct from new.moderation_reason then
 insert into public.otaku_review_moderation_log(review_id,actor_id,from_visibility,to_visibility,reason)
 values(new.id,auth.uid(),old.visibility,new.visibility,new.moderation_reason);
 end if; return new;
end $$;
revoke all on function otaku_private.review_moderation_audit() from public,anon,authenticated;

alter table public.otaku_notification_preferences alter column in_app_enabled set default false;
-- The old automatic opt-in is not evidence of consent. Leave previously saved choices intact.
update public.otaku_notification_preferences set in_app_enabled=false where updated_at=created_at;

create or replace function otaku_private.notify_board_post() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or auth.uid()<>new.user_id then raise exception 'not_allowed' using errcode='42501'; end if;
 insert into public.otaku_notifications(user_id,kind,title,body,href)
 select distinct p.user_id,'board','掲示板に新しい投稿があります','参加中の掲示板に新しい書き込みがありました。',
 case when new.event_id is not null then 'board.html?event='||new.event_id else 'board.html?idol='||new.idol_id end
 from public.otaku_board_posts p join public.otaku_notification_preferences n on n.user_id=p.user_id
 where p.user_id<>new.user_id and n.in_app_enabled and n.board_enabled
 and ((new.event_id is not null and p.event_id=new.event_id) or (new.idol_id is not null and p.idol_id=new.idol_id))
 and not exists(select 1 from public.otaku_user_blocks b where
 (b.blocker_id=p.user_id and b.blocked_id=new.user_id) or (b.blocker_id=new.user_id and b.blocked_id=p.user_id));
 return new;
end $$;
create or replace function otaku_private.notify_dm() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.otaku_conversations; recipient uuid;
begin
 if auth.uid() is null or auth.uid()<>new.sender_id then raise exception 'not_allowed' using errcode='42501'; end if;
 select * into c from public.otaku_conversations where id=new.conversation_id;
 if not found or new.sender_id not in(c.owner_user_id,c.requester_user_id) then raise exception 'not_allowed' using errcode='42501'; end if;
 recipient:=case when c.owner_user_id=new.sender_id then c.requester_user_id else c.owner_user_id end;
 if exists(select 1 from public.otaku_notification_preferences where user_id=recipient and in_app_enabled and dm_enabled)
 and not exists(select 1 from public.otaku_user_blocks where (blocker_id=recipient and blocked_id=new.sender_id) or (blocker_id=new.sender_id and blocked_id=recipient)) then
 insert into public.otaku_notifications(user_id,kind,title,body,href) values(recipient,'dm','新しいDMがあります','新しいメッセージが届きました。','chat.html?id='||new.conversation_id);
 end if; return new;
end $$;
revoke all on function otaku_private.notify_board_post(),otaku_private.notify_dm() from public,anon,authenticated;

create table public.otaku_content_reports(
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.otaku_profiles(id) on delete cascade,
 kind text not null check(kind in ('board','review')),
 target_id uuid not null,
 reason text not null check(char_length(btrim(reason)) between 1 and 1000),
 snapshot jsonb not null default '{}',
 status text not null default 'open' check(status in ('open','resolved')),
 created_at timestamptz not null default now(),
 unique(reporter_id,kind,target_id)
);
alter table public.otaku_content_reports enable row level security;
revoke all on public.otaku_content_reports from public,anon,authenticated;
grant select,insert on public.otaku_content_reports to authenticated;
grant update(status) on public.otaku_content_reports to authenticated;
create policy "otaku content report own or admin" on public.otaku_content_reports for select to authenticated using(reporter_id=(select auth.uid()) or (select public.otaku_is_catalog_admin()));
create policy "otaku content report insert" on public.otaku_content_reports for insert to authenticated with check(reporter_id=(select auth.uid()));
create policy "otaku content report admin update" on public.otaku_content_reports for update to authenticated using((select public.otaku_is_catalog_admin())) with check((select public.otaku_is_catalog_admin()));
create function otaku_private.content_report_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare s jsonb; author uuid;
begin
 if auth.uid() is null or auth.uid()<>new.reporter_id then raise exception 'not_allowed' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('otaku-content-report:'||auth.uid(),0));
 if (select count(*) from public.otaku_content_reports where reporter_id=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'report_rate_limit' using errcode='23514'; end if;
 if new.kind='board' then
 select jsonb_build_object('body',body,'event_id',event_id,'idol_id',idol_id),user_id into s,author from public.otaku_board_posts where id=new.target_id and otaku_private.board_target_visible(event_id,idol_id);
 else
 select jsonb_build_object('comment',comment,'rating',rating,'reviewee_id',reviewee_id),reviewer_id into s,author from public.otaku_reviews where id=new.target_id and visibility='visible';
 end if;
 if s is null or author=auth.uid() or not otaku_private.can_interact(author) then raise exception 'report_invalid_context' using errcode='42501'; end if;
 new.snapshot:=s; new.status:='open'; new.created_at:=now(); return new;
end $$;
create trigger otaku_content_report_guard before insert on public.otaku_content_reports for each row execute function otaku_private.content_report_guard();
revoke all on function otaku_private.content_report_guard() from public,anon,authenticated;

-- Actual withdrawal is invoked only by the signed-in owner after explicit UI confirmation.
create function public.otaku_withdraw(confirmation text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or confirmation is distinct from 'OTAKU LIVEを退会する' then raise exception 'not_allowed' using errcode='42501'; end if;
 if public.otaku_is_catalog_admin() then raise exception 'admin_transfer_required' using errcode='42501'; end if;
 delete from public.otaku_profiles where id=auth.uid();
end $$;
revoke all on function public.otaku_withdraw(text) from public,anon,authenticated;
grant execute on function public.otaku_withdraw(text) to authenticated;
