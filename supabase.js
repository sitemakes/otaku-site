const OTAKU_SUPABASE_URL = 'https://pfyvsweuvdnpmvabfflh.supabase.co';
const OTAKU_SUPABASE_KEY = 'sb_publishable_FJ9hNx9T4-sNV6Ypv94vJA_cCq5TxUp';

const otakuSupabase = window.supabase.createClient(
  OTAKU_SUPABASE_URL,
  OTAKU_SUPABASE_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  }
);

async function otakuGetUser() {
  const { data, error } = await otakuSupabase.auth.getUser();
  if (error) return null;
  return data.user ?? null;
}

async function otakuGetProfile(userId) {
  if (!userId) return null;
  const { data, error } = await otakuSupabase
    .from('otaku_profiles')
    .select('*')
    .eq('id', userId)
    .maybeSingle();
  if (error) return null;
  return data ?? null;
}

function otakuNextUrl(defaultPath = 'index.html') {
  const next = new URLSearchParams(location.search).get('next');
  if (!next) return defaultPath;
  try {
    const url = new URL(next, location.origin);
    if (url.origin !== location.origin) return defaultPath;
    return url.pathname + url.search + url.hash;
  } catch {
    return defaultPath;
  }
}

function otakuLoginUrl(next = location.href) {
  return `login.html?next=${encodeURIComponent(next)}`;
}

function otakuProfileUrl(next = location.href) {
  return `profile.html?next=${encodeURIComponent(next)}`;
}
