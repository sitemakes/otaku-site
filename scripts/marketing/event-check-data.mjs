import { mkdir, writeFile } from 'node:fs/promises';

const SUPABASE_URL = 'https://pfyvsweuvdnpmvabfflh.supabase.co';
const SUPABASE_KEY = 'sb_publishable_FJ9hNx9T4-sNV6Ypv94vJA_cCq5TxUp';
const PAGE_SIZE = 1000;
const now = new Date();

async function fetchRows(table, params) {
  const rows = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const url = new URL(`${SUPABASE_URL}/rest/v1/${table}`);
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
    url.searchParams.set('limit', String(PAGE_SIZE));
    url.searchParams.set('offset', String(offset));

    const response = await fetch(url, {
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
      },
    });
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 300);
      throw new Error(`Supabase ${table} request failed: HTTP ${response.status}${detail ? ` ${detail}` : ''}`);
    }

    const page = await response.json();
    rows.push(...page);
    if (page.length < PAGE_SIZE) return rows;
  }
}

function jstDateParts(date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  return Object.fromEntries(parts.map(({ type, value }) => [type, value]));
}

function dayOfYearInJst(date) {
  const { year, month, day } = jstDateParts(date);
  const current = Date.UTC(Number(year), Number(month) - 1, Number(day));
  const first = Date.UTC(Number(year), 0, 1);
  return Math.floor((current - first) / 86400000) + 1;
}

function formatJst(dateString) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date(dateString));
  const values = Object.fromEntries(parts.map(({ type, value }) => [type, value]));
  return `${values.year}-${values.month}-${values.day} ${values.hour}:${values.minute}`;
}

async function writeJson(path, value) {
  await mkdir('report', { recursive: true });
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

async function main() {
  const groups = await fetchRows('otaku_idol_groups', {
    select: 'id,name,slug,source_url',
    publication_status: 'eq.published',
    is_demo: 'eq.false',
    order: 'slug.asc',
  });
  groups.sort((a, b) => a.slug.localeCompare(b.slug, 'en'));

  if (process.env.MODE === 'groups') {
    await writeJson('report/registered-groups.json', groups.map(({ name, slug }) => ({ name, slug })));
    return;
  }

  const requestedSlugs = String(process.env.GROUP_SLUGS || '')
    .split(',')
    .map((slug) => slug.trim())
    .filter(Boolean);
  const requested = new Set(requestedSlugs);
  const bucket = dayOfYearInJst(now) % 7;
  const targets = requested.size
    ? groups.filter(({ slug }) => requested.has(slug))
    : groups.filter((_, index) => index % 7 === bucket);

  const events = await fetchRows('otaku_events', {
    select: 'group_id,title,venue,starts_at',
    publication_status: 'eq.published',
    is_demo: 'eq.false',
    starts_at: `gte.${now.toISOString()}`,
    order: 'starts_at.asc',
  });
  const eventsByGroup = new Map();
  for (const event of events) {
    if (!eventsByGroup.has(event.group_id)) eventsByGroup.set(event.group_id, []);
    eventsByGroup.get(event.group_id).push({
      title: event.title,
      venue: event.venue,
      starts_at: formatJst(event.starts_at),
    });
  }

  const report = targets.map(({ id, name, slug, source_url }) => ({
    name,
    slug,
    source_url,
    registered_events: eventsByGroup.get(id) || [],
  }));
  await writeJson('report/event-check.json', report);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
