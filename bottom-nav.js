'use strict';
// Shared bottom navigation for the main sections. Marks the current page as active.
(() => {
  const icon = d => `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const items = [
    ['index.html', 'ホーム', '<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>'],
    ['goods.html', 'グッズ', '<path d="M7 7h13l-4-4"/><path d="M17 17H4l4 4"/>'],
    ['boards.html', '掲示板', '<path d="M4 5h16v11H9l-5 4z"/>'],
    ['dm.html', 'DM', '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/>'],
    ['profile.html', 'マイページ', '<circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6"/>'],
  ];
  const page = location.pathname.split('/').pop() || 'index.html';
  const nav = document.createElement('nav');
  nav.className = 'bottom-nav';
  nav.setAttribute('aria-label', 'メインメニュー');
  nav.innerHTML = `<div class="bottom-nav-inner">${items.map(([href, label, d]) =>
    `<a href="${href}"${href === page ? ' aria-current="page"' : ''}>${icon(d)}${label}</a>`).join('')}</div>`;
  document.body.append(nav);
  document.body.classList.add('has-bottom-nav');
})();
