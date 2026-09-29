alter table public.otaku_profiles
 add column if not exists companion_preferred_gender text check (companion_preferred_gender is null or companion_preferred_gender in ('any','male','female','other')),
 add column if not exists companion_age_min smallint check (companion_age_min is null or companion_age_min between 15 and 99),
 add column if not exists companion_age_max smallint check (companion_age_max is null or companion_age_max between 15 and 99),
 add column if not exists companion_same_oshi text check (companion_same_oshi is null or companion_same_oshi in ('any','yes','no'));
