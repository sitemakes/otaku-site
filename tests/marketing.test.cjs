const test = require('node:test');
const assert = require('node:assert/strict');
let buildPosts;
let detectTemplate;
let chooseTemplate;
let xLength;
test.before(async () => ({ buildPosts, detectTemplate, chooseTemplate, xLength } = await import('../scripts/marketing/post.mjs')));
test('X weighted length', () => { assert.equal(xLength('日本語'), 6); assert.equal(xLength('abc123'), 6); assert.equal(xLength('https://example.com'), 23); });
const event = (n, start, created = '2026-10-10T00:00:00Z', group = '星空') => ({ title: `公演${n}`, venue: '渋谷会場', prefecture: '東京都', starts_at: start, created_at: created, otaku_idol_groups: { name: group } });
test('新着は5件と残りを表示', () => { const posts = buildPosts(Array.from({ length: 6 }, (_, i) => event(i, `2026-10-20T10:00:00Z`, '2026-10-11T01:00:00Z')), new Date('2026-10-11T10:00:00Z')); assert.match(posts[0].threads, /ほか1件/); });
test('新着なしは明日', () => { const posts = buildPosts([event(1, '2026-10-12T10:00:00Z')], new Date('2026-10-11T10:00:00Z')); assert.match(posts[0].threads, /明日の公演/); });
test('対象なしは0件', () => assert.equal(buildPosts([], new Date('2026-10-11T10:00:00Z')).length, 0));
test('月曜は最大2件で今週を追加', () => { const posts = buildPosts([event(1, '2026-10-13T10:00:00Z'), event(2, '2026-10-14T10:00:00Z')], new Date('2026-10-12T00:00:00Z')); assert.equal(posts.length, 2); assert.match(posts[1].threads, /今週の公演/); });
test('文字数とInstagram URL', () => { const posts = buildPosts([event(1, '2026-10-12T10:00:00Z')], new Date('2026-10-11T10:00:00Z')); assert.ok(posts.every((p) => p.threads.length <= 500 && p.instagram.length <= 2200)); assert.doesNotMatch(posts[0].instagram, /otaku-live-mvp\.vercel\.app/); });
test('JSTの日付境界', () => { const posts = buildPosts([event(1, '2026-10-12T00:30:00Z', '2026-10-01T00:00:00Z')], new Date('2026-10-10T15:30:00Z')); assert.match(posts[0].threads, /明日の公演/); assert.match(posts[0].threads, /10\/12/); });
test('テンプレートを判定する', () => { assert.equal(detectTemplate('🆕 新着公演を追加しました\n本文'), 'A'); assert.equal(detectTemplate('🆕 新着公演\n本文'), 'B'); for (const line of ['今週末の現場、一緒に行く人いますか？👀', '次の現場、もう決めた？🎤', '一人参戦が不安なら、同行募集を使ってみて🤝', '推しの公演、見逃してない？👀', '現場の予定、ここでまとめてチェック✅']) assert.equal(detectTemplate(line), 'C'); assert.equal(detectTemplate('不明'), null); });
test('テンプレート選択は未使用を優先する', () => { assert.equal(chooseTemplate({ A: { posts: 3 }, B: { posts: 3 }, C: { posts: 3 } }, () => 0.9), 'D'); assert.equal(chooseTemplate({ A: { posts: 3, views: 10, engagements: 1 }, B: { posts: 3, views: 10, engagements: 5 }, C: { posts: 3, views: 10, engagements: 0 }, D: { posts: 3 }, E: { posts: 3 }, F: { posts: 3 }, G: { posts: 3 } }, () => 0.9), 'B'); assert.equal(chooseTemplate(null, () => 0), 'A'); });
test('各テンプレートは上限内でグループ名を重ねない', () => { for (const template of ['A', 'B', 'C']) { const posts = buildPosts([event(1, '2026-10-12T10:00:00Z', '2026-10-01T00:00:00Z', '星空')], new Date('2026-10-11T10:00:00Z'), template); assert.ok(posts.every((p) => p.threads.length <= 500 && p.instagram.length <= 2200)); assert.doesNotMatch(posts[0].threads, /星空 星空/); } });
test('X posts fit weighted limit for every template', () => { for (const template of ['A', 'B', 'C']) { const posts = buildPosts(Array.from({ length: 10 }, (_, i) => event(i, '2026-10-12T10:00:00Z', '2026-10-01T00:00:00Z')), new Date('2026-10-11T10:00:00Z'), template); assert.ok(posts.every((p) => xLength(p.x) <= 280)); } });

