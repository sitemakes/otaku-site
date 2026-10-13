import { appendFileSync } from 'node:fs';
import { readFileSync } from 'node:fs';

const SUPABASE_URL = 'https://pfyvsweuvdnpmvabfflh.supabase.co/rest/v1/otaku_events';
const SUPABASE_KEY = 'sb_publishable_FJ9hNx9T4-sNV6Ypv94vJA_cCq5TxUp';
const SITE_URL = 'https://otaku-live-mvp.vercel.app/';
const IMAGE_URL = `${SITE_URL}og-default.jpg`;
const TAGS = '#OTAKULIVE #アイドル';
const JST = 'Asia/Tokyo';
const TEMPLATES = { A: 'A', B: 'B', C: 'C' };
const CALLS = ['今週末の現場、一緒に行く人いますか？👀', '次の現場、もう決めた？🎤', '一人参戦が不安なら、同行募集を使ってみて🤝', '推しの公演、見逃してない？👀', '現場の予定、ここでまとめてチェック✅'];

const jstParts = (date) => Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
  timeZone: JST, year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
}).formatToParts(date).filter(({ type }) => type !== 'literal').map(({ type, value }) => [type, value]));

const dayKey = (date) => { const p = jstParts(date); return `${p.year}-${p.month}-${p.day}`; };
const addDays = (date, days) => new Date(date.getTime() + days * 86400000);
const dateLabel = (date) => { const p = jstParts(new Date(date)); return `${Number(p.month)}/${Number(p.day)}(${'SunMonTueWedThuFriSat'.indexOf(p.weekday) / 3 >= 0 ? ['日','月','火','水','木','金','土']['SunMonTueWedThuFriSat'.indexOf(p.weekday) / 3] : p.weekday}) ${p.hour}:${p.minute}`; };
const groupName = (event) => event.otaku_idol_groups?.name || 'グループ名未設定';
const eventTitle = (event) => event.title?.startsWith(groupName(event)) ? event.title : `${groupName(event)} ${event.title}`;
const eventLine = (event) => `・${event.title} ${dateLabel(event.starts_at)} ${event.prefecture || ''}`.trim();
const groupedLine = (event) => `【${groupName(event)}】${dateLabel(event.starts_at)} ${event.venue || '会場未定'}`;
const finish = (headline, lines, instagram) => `${headline}\n${lines.join('\n')}\n${instagram ? 'プロフィールのリンクから見られます' : SITE_URL}\n${TAGS}`;

export function xLength(text) {
  let length = 0;
  let last = 0;
  for (const match of String(text).matchAll(/https?:\/\/[^\s]+/g)) {
    for (const char of String(text).slice(last, match.index)) length += /[\x00-\x7f]/.test(char) ? 1 : 2;
    length += 23;
    last = match.index + match[0].length;
  }
  for (const char of String(text).slice(last)) length += /[\x00-\x7f]/.test(char) ? 1 : 2;
  return length;
}

export function detectTemplate(text) {
  const first = String(text || '').split(/\r?\n/, 1)[0];
  if (first === '🆕 新着公演を追加しました' || first === '📅 明日の公演' || first.startsWith('🎤 今週の公演（')) return 'A';
  if (first === '🆕 新着公演' || first === '📅 明日の公演【グループ別】' || first === '🎤 今週の公演【グループ別】') return 'B';
  if (CALLS.includes(first)) return 'C';
  return null;
}

const callLine = (now, kind, count, groups) => `${CALLS[Math.floor(Number(jstParts(now).day) % CALLS.length)]}\n${kind === 'new' ? `${groups.slice(0, 3).join('、')}など、新しく${count}公演を追加しました。` : `${kind === 'tomorrow' ? '明日' : '今週'}は${count}公演`}`;

function fitPost(headline, events, instagram, limit, suffix = '', line = eventLine) {
  let count = Math.min(5, events.length);
  while (count >= 0) {
    const rest = events.length > count ? `\nほか${events.length - count}件` : '';
    const text = finish(headline, events.slice(0, count).map(line).concat(rest ? [rest.trim()] : []), instagram) + suffix;
    if (text.length <= limit) return text;
    count -= 1;
  }
  return finish(headline, [], instagram) + suffix;
}

