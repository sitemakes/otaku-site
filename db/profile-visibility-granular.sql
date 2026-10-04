alter table public.otaku_profiles
  add column if not exists show_username boolean not null default true,
  add column if not exists show_display_name boolean not null default true,
  add column if not exists show_avatar boolean not null default true;

drop view if exists public.otaku_public_profiles;
create view public.otaku_public_profiles with (security_invoker=true) as
select id,
 case when show_username then username else null end as username,
 case when show_display_name then display_name else null end as display_name,
 case when show_avatar then avatar_url else null end as avatar_url,
 case when show_age then age_range else null end as age_range,
 case when show_gender then gender else null end as gender,
 case when show_prefecture then prefecture else null end as prefecture,
 case when show_bio then bio else null end as bio,
 case when show_favorites then same_oshi_policy else null end as same_oshi_policy,
 show_favorites, show_attendance
from public.otaku_profiles;
revoke all on public.otaku_public_profiles from anon;
grant select on public.otaku_public_profiles to authenticated;
