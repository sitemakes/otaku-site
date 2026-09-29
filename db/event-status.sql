-- Event status extension for the source-verified catalog.
alter table public.otaku_events
  add column event_status text not null default 'scheduled' check (event_status in ('scheduled','changed','postponed','cancelled')),
  add column status_note text,
  add column status_updated_at timestamptz,
  add constraint otaku_events_status_note_length check (status_note is null or char_length(status_note) between 1 and 1000);
create or replace function otaku_private.validate_catalog() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare parent_demo boolean; parent_status text;
begin
  if TG_OP = 'UPDATE' then
    if new.id <> old.id or new.is_demo <> old.is_demo then
      raise exception 'catalog_identity_immutable' using errcode='23514';
    end if;
    new.revision := old.revision + 1;
  else new.revision := 1;
  end if;
  new.updated_at := now();
  if TG_TABLE_NAME = 'otaku_events' then
    new.title := btrim(new.title); new.venue := btrim(new.venue);
    if new.event_status <> 'scheduled' and (new.status_note is null or btrim(new.status_note)='') then raise exception 'catalog_status_note_required' using errcode='23514'; end if;
    if new.event_status = 'scheduled' then new.status_note := null; end if;
    if TG_OP = 'UPDATE' and (new.event_status is distinct from old.event_status or new.status_note is distinct from old.status_note) then new.status_updated_at := now(); elsif TG_OP = 'INSERT' and new.event_status <> 'scheduled' then new.status_updated_at := now(); end if;
    if new.title = '' or new.venue = '' then raise exception 'catalog_name_required' using errcode='23514'; end if;
    if not isfinite(new.starts_at) or (new.ends_at is not null and not isfinite(new.ends_at)) then
      raise exception 'catalog_invalid_date' using errcode='23514';
    end if;
  else
    new.name := btrim(new.name);
    if new.name = '' then raise exception 'catalog_name_required' using errcode='23514'; end if;
  end if;
  if new.source_url is not null and (
    length(new.source_url) > 2048 or new.source_url !~ '^https://[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+(/[!-~]*)?$'
    or new.source_url ~ '[<>"''\\]'
  ) then raise exception 'catalog_invalid_source_url' using errcode='23514'; end if;
  if new.source_checked_at > now() or (new.source_checked_at is not null and not isfinite(new.source_checked_at)) then raise exception 'catalog_future_verification' using errcode='23514'; end if;
  if not new.is_demo and new.publication_status = 'published' and
    (new.source_url is null or new.source_kind is null or new.source_checked_at is null) then
    raise exception 'catalog_source_required' using errcode='23514';
  end if;
  if TG_TABLE_NAME <> 'otaku_idol_groups' then
    if new.group_id is null then raise exception 'catalog_group_required' using errcode='23514'; end if;
    select is_demo, publication_status into parent_demo, parent_status
      from public.otaku_idol_groups where id = new.group_id for share;
    if not found or parent_demo <> new.is_demo then
      raise exception 'catalog_group_type_mismatch' using errcode='23514';
    end if;
    if new.publication_status = 'published' and parent_status <> 'published' then
      raise exception 'catalog_publish_group_first' using errcode='23514';
    end if;
  elsif TG_OP = 'UPDATE' and new.publication_status <> 'published' and old.publication_status = 'published' then
    if exists(select 1 from public.otaku_idols where group_id = new.id and publication_status='published')
      or exists(select 1 from public.otaku_events where group_id = new.id and publication_status='published') then
      raise exception 'catalog_unpublish_children_first' using errcode='23514';
    end if;
  end if;
  return new;
end $$;

