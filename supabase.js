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

// Report unexpected browser failures without sending form values or account data.
(function installClientErrorReporting() {
  if (window.__otakuClientErrorReportingInstalled) return;
  window.__otakuClientErrorReportingInstalled = true;
  const sent = new Set();
  const send = (type, error) => {
    const message = String(error?.message || error || 'Unknown client error').slice(0, 500);
    const stack = String(error?.stack || '').slice(0, 2000);
    const key = `${type}:${message}:${location.pathname}`;
    if (sent.has(key)) return;
    sent.add(key);
    if (sent.size > 20) sent.delete(sent.values().next().value);
    const body = JSON.stringify({ type, message, stack, page: `${location.pathname}${location.search}` });
    try {
      fetch('/api/client-error', { method: 'POST', headers: { 'content-type': 'application/json' }, body, keepalive: true }).catch(() => {});
    } catch (_) {}
  };
  window.addEventListener('error', event => send('window.error', event.error || event.message));
  window.addEventListener('unhandledrejection', event => send('unhandledrejection', event.reason));
})();

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
