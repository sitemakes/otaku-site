/* Shared, dependency-free group search helpers. */
(function (root) {
  'use strict';

  function normalizeForSearch(text) {
    return String(text || '')
      .normalize('NFKC')
      .toLowerCase()
      .replace(/[\u30a1-\u30f6]/g, character => String.fromCharCode(character.charCodeAt(0) - 0x60))
      .replace(/ー/g, '')
      .replace(/[^\p{L}\p{N}]/gu, '');
  }

  function searchTerms(group) {
    return [group?.name, ...String(group?.search_aliases || '').split(/\s+/)]
      .map(normalizeForSearch)
      .filter(Boolean);
  }

  function groupMatches(group, query) {
    const normalizedQuery = normalizeForSearch(query);
    return !normalizedQuery || searchTerms(group).some(term => term.includes(normalizedQuery));
  }

  function rankGroups(groups, query) {
    const normalizedQuery = normalizeForSearch(query);
    return (groups || [])
      .map((group, index) => {
        const terms = searchTerms(group);
        const rank = !normalizedQuery || terms.some(term => term.startsWith(normalizedQuery)) ? 0 : 1;
        return { group, index, rank };
      })
      .filter(row => !normalizedQuery || row.rank === 0 || searchTerms(row.group).some(term => term.includes(normalizedQuery)))
      .sort((a, b) => a.rank - b.rank || String(a.group.name || '').localeCompare(String(b.group.name || ''), 'ja') || a.index - b.index)
      .map(row => row.group);
  }

  root.normalizeForSearch = normalizeForSearch;
  root.groupMatches = groupMatches;
  root.rankGroups = rankGroups;
  if (typeof module !== 'undefined') module.exports = { normalizeForSearch, groupMatches, rankGroups };
})(typeof globalThis !== 'undefined' ? globalThis : window);
