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
test('JST day ranges are independent of browser timezone', () => {
  assert.deepEqual(c.jstDayRange('2026-10-24T08:00:00.000Z'), {from:'2026-10-23T15:00:00.000Z',to:'2026-10-24T15:00:00.000Z'});
  assert.notDeepEqual(c.jstDayRange('2026-10-24T14:30:00.000Z'), c.jstDayRange('2026-10-24T15:30:00.000Z'));
});
test('duplicate events match JST day and annotate proximity and venue', () => {
  const candidate = {id:'current',group_id:'g',is_demo:false,starts_at:'2026-10-24T08:00:00.000Z',venue:'ゼビオアリーナ仙台'};
  const existing = [
    {id:'late',group_id:'g',is_demo:false,starts_at:'2026-10-24T09:01:00.000Z',venue:'abc hall',title:'Late',publication_status:'draft'},
    {id:'near',group_id:'g',is_demo:false,starts_at:'2026-10-24T08:30:00.000Z',venue:'ゼビオアリーナ　仙台',title:'Near',publication_status:'published'},
    {id:'current',group_id:'g',is_demo:false,starts_at:'2026-10-24T08:00:00.000Z',venue:'x',title:'Self',publication_status:'draft'},
    {id:'next',group_id:'g',is_demo:false,starts_at:'2026-10-24T15:30:00.000Z',venue:'x',title:'Next',publication_status:'draft'},
    {id:'demo',group_id:'g',is_demo:true,starts_at:'2026-10-24T08:00:00.000Z',venue:'x',title:'Demo',publication_status:'draft'},
    {id:'other',group_id:'other',is_demo:false,starts_at:'2026-10-24T08:00:00.000Z',venue:'x',title:'Other',publication_status:'draft'}
  ];
  const result = c.duplicateEvents(candidate, existing);
  assert.deepEqual(result.map(row => row.id), ['near','late']);
  assert.equal(result[0].nearTime, true); assert.equal(result[0].sameVenue, true);
  assert.equal(result[1].nearTime, false); assert.equal(result[1].sameVenue, false);
  assert.equal(c.normalizeVenue('ＡＢＣ Hall'), c.normalizeVenue('abc hall'));
  assert.deepEqual(existing[0], {id:'late',group_id:'g',is_demo:false,starts_at:'2026-10-24T09:01:00.000Z',venue:'abc hall',title:'Late',publication_status:'draft'});
  assert.equal(c.duplicateEvents({id:'x',group_id:'g',is_demo:false,starts_at:'2026-10-24T14:30:00.000Z',venue:'x'}, [{id:'y',group_id:'g',is_demo:false,starts_at:'2026-10-24T14:59:00.000Z',venue:'x',title:'x',publication_status:'draft'}])[0].nearTime, true);
});
test('duplicate events compare equivalent UTC timestamp formats numerically', () => {
  const candidate = {id:'current',group_id:'g',is_demo:false,starts_at:'2026-10-24T08:00:00.000Z',venue:'x'};
  const existing = [
    {id:'start',group_id:'g',is_demo:false,starts_at:'2026-10-23T15:00:00+00:00',venue:'x',title:'Start',publication_status:'draft'},
    {id:'same',group_id:'g',is_demo:false,starts_at:'2026-10-24T08:00:00+00:00',venue:'x',title:'Same',publication_status:'draft'},
    {id:'next',group_id:'g',is_demo:false,starts_at:'2026-10-24T15:00:00+00:00',venue:'x',title:'Next',publication_status:'draft'}
  ];
  const result = c.duplicateEvents(candidate, existing);
  assert.deepEqual(result.map(row => row.id), ['start','same']);
  assert.equal(result[1].nearTime, true);
});
