const {test} = require('node:test');
const assert = require('node:assert/strict');
const c = require('../catalog.js');
test('admin controls do not shadow native form methods', () => {
  const html = require('node:fs').readFileSync(require('node:path').join(__dirname,'../admin.html'),'utf8');
  const form = html.match(/<form[\s\S]*?<\/form>/)[0];
  assert.doesNotMatch(form, /(?:id|name)="(?:reset|submit|requestSubmit|checkValidity|reportValidity)"/);
});
test('source links reject executable, credentialed and malformed URLs', () => {
  for (const url of ['javascript:alert(1)','http://example.com','https://user:pass@example.com/','https://example.com/"onclick="x','https://example.com\\evil','https://localhost/','https://example.com:443/']) assert.throws(() => c.sourceUrl(url));
  assert.equal(c.sourceUrl('https://example.com/news?id=1&lang=ja'),'https://example.com/news?id=1&lang=ja');
});
test('Japan date conversion is independent of browser timezone and rejects rollover', () => {
  assert.equal(c.jst('2026-10-01T18:00'),'2026-10-01T09:00:00.000Z');
  assert.equal(c.toJst('2026-10-01T09:00:00Z'),'2026-10-01T18:00');
  assert.throws(() => c.jst('2026-02-30T18:00'));
});
test('publication needs evidence, drafts do not', () => {
  const group = { name:' Real Group ',slug:'real-group',publication_status:'draft' };
  assert.equal(c.payload('groups',group).name,'Real Group');
  assert.throws(() => c.payload('groups',{...group,publication_status:'published'}));
  assert.equal(c.payload('groups',{...group,publication_status:'published',source_url:'https://example.com/',source_kind:'official',source_checked_at:'2026-01-01T00:00:00Z'}).publication_status,'published');
});
test('events require group, title, venue, valid chronological dates', () => {
  const event = {publication_status:'draft',group_id:'group',title:'Live',venue:'Venue',starts_at:'2026-10-01T18:00'};
  assert.ok(c.payload('events',event));
  assert.throws(() => c.payload('events',{...event,ends_at:'2026-10-01T17:00'}));
  assert.throws(() => c.payload('events',{...event,group_id:''}));
  assert.throws(() => c.payload('events',{...event,title:' '}));
});
