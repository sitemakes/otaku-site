alter table public.otaku_profiles
 add column if not exists show_age boolean not null default true,
 add column if not exists show_gender boolean not null default true,
 add column if not exists show_prefecture boolean not null default true,
 add column if not exists show_bio boolean not null default true,
 add column if not exists show_favorites boolean not null default true;
create or replace view public.otaku_public_profiles with (security_invoker=true) as
select id, username, display_name,
 case when show_age then age_range else null end as age_range,
 case when show_gender then gender else null end as gender,
 case when show_prefecture then prefecture else null end as prefecture,
 case when show_bio then bio else null end as bio,
 case when show_favorites then same_oshi_policy else null end as same_oshi_policy,
 show_favorites
from public.otaku_profiles;
revoke all on public.otaku_public_profiles from anon;
grant select on public.otaku_public_profiles to authenticated;
