-- Keep public records hidden when their event is no longer published.
drop policy if exists event_records_anon_read on public.otaku_event_records;
drop policy if exists event_records_authenticated_read on public.otaku_event_records;
create policy event_records_anon_read on public.otaku_event_records
  for select to anon using (visibility='public' and not hidden and exists (
    select 1 from public.otaku_events e where e.id=event_id and e.publication_status='published'));
create policy event_records_authenticated_read on public.otaku_event_records
  for select to authenticated using (
    user_id=(select auth.uid()) or
    (visibility='public' and not hidden and otaku_private.can_interact(user_id) and exists (
      select 1 from public.otaku_events e where e.id=event_id and e.publication_status='published')));
