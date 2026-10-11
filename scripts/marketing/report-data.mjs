import { mkdir, writeFile } from 'node:fs/promises';
import { detectTemplate } from './post.mjs';

const SUPABASE_URL = 'https://pfyvsweuvdnpmvabfflh.supabase.co';
const SUPABASE_KEY = 'sb_publishable_FJ9hNx9T4-sNV6Ypv94vJA_cCq5TxUp';
const THREADS_API = 'https://graph.threads.net/v1.0';
const INSTAGRAM_API = 'https://graph.instagram.com/v22.0';
const DAY_MS = 86400000;
const now = new Date();
const currentStart = new Date(now.getTime() - 7 * DAY_MS);
const previousStart = new Date(now.getTime() - 14 * DAY_MS);
const secrets = [process.env.REPORT_KEY, process.env.THREADS_TOKEN, process.env.IG_TOKEN].filter(Boolean);

function errorMessage(error) {
  let message = error instanceof Error ? error.message : String(error);
  for (const secret of secrets) message = message.replaceAll(secret, '[redacted]');
  return message;
}

async function jsonRequest(url, options = {}) {
  const response = await fetch(url, options);
  if (!response.ok) {
    let detail = '';
    try {
      const body = await response.json();
      detail = body?.error?.message || body?.message || '';
    } catch {}
    throw new Error(`HTTP ${response.status}${detail ? `: ${detail}` : ''}`);
  }
  return response.json();
}

function insightValue(item) {
  const value = item?.values?.[0]?.value ?? item?.total_value?.value ?? item?.value;
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function firstLine(text) {
  return String(text || '').split(/\r?\n/, 1)[0];
}

function inPeriod(date, start, end) {
  const time = new Date(date).getTime();
  return time >= start.getTime() && time < end.getTime();
}

function sumPosts(posts, metricNames, start, end) {
  const selected = posts.filter((post) => inPeriod(post.date, start, end));
  const totals = { posts: selected.length };
  for (const metric of metricNames) {
    const values = selected.map((post) => post[metric]).filter(Number.isFinite);
    if (values.length) totals[metric] = values.reduce((sum, value) => sum + value, 0);
  }
  return totals;
}

function addEngagementRate(totals, engagementMetrics, exposureMetrics) {
  const exposureName = exposureMetrics.find((metric) => Number.isFinite(totals[metric]) && totals[metric] > 0);
  const engagementValues = engagementMetrics.map((metric) => totals[metric]).filter(Number.isFinite);
  if (!exposureName || !engagementValues.length) return totals;
  totals.engagements = engagementValues.reduce((sum, value) => sum + value, 0);
  totals.engagement_rate = totals.engagements / totals[exposureName];
  totals.engagement_rate_base = exposureName;
  return totals;
}

function periodTotals(posts, metricNames, engagementMetrics, exposureMetrics) {
  return {
    current: addEngagementRate(sumPosts(posts, metricNames, currentStart, now), engagementMetrics, exposureMetrics),
    previous: addEngagementRate(sumPosts(posts, metricNames, previousStart, currentStart), engagementMetrics, exposureMetrics),
  };
}

async function fetchRecentMedia(url, token) {
  const posts = [];
  let next = url;
  for (let page = 0; next && page < 20; page += 1) {
    const pageUrl = new URL(next);
    if (!pageUrl.searchParams.has('access_token')) pageUrl.searchParams.set('access_token', token);
    const result = await jsonRequest(pageUrl);
    const data = result.data || [];
    posts.push(...data);
    if (data.some((post) => new Date(post.timestamp) < previousStart)) break;
    next = result.paging?.next || null;
  }
  return posts.filter((post) => inPeriod(post.timestamp, previousStart, now));
}

async function collectSite() {
  if (!process.env.REPORT_KEY) return { error: 'REPORT_KEY is not configured' };
  try {
    return await jsonRequest(`${SUPABASE_URL}/rest/v1/rpc/otaku_growth_stats`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ report_key: process.env.REPORT_KEY, days: 7 }),
    });
  } catch (error) {
    return { error: errorMessage(error) };
  }
}

