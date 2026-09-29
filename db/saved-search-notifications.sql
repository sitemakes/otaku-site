create or replace function otaku_private.notify_saved_search_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.otaku_is_catalog_admin() then raise exception 'catalog_admin_required' using errcode='42501'; end if;
 if not (new.publication_status='published' and (TG_OP='INSERT' or old.publication_status<>'published')) then return new; end if;
 insert into public.otaku_notifications(user_id,kind,title,body,href)
 select distinct s.user_id,'event','保存した検索に一致する公演',new.title||'が公開されました。','event.html?id='||new.id
 from public.otaku_saved_searches s join public.otaku_notification_preferences p on p.user_id=s.user_id
 left join public.otaku_idol_groups g on g.id=new.group_id
 where p.in_app_enabled and p.event_reminder_enabled
   and (s.query='' or lower(new.title||' '||new.venue||' '||coalesce(new.prefecture,'')||' '||coalesce(new.city,'')||' '||coalesce(g.name,'')) like '%'||lower(s.query)||'%')
   and (s.group_id is null or s.group_id=new.group_id)
   and (s.month is null or to_char(new.starts_at at time zone 'Asia/Tokyo','YYYY-MM')=s.month);
 return new;
end $$;
revoke all on function otaku_private.notify_saved_search_event() from public,anon,authenticated;
drop trigger if exists otaku_saved_search_event_notify on public.otaku_events;
create trigger otaku_saved_search_event_notify after insert or update on public.otaku_events for each row execute function otaku_private.notify_saved_search_event();
