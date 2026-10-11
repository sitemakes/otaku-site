const SUPABASE_URL = 'https://pfyvsweuvdnpmvabfflh.supabase.co/rest/v1/otaku_events';
const SUPABASE_KEY = 'sb_publishable_FJ9hNx9T4-sNV6Ypv94vJA_cCq5TxUp';
const SITE_URL = 'https://otaku-live-mvp.vercel.app/';
const IMAGE_URL = `${SITE_URL}og-default.jpg`;
const TAGS = '#OTAKULIVE #アイドル';
const JST = 'Asia/Tokyo';

const jstParts = (date) => Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
  timeZone: JST, year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
}).formatToParts(date).filter(({ type }) => type !== 'literal').map(({ type, value }) => [type, value]));

const dayKey = (date) => { const p = jstParts(date); return `${p.year}-${p.month}-${p.day}`; };
const addDays = (date, days) => new Date(date.getTime() + days * 86400000);
const dateLabel = (date) => { const p = jstParts(new Date(date)); return `${Number(p.month)}/${Number(p.day)}(${'SunMonTueWedThuFriSat'.indexOf(p.weekday) / 3 >= 0 ? ['日','月','火','水','木','金','土']['SunMonTueWedThuFriSat'.indexOf(p.weekday) / 3] : p.weekday}) ${p.hour}:${p.minute}`; };
const groupName = (event) => event.otaku_idol_groups?.name || 'グループ名未設定';
const eventLine = (event) => `・${groupName(event)} ${event.title} ${dateLabel(event.starts_at)} ${event.venue || '会場未定'}${event.prefecture ? `（${event.prefecture}）` : ''}`;
const finish = (headline, lines, instagram) => `${headline}\n${lines.join('\n')}\n${instagram ? 'プロフィールのリンクから見られます' : SITE_URL}\n${TAGS}`;

function fitPost(headline, events, instagram, limit, suffix = '') {
  let count = Math.min(5, events.length);
  while (count >= 0) {
    const rest = events.length > count ? `\nほか${events.length - count}件` : '';
    const text = finish(headline, events.slice(0, count).map(eventLine).concat(rest ? [rest.trim()] : []), instagram) + suffix;
    if (text.length <= limit) return text;
    count -= 1;
  }
  return finish(headline, [], instagram) + suffix;
}

export function buildPosts(events, now = new Date()) {
  const current = new Date(now);
  const currentJst = jstParts(current);
  const sorted = [...events].sort((a, b) => new Date(a.starts_at) - new Date(b.starts_at));
  const posts = [];
  const fresh = sorted.filter((event) => current - new Date(event.created_at) >= 0 && current - new Date(event.created_at) <= 86400000);
  if (fresh.length) {
    posts.push({ kind: 'new', headline: '🆕 新着公演を追加しました', events: fresh });
  } else {
    const tomorrow = dayKey(addDays(current, 1));
    const next = sorted.filter((event) => dayKey(new Date(event.starts_at)) === tomorrow);
    if (next.length) posts.push({ kind: 'tomorrow', headline: '📅 明日の公演', events: next });
  }
  if (currentJst.weekday === 'Mon') {
    const weekEvents = sorted.filter((event) => {
      const start = new Date(event.starts_at); return start >= current && start < addDays(current, 7);
    });
    const counts = new Map();
    for (const event of weekEvents) counts.set(groupName(event), (counts.get(groupName(event)) || 0) + 1);
    const groups = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
    if (groups.length) posts.push({ kind: 'week', headline: `🎤 今週の公演（${Number(currentJst.month)}/${Number(currentJst.day)}〜${Number(jstParts(addDays(current, 6)).month)}/${Number(jstParts(addDays(current, 6)).day)}）`, groups });
  }
  const limited = posts.slice(0, 2);
  return limited.map((post) => {
    if (post.kind === 'week') {
      const lines = post.groups.slice(0, 8).map(([name, count]) => `・${name} ${count}公演`);
      if (post.groups.length > 8) lines.push(`・ほか${post.groups.length - 8}グループ`);
      return { threads: finish(post.headline, lines, false), instagram: finish(post.headline, lines, true) };
    }
    return { threads: fitPost(post.headline, post.events, false, 500), instagram: fitPost(post.headline, post.events, true, 2200) };
  });
}

