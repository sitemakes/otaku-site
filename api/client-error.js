'use strict';

const MAX_BODY = 8 * 1024;
const trim = (value, max) => String(value || '').slice(0, max);

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.statusCode = 405;
    res.setHeader('allow', 'POST');
    res.end();
    return;
  }

  const origin = String(req.headers.origin || '');
  const referer = String(req.headers.referer || '');
  if (origin && origin !== 'https://otaku-live-mvp.vercel.app' && !referer.startsWith('https://otaku-live-mvp.vercel.app/')) {
    res.statusCode = 403;
    res.end();
    return;
  }

  const raw = typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {});
  if (raw.length > MAX_BODY) {
    res.statusCode = 413;
    res.end();
    return;
  }

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    res.statusCode = 400;
    res.end();
    return;
  }

  const event = {
    level: 'error',
    type: trim(payload.type, 32),
    message: trim(payload.message, 500),
    stack: trim(payload.stack, 2000),
    page: trim(payload.page, 300),
    timestamp: new Date().toISOString(),
    requestId: trim(req.headers['x-vercel-id'], 120),
  };
  console.error(JSON.stringify(event));
  res.statusCode = 204;
  res.end();
};
