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

// Share one server-verified user lookup per page. Each page loads several
// modules that all ask for the user, and auth.getUser() calls run one at a
// time, so separate lookups queue up and delay rendering. Only a signed-in
// result is kept; it is dropped when the session changes.
let otakuUserPromise = null;
otakuSupabase.auth.onAuthStateChange(event => {
  if (event === 'SIGNED_IN' || event === 'SIGNED_OUT' || event === 'USER_UPDATED') otakuUserPromise = null;
});

function otakuGetUser() {
  if (!otakuUserPromise) {
    const pending = otakuSupabase.auth.getUser()
      .then(({ data, error }) => (error ? null : data.user ?? null))
      .catch(() => null)
      .then(user => {
        if (!user && otakuUserPromise === pending) otakuUserPromise = null;
        return user;
      });
    otakuUserPromise = pending;
  }
  return otakuUserPromise;
}

// The signed-in user's own full profile. Other users' private fields are not
// selectable on otaku_profiles, so the own row comes from a dedicated RPC.
async function otakuGetProfile(userId) {
  if (!userId) return null;
  const { data, error } = await otakuSupabase.rpc('otaku_my_profile').maybeSingle();
  if (error || data?.id !== userId) return null;
  return data;
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

function otakuRateLimitMessage(error) {
  const text = [error?.message, error?.code, error?.details].filter(Boolean).join(' ');
  return text.includes('rate_limited') ? '短い時間に送信が多すぎます。少し時間を置いてからお試しください。' : null;
}

function otakuProfileUrl(next = location.href) {
  return `profile.html?next=${encodeURIComponent(next)}`;
}