function fitX(headline, events, line = eventLine) {
  let count = Math.min(5, events.length);
  while (count >= 0) {
    const rest = events.length > count ? `\nほか${events.length - count}件` : '';
    const text = finish(headline, events.slice(0, count).map(line).concat(rest ? [rest.trim()] : []), false);
    if (xLength(text) <= 280) return text;
    count -= 1;
  }
  return finish(headline, [], false);
}

function fitXLines(headline, lines) {
  for (let count = lines.length; count >= 0; count -= 1) {
    const text = finish(headline, lines.slice(0, count), false);
    if (xLength(text) <= 280) return text;
  }
  return finish(headline, [], false);
}

export function buildPosts(events, now = new Date(), template = 'A') {
  const current = new Date(now);
  const currentJst = jstParts(current);
  const sorted = [...events].sort((a, b) => new Date(a.starts_at) - new Date(b.starts_at));
  const posts = [];
  const fresh = sorted.filter((event) => current - new Date(event.created_at) >= 0 && current - new Date(event.created_at) <= 86400000);
  if (fresh.length) {
    posts.push({ kind: 'new', headline: template === 'A' ? '🆕 新着公演を追加しました' : template === 'B' ? '🆕 新着公演' : callLine(current, 'new', fresh.length, fresh.map(groupName)), events: fresh });
  } else {
    const tomorrow = dayKey(addDays(current, 1));
    const next = sorted.filter((event) => dayKey(new Date(event.starts_at)) === tomorrow);
    if (next.length) posts.push({ kind: 'tomorrow', headline: template === 'A' ? '📅 明日の公演' : template === 'B' ? '📅 明日の公演【グループ別】' : callLine(current, 'tomorrow', next.length, []), events: next });
  }
  if (currentJst.weekday === 'Mon') {
    const weekEvents = sorted.filter((event) => {
      const start = new Date(event.starts_at); return start >= current && start < addDays(current, 7);
    });
    const counts = new Map();
    for (const event of weekEvents) counts.set(groupName(event), (counts.get(groupName(event)) || 0) + 1);
    const groups = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
    if (groups.length) posts.push({ kind: 'week', headline: template === 'A' ? `🎤 今週の公演（${Number(currentJst.month)}/${Number(currentJst.day)}〜${Number(jstParts(addDays(current, 6)).month)}/${Number(jstParts(addDays(current, 6)).day)}）` : template === 'B' ? '🎤 今週の公演【グループ別】' : callLine(current, 'week', weekEvents.length, []), groups, events: weekEvents });
  }
  const limited = posts.slice(0, 2);
  return limited.map((post) => {
    if (post.kind === 'week') {
      const lines = template === 'B' ? post.groups.slice(0, 8).map(([name, count]) => `【${name}】${count}公演`) : post.groups.slice(0, 8).map(([name, count]) => `・${name} ${count}公演`);
      if (post.groups.length > 8) lines.push(`・ほか${post.groups.length - 8}グループ`);
      if (template === 'C') return { threads: finish(post.headline, [], false), instagram: finish(post.headline, [], true), x: finish(post.headline, [], false) };
      return { threads: finish(post.headline, lines, false), instagram: finish(post.headline, lines, true), x: fitXLines(post.headline, lines) };
    }
    return { threads: fitPost(post.headline, post.events, false, 500, '', template === 'B' ? groupedLine : eventLine), instagram: fitPost(post.headline, post.events, true, 2200, '', template === 'B' ? groupedLine : eventLine), x: fitX(post.headline, post.events, template === 'B' ? groupedLine : eventLine) };
  });
}

export function chooseTemplate(stats, random = Math.random) {
  const names = ['A', 'B', 'C'];
  if (!stats) return names[Math.floor(random() * names.length)];
  const under = names.filter((name) => (stats[name]?.posts || 0) < 3);
  if (under.length) return under.sort((a, b) => (stats[a]?.posts || 0) - (stats[b]?.posts || 0) || names.indexOf(a) - names.indexOf(b))[0];
  if (random() < 0.2) return names[Math.floor(random() * names.length)];
  return names.sort((a, b) => ((stats[b]?.engagements || 0) / (stats[b]?.views || 1)) - ((stats[a]?.engagements || 0) / (stats[a]?.views || 1)))[0];
}

