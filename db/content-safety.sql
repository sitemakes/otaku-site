alter table public.otaku_board_posts add column hidden boolean not null default false;
drop policy "otaku board visible posts" on public.otaku_board_posts;
create policy "otaku board visible posts" on public.otaku_board_posts for select to authenticated using(not hidden and otaku_private.board_target_visible(event_id,idol_id) and otaku_private.can_interact(user_id));
create table public.otaku_content_actions (
 id bigint generated always as identity primary key,
 report_id uuid not null references public.otaku_content_reports(id) on delete cascade,
 actor_id uuid not null, action text not null, reason text not null, created_at timestamptz not null default now()
);
alter table public.otaku_content_actions enable row level security;
revoke all on public.otaku_content_actions from public,anon,authenticated;
grant select on public.otaku_content_actions to authenticated;
create policy "otaku admins read content actions" on public.otaku_content_actions for select to authenticated using((select public.otaku_is_catalog_admin()));
create function public.otaku_moderate_content(report uuid, action text, reason text) returns void language plpgsql security definer set search_path='' as $$
declare r public.otaku_content_reports;
begin
 if auth.uid() is null or not public.otaku_is_catalog_admin() then raise exception 'not_allowed' using errcode='42501'; end if;
 if action not in ('hide','restore','resolve') or action is null or reason is null or char_length(btrim(reason)) not between 1 and 500 then raise exception 'invalid_action' using errcode='23514'; end if;
 select * into r from public.otaku_content_reports where id=report for update;
 if not found then raise exception 'report_not_found' using errcode='23514'; end if;
 if action<>'resolve' then
 if r.kind='board' then update public.otaku_board_posts set hidden=(action='hide') where id=r.target_id;
 else update public.otaku_reviews set visibility=case when action='hide' then 'hidden' else 'visible' end, moderation_reason=btrim(reason) where id=r.target_id; end if;
 if not found then raise exception 'content_not_found' using errcode='23514'; end if;
 end if;
 update public.otaku_content_reports set status=case when action='restore' then 'open' else 'resolved' end where id=report;
 insert into public.otaku_content_actions(report_id,actor_id,action,reason) values(report,auth.uid(),action,btrim(reason));
end $$;
revoke all on function public.otaku_moderate_content(uuid,text,text) from public,anon,authenticated;
grant execute on function public.otaku_moderate_content(uuid,text,text) to authenticated;

create or replace function otaku_private.board_guard() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' and public.otaku_is_catalog_admin() and (to_jsonb(new)-'hidden')=(to_jsonb(old)-'hidden') then return new; end if;
 if auth.uid() is null or new.user_id<>auth.uid() then raise exception 'board_not_allowed' using errcode='42501'; end if;
 if tg_op='UPDATE' and (to_jsonb(new)-array['body','updated_at']) is distinct from (to_jsonb(old)-array['body','updated_at']) then raise exception 'board_not_allowed' using errcode='42501'; end if;
 if not otaku_private.board_target_visible(new.event_id,new.idol_id) then raise exception 'board_target_unavailable' using errcode='42501'; end if;
 new.body:=btrim(new.body); if new.body is null or new.body='' or length(new.body)>2000 then raise exception 'board_content_invalid' using errcode='23514'; end if;
 if tg_op='INSERT' then new.hidden:=false; new.created_at:=now(); end if;
 new.updated_at:=now(); return new;
end $$;

create or replace function otaku_private.block_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare a uuid; b uuid;
begin
 if TG_OP='DELETE' then
 a:=old.blocker_id; b:=old.blocked_id;
 -- Cascading profile removal: allow only after the referenced profile is absent.
 if not exists(select 1 from public.otaku_profiles where id=a) or not exists(select 1 from public.otaku_profiles where id=b) then return old; end if;
 else a:=new.blocker_id; b:=new.blocked_id; new.created_at:=now(); end if;
 if auth.uid() is null or auth.uid()<>a then raise exception 'safety_not_allowed' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(least(a,b)::text||greatest(a,b)::text,0));
 if TG_OP='DELETE' then return old; end if; return new;
end $$;
revoke all on function otaku_private.block_guard(),otaku_private.board_guard() from public,anon,authenticated;
