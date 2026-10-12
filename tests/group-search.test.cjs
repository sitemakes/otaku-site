const {test} = require('node:test');
const assert = require('node:assert/strict');
const {normalizeForSearch, groupMatches, rankGroups} = require('../group-search.js');

const groups = [
  {id:'equal-love', name:'＝LOVE', search_aliases:'いこらぶ イコールラブ equal-love'},
  {id:'morning-musume', name:"モーニング娘。'26", search_aliases:'もーむす モー娘。'},
  {id:'other', name:'別のグループ', search_aliases:'べつ'}
];

test('normalization ignores width, case, script, long vowels, spaces and symbols', () => {
  assert.equal(normalizeForSearch(' ＝ＬＯＶＥ！ '), 'love');
  assert.equal(normalizeForSearch('モーニング・ムスメ'), 'もにんぐむすめ');
});

test('group aliases and names match partial normalized queries', () => {
  const equalLove = groups[0];
  for (const query of ['いこらぶ','イコールラブ','equal love','＝ＬＯＶＥ']) assert.equal(groupMatches(equalLove, query), true, query);
  assert.equal(groupMatches(groups[1], 'もーむす'), true);
  assert.equal(groups.every(group => groupMatches(group, '')), true);
  assert.equal(groups.some(group => groupMatches(group, '無関係な語')), false);
});

test('prefix matches rank before partial matches and ties use name order', () => {
  const ranked = rankGroups([
    {id:'partial',name:'B',search_aliases:'まいあいどる'},
    {id:'prefix-b',name:'Bグループ',search_aliases:'あいどるびー'},
    {id:'prefix-a',name:'Aグループ',search_aliases:'あいどるえー'}
  ], 'あいどる');
  assert.deepEqual(ranked.map(group => group.id), ['prefix-a','prefix-b','partial']);
});