export async function fetchThreadsStats(token, userId, now = new Date()) {
  const since = new Date(now.getTime() - 30 * 86400000);
  const list = await jsonRequest(`https://graph.threads.net/v1.0/${userId}/threads?fields=id,text,timestamp&limit=100&access_token=${encodeURIComponent(token)}`, { method: 'GET' });
  const stats = { A: { posts: 0, views: 0, engagements: 0 }, B: { posts: 0, views: 0, engagements: 0 }, C: { posts: 0, views: 0, engagements: 0 } };
  for (const post of list.data || []) { if (new Date(post.timestamp) < since) continue; const kind = detectTemplate(post.text); if (!kind) continue; const insight = await jsonRequest(`https://graph.threads.net/v1.0/${post.id}/insights?metric=views,likes,replies,reposts,quotes&access_token=${encodeURIComponent(token)}`, { method: 'GET' }); const values = Object.fromEntries((insight.data || []).map((item) => [item.name, Number(item.values?.[0]?.value || item.value || 0)])); stats[kind].posts += 1; stats[kind].views += values.views || 0; stats[kind].engagements += (values.likes || 0) + (values.replies || 0) + (values.reposts || 0) + (values.quotes || 0); }
  return stats;
}

async function jsonRequest(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) { let message = `HTTP ${response.status}`; try { message += `: ${(await response.json()).error?.message || 'request failed'}`; } catch {} throw new Error(message); }
  return response.json();
}
async function alreadyPostedRecently() {
  let url;
  if (process.env.THREADS_TOKEN) {
    url = `https://graph.threads.net/v1.0/me/threads?fields=id,timestamp&limit=1&access_token=${encodeURIComponent(process.env.THREADS_TOKEN)}`;
  } else if (process.env.IG_TOKEN) {
    url = `https://graph.instagram.com/v22.0/me/media?fields=id,timestamp&limit=1&access_token=${encodeURIComponent(process.env.IG_TOKEN)}`;
  } else {
    console.log('投稿済みか確認できないため投稿を続けます（トークン未設定）');
    return false;
  }
  try {
    const result = await jsonRequest(url, { method: 'GET' });
    const timestamp = result.data?.[0]?.timestamp;
    const elapsed = Date.now() - new Date(timestamp).getTime();
    return Boolean(timestamp && elapsed >= 0 && elapsed <= 20 * 60 * 60 * 1000);
  } catch (error) {
    console.log(`投稿済みか確認できないため投稿を続けます: ${error.message}`);
    return false;
  }
}
async function fetchThreadsUser() {
  const result = await jsonRequest(`https://graph.threads.net/v1.0/me?fields=id,username&access_token=${encodeURIComponent(process.env.THREADS_TOKEN)}`, { method: 'GET' });
  return { id: result.id, username: result.username };
}
async function resolveThreadsUser() {
  return process.env.THREADS_USER_ID ? { id: process.env.THREADS_USER_ID } : fetchThreadsUser();
}
async function fetchInstagramUser() {
  const result = await jsonRequest(`https://graph.instagram.com/v22.0/me?fields=user_id,username&access_token=${encodeURIComponent(process.env.IG_TOKEN)}`, { method: 'GET' });
  return { id: result.user_id || result.id, username: result.username };
}
async function resolveInstagramUser() {
  return process.env.IG_USER_ID ? { id: process.env.IG_USER_ID } : fetchInstagramUser();
}
async function postThreads(text) {
  const base = 'https://graph.threads.net/v1.0';
  const user = await resolveThreadsUser();
  const made = await jsonRequest(`${base}/${user.id}/threads`, { method: 'POST', body: new URLSearchParams({ media_type: 'TEXT', text, access_token: process.env.THREADS_TOKEN }) });
  let status = 'IN_PROGRESS';
  let errorMessage = '';
  for (let attempt = 0; attempt < 10; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 3000));
    const result = await jsonRequest(`${base}/${made.id}?fields=status,error_message&access_token=${encodeURIComponent(process.env.THREADS_TOKEN)}`, { method: 'GET' });
    status = result.status;
    errorMessage = result.error_message || '';
    if (status === 'FINISHED') break;
    if (status === 'ERROR' || status === 'EXPIRED') {
      console.error(`Threads container ${status}: ${errorMessage || 'unknown error'}`);
      throw new Error(`Threads container ${status}`);
    }
  }
  if (status !== 'FINISHED') {
    console.error(`Threads container did not finish in time: ${errorMessage || 'unknown error'}`);
    throw new Error('Threads container did not finish in time');
  }
  await jsonRequest(`${base}/${user.id}/threads_publish`, { method: 'POST', body: new URLSearchParams({ creation_id: made.id, access_token: process.env.THREADS_TOKEN }) });
}
async function postInstagram(caption) {
  const base = 'https://graph.instagram.com/v22.0';
  const user = await resolveInstagramUser();
  const made = await jsonRequest(`${base}/${user.id}/media`, { method: 'POST', body: new URLSearchParams({ image_url: IMAGE_URL, caption, access_token: process.env.IG_TOKEN }) });
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
  await jsonRequest(`${base}/${user.id}/media_publish`, { method: 'POST', body: new URLSearchParams({ creation_id: made.id, access_token: process.env.IG_TOKEN }) });
}

