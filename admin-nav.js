'use strict';
// Shared header and section tabs for the admin pages. Each page still checks admin rights itself.
(() => {
  const tabs = [
    ['admin.html', '公演・グループ'],
    ['venue-admin.html', '会場ガイド'],
    ['reports.html', '通報'],
    ['content-admin.html', '掲示板・評価の通報'],
    ['review-admin.html', '同行評価'],
  ];
  const page = location.pathname.split('/').pop();
  const main = document.querySelector('main');
  if (!main) return;
  // Drop each page's own header / back link; the tabs replace them.
  main.querySelector(':scope > header')?.remove();
  const firstLink = main.firstElementChild;
  if (firstLink?.tagName === 'A' && firstLink.getAttribute('href') === 'admin.html') firstLink.remove();

  const header = document.createElement('header');
  header.className = 'admin-header';
  header.innerHTML = '<a class="brand" href="index.html">OTAKU LIVE</a><span class="admin-label">管理</span><a class="admin-exit" href="profile.html">マイページへ</a>';
  const nav = document.createElement('nav');
  nav.className = 'admin-nav';
  nav.setAttribute('aria-label', '管理メニュー');
  nav.innerHTML = tabs.map(([href, label]) =>
    `<a href="${href}"${href === page ? ' aria-current="page"' : ''}>${label}</a>`).join('');
  main.prepend(header, nav);
  document.body.classList.add('admin-page');
})();
