alter table public.otaku_notifications add column if not exists archived_at timestamptz;
grant update(archived_at) on public.otaku_notifications to authenticated;