async function postXToIssue(posts) {
  const headers = { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' };
  const base = `https://api.github.com/repos/${process.env.GITHUB_REPOSITORY}`;
  const issues = await jsonRequest(`${base}/issues?labels=x-post&state=open&per_page=1`, { headers });
  let issue = issues[0];
  if (!issue) {
    const payload = { title: 'X 投稿用の文面', labels: ['x-post'], body: '毎日の X 用の文面がコメントで届きます。リンクを押すと投稿画面が開くので、内容を確認して「ポスト」を押してください。' };
    try { issue = await jsonRequest(`${base}/issues`, { method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) }); }
    catch { delete payload.labels; issue = await jsonRequest(`${base}/issues`, { method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) }); }
  }
  for (const post of posts) {
    const link = `https://x.com/intent/post?text=${encodeURIComponent(post.x)}`;
    await jsonRequest(`${base}/issues/${issue.number}/comments`, { method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify({ body: `**X に投稿する** → ${link}\n\n\`\`\`\n${post.x}\n\`\`\`` }) });
  }
}

async function announce(name, dryRun) {
  if (!/^[A-Za-z0-9-]+$/.test(name)) throw new Error('ANNOUNCE は英数字とハイフンのみ指定できます');
  const source = readFileSync(new URL(`./announcements/${name}.txt`, import.meta.url), 'utf8');
  const post = {
    threads: source.replaceAll('{LINK}', SITE_URL),
    instagram: source.replaceAll('{LINK}', 'プロフィールのリンクからどうぞ'),
  };
  post.x = post.threads;
  let failures = 0;
  for (const [channel, configured, text, limit, send] of [['Threads', process.env.THREADS_TOKEN, post.threads, 500, postThreads], ['Instagram', process.env.IG_TOKEN, post.instagram, 2200, postInstagram]]) {
    if (text.length > limit) { failures += 1; console.error(`${channel}: ${limit}文字を超えています（${text.length}文字）`); continue; }
    if (dryRun) { console.log(`${channel}${configured ? '' : '（未設定・本番ではスキップ）'} 1 (${text.length}文字):\n${text}`); continue; }
    if (!configured) { console.log(`${channel}: スキップ（未設定）`); continue; }
    try { await send(text); }
    catch (error) { failures += 1; console.error(`${channel} 1: ${error.message}`); }
  }
  if (dryRun) {
    console.log(`X 1 (${xLength(post.x)} weighted chars):\n${post.x}\nhttps://x.com/intent/post?text=${encodeURIComponent(post.x)}`);
    if (xLength(post.x) > 280) console.log('X: 280 weighted charsを超えているため Issue コメントを作成しません');
  } else if (xLength(post.x) > 280) console.log(`X: 280 weighted charsを超えているため Issue コメントを作成しません（${xLength(post.x)} weighted chars）`);
  else if (process.env.GITHUB_TOKEN && process.env.GITHUB_REPOSITORY) {
    try { await postXToIssue([post]); }
    catch (error) { failures += 1; console.error(`X Issue: ${error.message}`); }
  }
  if (failures) process.exitCode = 1;
}