test('D 大型公演のカウントダウン', () => {
  const target = { ...event(1, '2026-10-14T09:00:00Z', '2026-10-01T00:00:00Z', '星空'), venue: '東京ドーム', title: '記念公演' };
  const post = buildPosts([target], new Date('2026-10-11T10:00:00Z'), 'D')[0];
  assert.match(post.threads, /^⏳ 東京ドームまであと3日！/);
  assert.equal(detectTemplate(post.threads), 'D');
  assert.ok(post.threads.length <= 500 && post.instagram.length <= 2200 && xLength(post.x) <= 280);
});

test('E 地域別の今週末', () => {
  const events = [event(1, '2026-10-17T09:00:00Z', '2026-10-01T00:00:00Z'), event(2, '2026-10-17T12:00:00Z', '2026-10-01T00:00:00Z'), event(3, '2026-10-18T09:00:00Z', '2026-10-01T00:00:00Z'), { ...event(4, '2026-10-17T10:00:00Z', '2026-10-01T00:00:00Z'), prefecture: '大阪府' }, { ...event(5, '2026-10-18T10:00:00Z', '2026-10-01T00:00:00Z'), prefecture: '大阪府' }];
  const post = buildPosts(events, new Date('2026-10-14T03:00:00Z'), 'E')[0];
  assert.match(post.threads, /^📍 今週末の東京都の現場/);
  assert.match(post.threads, /・星空 10\/17\(土\) 渋谷会場（2公演）/);
  assert.equal((post.threads.match(/10\/17\(土\) 渋谷会場/g) || []).length, 1);
  assert.equal(detectTemplate(post.threads), 'E');
  assert.ok(post.threads.length <= 500 && post.instagram.length <= 2200 && xLength(post.x) <= 280);
});

test('F 質問型', () => {
  const post = buildPosts([event(1, '2026-10-17T09:00:00Z', '2026-10-01T00:00:00Z', '星空'), event(2, '2026-10-17T12:00:00Z', '2026-10-01T00:00:00Z', '星空'), event(3, '2026-10-18T09:00:00Z', '2026-10-01T00:00:00Z', '月影')], new Date('2026-10-14T03:00:00Z'), 'F')[0];
  assert.match(post.threads, /^🙋 今週末どの現場に行く？/);
  assert.match(post.threads, /星空、月影など/);
  assert.doesNotMatch(post.threads, /星空、星空/);
  assert.equal(detectTemplate(post.threads), 'F');
  assert.ok(post.threads.length <= 500 && post.instagram.length <= 2200 && xLength(post.x) <= 280);
});

test('G 新グループのお知らせ', () => {
  const groups = [{ name: '新星', created_at: '2026-10-12T00:00:00Z' }, { name: '流星', created_at: '2026-10-10T00:00:00Z' }];
  const post = buildPosts([], new Date('2026-10-14T03:00:00Z'), 'G', groups)[0];
  assert.match(post.threads, /^🎉 新しく掲載したグループ/);
  assert.equal(detectTemplate(post.threads), 'G');
  assert.ok(post.threads.length <= 500 && post.instagram.length <= 2200 && xLength(post.x) <= 280);
});

test('D〜G は該当なしなら A にフォールバック', () => {
  const fallbackEvent = event(1, '2026-10-15T09:00:00Z', '2026-10-01T00:00:00Z');
  for (const template of ['D', 'E', 'F', 'G']) {
    const post = buildPosts([fallbackEvent], new Date('2026-10-14T03:00:00Z'), template, [])[0];
    assert.match(post.threads, /^📅 明日の公演/);
    assert.equal(detectTemplate(post.threads), 'A');
  }
});
