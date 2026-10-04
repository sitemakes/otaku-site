create table if not exists public.otaku_event_checklist_items (
  event_id uuid not null references public.otaku_events(id) on delete cascade,
  user_id uuid not null references public.otaku_profiles(id) on delete cascade,
  item_key text not null check (item_key in ('ticket','id','transport','goods','venue','contact')),
  checked boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (event_id,user_id,item_key)
);
create index if not exists otaku_event_checklist_user_idx on public.otaku_event_checklist_items(user_id,updated_at desc);
alter table public.otaku_event_checklist_items enable row level security;
revoke all on public.otaku_event_checklist_items from public,anon,authenticated;
grant select,insert,update,delete on public.otaku_event_checklist_items to authenticated;
drop policy if exists event_checklist_select_own on public.otaku_event_checklist_items;
drop policy if exists event_checklist_insert_own on public.otaku_event_checklist_items;
drop policy if exists event_checklist_update_own on public.otaku_event_checklist_items;
drop policy if exists event_checklist_delete_own on public.otaku_event_checklist_items;
create policy event_checklist_select_own on public.otaku_event_checklist_items for select to authenticated using ((select auth.uid())=user_id);
create policy event_checklist_insert_own on public.otaku_event_checklist_items for insert to authenticated with check ((select auth.uid())=user_id);
create policy event_checklist_update_own on public.otaku_event_checklist_items for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create policy event_checklist_delete_own on public.otaku_event_checklist_items for delete to authenticated using ((select auth.uid())=user_id);