async function main() {
  const dryRun = process.argv.includes('--dry-run') || process.env.DRY_RUN === '1';
  const check = process.argv.includes('--check') || process.env.CHECK === '1';
  const reportOnly = process.env.REPORT === '1' || process.argv.includes('--report');
  const channels = [
    ['Threads', process.env.THREADS_TOKEN, fetchThreadsUser],
    ['Instagram', process.env.IG_TOKEN, fetchInstagramUser],
  ];
  if (check) {
    let failures = 0;
    for (const [channel, token, resolve] of channels) {
      if (!token) { console.log(`${channel}: スキップ（未設定）`); continue; }
      try {
        const user = await resolve();
        console.log(`${channel}: 接続OK（@${user.username || 'unknown'}）`);
      } catch (error) {
        failures += 1;
        console.log(`${channel}: 接続NG（${error.message}）`);
      }
    }
    if (failures) process.exitCode = 1;
    return;
  }
  if (process.env.ANNOUNCE) {
    await announce(process.env.ANNOUNCE, dryRun);
    return;
  }
  if ((process.env.GITHUB_EVENT_NAME === 'schedule' || process.env.AUTO_POST === '1') && !dryRun && !reportOnly && await alreadyPostedRecently()) {
    console.log('直近20時間以内に投稿済みのためスキップ');
    return;
  }
  let stats = null;
  if (process.env.THREADS_TOKEN) {
    try { stats = await fetchThreadsStats(process.env.THREADS_TOKEN, process.env.THREADS_USER_ID || (await resolveThreadsUser()).id); }
    catch (error) { console.log(`Threads 成績取得失敗: ${error.message}`); }
  } else if (reportOnly) { console.log('Threads 未設定のため成績なし'); return; }
  if (reportOnly) {
    if (!stats) { console.log('Threads 成績なし'); return; }
    const table = ['| テンプレート | 投稿数 | 平均表示 | 平均反応率 |', '|---|---:|---:|---:|', ...['A', 'B', 'C'].map((name) => { const s = stats[name]; const rate = s.views ? s.engagements / s.views : 0; return `| ${name} | ${s.posts} | ${(s.views / (s.posts || 1)).toFixed(1)} | ${(rate * 100).toFixed(2)}% |`; })].join('\n');
    if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${table}\n`); else console.log(table);
    return;
  }
  const params = new URLSearchParams({ select: 'id,title,venue,prefecture,starts_at,created_at,otaku_idol_groups(name)', publication_status: 'eq.published', is_demo: 'eq.false', starts_at: `gte.${new Date().toISOString()}`, order: 'starts_at.asc', limit: '1000' });
  const events = await jsonRequest(`${SUPABASE_URL}?${params}`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } });
  const template = process.env.THREADS_TOKEN ? chooseTemplate(stats) : ['A', 'B', 'C'][Number(jstParts(new Date()).day) % 3];
  console.log(`テンプレート: ${template}${dryRun && stats ? ` / 成績: ${JSON.stringify(stats)}` : ''}`);
  const posts = buildPosts(events, new Date(), template);
  let failures = 0;
  for (const [channel, configured, texts, send] of [['Threads', process.env.THREADS_TOKEN, posts.map((p) => p.threads), postThreads], ['Instagram', process.env.IG_TOKEN, posts.map((p) => p.instagram), postInstagram]]) {
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
  const xTexts = posts.map((post) => post.x);
  if (dryRun) xTexts.forEach((text, index) => console.log(`X ${index + 1} (${xLength(text)} weighted chars):\n${text}\nhttps://x.com/intent/post?text=${encodeURIComponent(text)}`));
  else if (process.env.GITHUB_TOKEN && process.env.GITHUB_REPOSITORY) {
    try { await postXToIssue(posts); }
    catch (error) { failures += 1; console.error(`X Issue: ${error.message}`); }
  }
  if (failures) process.exitCode = 1;
}

if (process.argv[1]?.endsWith('post.mjs')) main().catch((error) => { console.error(`投稿失敗: ${error.message}`); process.exitCode = 1; });
