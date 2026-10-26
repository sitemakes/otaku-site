'use strict';

(async () => {
  const $ = id => document.getElementById(id);
  const pageSize = 30;
  const statusLabels = {
    pending: '確認待ち',
    approved: '承認済み',
    rejected: '見送り',
    hidden: '通報で非表示',
  };
  let filter = 'pending';
  let offset = 0;
  let loading = false;
  let reviewing = false;

  const { data: admin, error: adminError } = await otakuSupabase.rpc('otaku_is_catalog_admin');
  if (adminError || !admin) {
    $('message').textContent = '管理者アカウントでログインしてください。';
    return;
  }

  $('adminContent').hidden = false;

  function jstToday() {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Tokyo', year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(new Date());
    const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
    return `${values.year}-${values.month}-${values.day}`;
  }

  function formatDateTime(value) {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return value;
    return new Intl.DateTimeFormat('ja-JP', {
      timeZone: 'Asia/Tokyo', dateStyle: 'medium', timeStyle: 'short',
    }).format(date);
  }

  function setControlsDisabled(disabled) {
    $('filters').querySelectorAll('button').forEach(button => { button.disabled = disabled; });
    $('more').disabled = disabled;
  }

  async function reviewBanner(bannerId, decision, section) {
    if (reviewing) return;
    reviewing = true;
    section.querySelectorAll('button').forEach(button => { button.disabled = true; });
    const { error } = await otakuSupabase.rpc('otaku_review_support_banner', {
      banner_id: bannerId,
      decision,
    });
    reviewing = false;
    if (error) {
      section.querySelectorAll('button').forEach(button => { button.disabled = false; });
      $('message').textContent = '更新できませんでした。';
      return;
    }
    await load(true, '更新しました。');
  }

  function appendActionButtons(section, banner) {
    const decisions = banner.status === 'pending'
      ? [['approved', '承認'], ['rejected', '見送り']]
      : banner.status === 'approved'
        ? [['hidden', '非表示にする']]
        : banner.status === 'hidden'
          ? [['approved', '掲載に戻す（承認）'], ['rejected', '見送り']]
          : [];
    if (!decisions.length) return;
    const controls = document.createElement('div');
    controls.className = 'controls';
    for (const [decision, label] of decisions) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = label;
      button.addEventListener('click', () => reviewBanner(banner.id, decision, section));
      controls.append(button);
    }
    section.append(controls);
  }

  function renderBanner(banner, groupNames, idolNames, reportsByBanner, today) {
    const section = document.createElement('section');
    section.className = 'card support-banner-admin-item';
    section.append(otakuSupportBannerCard({
      group_name: groupNames.get(banner.group_id) || '（不明）',
      idol_name: banner.idol_id ? (idolNames.get(banner.idol_id) || '（不明）') : '',
      occasion: banner.occasion,
      show_on: banner.show_on,
      message: banner.message,
      display_name: banner.display_mode === 'profile' ? '表示名（公開設定による）' : '匿名のファン',
    }));

    const metadata = document.createElement('p');
    metadata.className = 'body support-banner-admin-meta';
    const lines = [
      `状態：${statusLabels[banner.status] || banner.status}`,
      `掲載日：${banner.show_on}`,
      `申請日時：${formatDateTime(banner.created_at)}`,
    ];
    if (banner.reviewed_at) lines.push(`審査日時：${formatDateTime(banner.reviewed_at)}`);
    metadata.textContent = lines.join('\n');
    section.append(metadata);

    if (banner.status === 'pending' && banner.show_on < today) {
      const expired = document.createElement('p');
      expired.className = 'support-banner-admin-warning';
      expired.textContent = '掲載日が過ぎています（承認しても表示されません）。';
      section.append(expired);
    }

    const reports = reportsByBanner.get(banner.id) || [];
    if (reports.length) {
      const reportBox = document.createElement('div');
      reportBox.className = 'support-banner-report';
      const heading = document.createElement('p');
      heading.textContent = `通報 ${reports.length}件`;
      const reasons = document.createElement('ul');
      for (const report of reports) {
        const item = document.createElement('li');
        item.textContent = report.reason;
        reasons.append(item);
      }
      reportBox.append(heading, reasons);
      section.append(reportBox);
    }

    appendActionButtons(section, banner);
    $('records').append(section);
  }

  async function load(reset = false, successMessage = '') {
    if (loading) return;
    loading = true;
    setControlsDisabled(true);
    if (reset) {
      offset = 0;
      $('records').replaceChildren();
      $('more').hidden = true;
    }
    $('message').textContent = successMessage || '取得中…';

    const today = jstToday();
    let query = otakuSupabase.from('otaku_support_banners')
      .select('id,group_id,idol_id,occasion,show_on,message,display_mode,status,reviewed_at,created_at');
    if (filter === 'pending') query = query.eq('status', 'pending').order('show_on', { ascending: true });
    if (filter === 'approved') query = query.eq('status', 'approved').gte('show_on', today);
    if (filter === 'hidden') query = query.eq('status', 'hidden');
    query = filter === 'pending'
      ? query.order('id', { ascending: true })
      : query.order('created_at', { ascending: false }).order('id', { ascending: true });
    const { data: banners, error: bannerError } = await query.range(offset, offset + pageSize - 1);
    if (bannerError) {
      $('message').textContent = '取得できませんでした。';
      loading = false;
      setControlsDisabled(false);
      return;
    }

    const bannerIds = banners.map(banner => banner.id);
    const groupIds = [...new Set(banners.map(banner => banner.group_id))];
    const idolIds = [...new Set(banners.map(banner => banner.idol_id).filter(Boolean))];
    const reportsRequest = bannerIds.length
      ? otakuSupabase.from('otaku_support_banner_reports').select('banner_id,reason').in('banner_id', bannerIds)
      : Promise.resolve({ data: [], error: null });
    const groupsRequest = groupIds.length
      ? otakuSupabase.from('otaku_idol_groups').select('id,name').in('id', groupIds)
      : Promise.resolve({ data: [], error: null });
    const idolsRequest = idolIds.length
      ? otakuSupabase.from('otaku_idols').select('id,name').in('id', idolIds)
      : Promise.resolve({ data: [], error: null });
    const [reportsResult, groupsResult, idolsResult] = await Promise.all([
      reportsRequest, groupsRequest, idolsRequest,
    ]);
    if (reportsResult.error) {
      $('message').textContent = '取得できませんでした。';
      loading = false;
      setControlsDisabled(false);
      return;
    }

    const groupNames = new Map((groupsResult.data || []).map(group => [group.id, group.name]));
    const idolNames = new Map((idolsResult.data || []).map(idol => [idol.id, idol.name]));
    const reportsByBanner = new Map();
    for (const report of reportsResult.data || []) {
      const reports = reportsByBanner.get(report.banner_id) || [];
      reports.push(report);
      reportsByBanner.set(report.banner_id, reports);
    }
    for (const banner of banners) renderBanner(banner, groupNames, idolNames, reportsByBanner, today);

    offset += banners.length;
    $('more').hidden = banners.length < pageSize;
    if (!successMessage) {
      $('message').textContent = offset ? `${offset}件を表示しています。` : '該当する応援バナーはありません。';
    }
    loading = false;
    setControlsDisabled(false);
  }

  $('filters').addEventListener('click', event => {
    const button = event.target.closest('button[data-filter]');
    if (!button || loading || button.dataset.filter === filter) return;
    filter = button.dataset.filter;
    $('filters').querySelectorAll('button').forEach(item => {
      item.setAttribute('aria-pressed', String(item === button));
    });
    load(true);
  });
  $('more').addEventListener('click', () => load());
  await load(true);
})();