async function jsonRequest(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) { let message = `HTTP ${response.status}`; try { message += `: ${(await response.json()).error?.message || 'request failed'}`; } catch {} throw new Error(message); }
  return response.json();
}
async function postThreads(text) {
  const base = 'https://graph.threads.net/v1.0';
  const made = await jsonRequest(`${base}/${process.env.THREADS_USER_ID}/threads`, { method: 'POST', body: new URLSearchParams({ media_type: 'TEXT', text, access_token: process.env.THREADS_TOKEN }) });
  await jsonRequest(`${base}/${process.env.THREADS_USER_ID}/threads_publish`, { method: 'POST', body: new URLSearchParams({ creation_id: made.id, access_token: process.env.THREADS_TOKEN }) });
}
async function postInstagram(caption) {
  const base = 'https://graph.instagram.com/v22.0';
  const made = await jsonRequest(`${base}/${process.env.IG_USER_ID}/media`, { method: 'POST', body: new URLSearchParams({ image_url: IMAGE_URL, caption, access_token: process.env.IG_TOKEN }) });
  let status = 'IN_PROGRESS';
  for (let attempt = 0; attempt < 10; attempt += 1) {
    if (attempt > 0) await new Promise((resolve) => setTimeout(resolve, 3000));
    const statusUrl = `${base}/${made.id}?fields=status_code&access_token=${encodeURIComponent(process.env.IG_TOKEN)}`;
    const result = await jsonRequest(statusUrl, { method: 'GET' });
    status = result.status_code;
    if (status === 'FINISHED') break;
    if (status === 'ERROR' || status === 'EXPIRED') throw new Error(`Instagram container ${status}`);
  }
  if (status !== 'FINISHED') throw new Error('Instagram container did not finish in time');
  await jsonRequest(`${base}/${process.env.IG_USER_ID}/media_publish`, { method: 'POST', body: new URLSearchParams({ creation_id: made.id, access_token: process.env.IG_TOKEN }) });
}

async function main() {
  const params = new URLSearchParams({ select: 'id,title,venue,prefecture,starts_at,created_at,otaku_idol_groups(name)', publication_status: 'eq.published', is_demo: 'eq.false', starts_at: `gte.${new Date().toISOString()}`, order: 'starts_at.asc', limit: '1000' });
  const events = await jsonRequest(`${SUPABASE_URL}?${params}`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } });
  const posts = buildPosts(events);
  const dryRun = process.argv.includes('--dry-run') || process.env.DRY_RUN === '1';
  let failures = 0;
  for (const [channel, configured, texts, send] of [['Threads', process.env.THREADS_USER_ID && process.env.THREADS_TOKEN, posts.map((p) => p.threads), postThreads], ['Instagram', process.env.IG_USER_ID && process.env.IG_TOKEN, posts.map((p) => p.instagram), postInstagram]]) {
    if (dryRun) {
      if (!texts.length) console.log(`${channel}: 本日の投稿はありません`);
      else texts.forEach((text, index) => console.log(`${channel}${configured ? '' : '（未設定・本番ではスキップ）'} ${index + 1} (${text.length}文字):\n${text}`));
      continue;
    }
    if (!configured) { console.log(`${channel}: スキップ（未設定）`); continue; }
    for (const [index, text] of texts.entries()) {
      try { await send(text); }
      catch (error) { failures += 1; console.error(`${channel} ${index + 1}: ${error.message}`); }
    }
  }
  if (failures) process.exitCode = 1;
}

if (process.argv[1]?.endsWith('post.mjs')) main().catch((error) => { console.error(`投稿失敗: ${error.message}`); process.exitCode = 1; });
