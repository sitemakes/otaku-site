create or replace function otaku_private.content_report_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare s jsonb; author uuid;
begin
 if auth.uid() is null or auth.uid()<>new.reporter_id then raise exception 'not_allowed' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('otaku-content-report:'||auth.uid(),0));
 if (select count(*) from public.otaku_content_reports where reporter_id=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'report_rate_limit' using errcode='23514'; end if;
 if new.kind='board' then
 select jsonb_build_object('body',body,'event_id',event_id,'idol_id',idol_id),user_id into s,author from public.otaku_board_posts where id=new.target_id and not hidden and otaku_private.board_target_visible(event_id,idol_id);
 else
 select jsonb_build_object('comment',comment,'rating',rating,'reviewee_id',reviewee_id),reviewer_id into s,author from public.otaku_reviews where id=new.target_id and visibility='visible';
 end if;
 if s is null or author=auth.uid() or not otaku_private.can_interact(author) then raise exception 'report_invalid_context' using errcode='42501'; end if;
 new.snapshot:=s; new.status:='open'; new.created_at:=now(); return new;
end $$;