async function collectThreads() {
  const token = process.env.THREADS_TOKEN;
  if (!token) return { error: 'THREADS_TOKEN is not configured' };
  const metrics = ['views', 'likes', 'replies', 'reposts', 'quotes'];
  try {
    const listUrl = new URL(`${THREADS_API}/me/threads`);
    listUrl.searchParams.set('fields', 'id,text,timestamp,permalink');
    listUrl.searchParams.set('limit', '100');
    const media = await fetchRecentMedia(listUrl, token);
    const posts = [];
    for (const item of media) {
      const post = {
        date: item.timestamp,
        template: detectTemplate(item.text),
        first_line: firstLine(item.text),
        permalink: item.permalink,
      };
      try {
        const url = new URL(`${THREADS_API}/${encodeURIComponent(item.id)}/insights`);
        url.searchParams.set('metric', metrics.join(','));
        url.searchParams.set('access_token', token);
        const result = await jsonRequest(url);
        const values = Object.fromEntries((result.data || []).map((metric) => [metric.name, insightValue(metric)]));
        for (const metric of metrics) post[metric] = values[metric] ?? 0;
      } catch (error) {
        for (const metric of metrics) post[metric] = null;
        post.error = errorMessage(error);
      }
      posts.push(post);
    }
    return {
      posts,
      totals: periodTotals(posts, metrics, ['likes', 'replies', 'reposts', 'quotes'], ['views']),
    };
  } catch (error) {
    return { error: errorMessage(error) };
  }
}

async function collectInstagram() {
  const token = process.env.IG_TOKEN;
  if (!token) return { error: 'IG_TOKEN is not configured' };
  const metrics = ['views', 'reach', 'likes', 'comments', 'saved', 'shares'];
  try {
    const listUrl = new URL(`${INSTAGRAM_API}/me/media`);
    listUrl.searchParams.set('fields', 'id,caption,timestamp,permalink');
    listUrl.searchParams.set('limit', '100');
    const media = await fetchRecentMedia(listUrl, token);
    const posts = [];
    for (const item of media) {
      const post = {
        date: item.timestamp,
        template: detectTemplate(item.caption),
        first_line: firstLine(item.caption),
        permalink: item.permalink,
      };
      const failures = [];
      for (const metric of metrics) {
        try {
          const url = new URL(`${INSTAGRAM_API}/${encodeURIComponent(item.id)}/insights`);
          url.searchParams.set('metric', metric);
          url.searchParams.set('access_token', token);
          const result = await jsonRequest(url);
          const value = insightValue((result.data || [])[0]);
          if (value !== undefined) post[metric] = value;
        } catch (error) {
          failures.push(errorMessage(error));
        }
      }
      if (failures.length === metrics.length) post.error = failures[0] || 'Insights are unavailable';
      posts.push(post);
    }
    return {
      posts,
      totals: periodTotals(posts, metrics, ['likes', 'comments', 'saved', 'shares'], ['views', 'reach']),
    };
  } catch (error) {
    return { error: errorMessage(error) };
  }
}

async function main() {
  const [site, threads, instagram] = await Promise.all([
    collectSite(),
    collectThreads(),
    collectInstagram(),
  ]);
  const report = {
    generated_at: now.toISOString(),
    period: {
      days: 7,
      current: { start: currentStart.toISOString(), end: now.toISOString() },
      previous: { start: previousStart.toISOString(), end: currentStart.toISOString() },
    },
    site,
    threads,
    instagram,
  };
  await mkdir('report', { recursive: true });
  await writeFile('report/report.json', `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}

main().catch(async (error) => {
  const report = {
    generated_at: now.toISOString(),
    period: { days: 7 },
    site: { error: 'Collection did not complete' },
    threads: { error: 'Collection did not complete' },
    instagram: { error: 'Collection did not complete' },
    error: errorMessage(error),
  };
  await mkdir('report', { recursive: true });
  await writeFile('report/report.json', `${JSON.stringify(report, null, 2)}\n`, 'utf8');
});
