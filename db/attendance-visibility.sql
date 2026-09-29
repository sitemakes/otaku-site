alter table public.otaku_profiles add column if not exists show_attendance boolean not null default false;
drop view public.otaku_public_profiles;
create view public.otaku_public_profiles with (security_invoker=true) as
select id, username, display_name, avatar_url,
 case when show_age then age_range else null end as age_range,
 case when show_gender then gender else null end as gender,
 case when show_prefecture then prefecture else null end as prefecture,
 case when show_bio then bio else null end as bio,
 case when show_favorites then same_oshi_policy else null end as same_oshi_policy,
 show_favorites, show_attendance
from public.otaku_profiles;
grant select on public.otaku_public_profiles to authenticated;
