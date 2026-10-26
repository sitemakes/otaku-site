'use strict';

(() => {
  const loading = document.getElementById('loading');
  const signedOut = document.getElementById('signedOut');
  const signedIn = document.getElementById('signedIn');
  const loginLink = document.getElementById('loginLink');
  const eligibilityCounts = document.getElementById('eligibilityCounts');
  const eligibilityReason = document.getElementById('eligibilityReason');
  const bannerForm = document.getElementById('bannerForm');
  const bannerFields = document.getElementById('bannerFields');
  const groupSelect = document.getElementById('groupSelect');
  const idolSelect = document.getElementById('idolSelect');
  const occasionSelect = document.getElementById('occasionSelect');
  const showOn = document.getElementById('showOn');
  const bannerMessage = document.getElementById('bannerMessage');
  const messageCount = document.getElementById('messageCount');
  const submitButton = document.getElementById('submitButton');
  const submitStatus = document.getElementById('submitStatus');
  const preview = document.getElementById('preview');
  const applicationList = document.getElementById('applicationList');

  let groups = [];
  let currentIdols = [];
  let currentUserId = null;
  let eligible = false;
  let submitted = false;

  const jstToday = () => new Date(Date.now() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const addDays = (date, days) => {
    const value = new Date(`${date}T00:00:00Z`);
    value.setUTCDate(value.getUTCDate() + days);
    return value.toISOString().slice(0, 10);
  };
  const formatDate = date => {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date || '');
    return match ? `${Number(match[1])}年${Number(match[2])}月${Number(match[3])}日` : '';
  };
  const addOption = (select, value, label) => {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    select.append(option);
  };

  function renderPreview() {
    const group = groups.find(item => item.id === groupSelect.value);
    const idol = currentIdols.find(item => item.id === idolSelect.value);
    const displayMode = bannerForm.elements.displayMode.value;
    const card = otakuSupportBannerCard({
      group_name: group?.name || 'グループを選択',
      idol_name: idol?.name || '',
      occasion: occasionSelect.value,
      show_on: showOn.value,
      message: bannerMessage.value,
      display_name: displayMode === 'profile' ? 'あなたの表示名' : '匿名のファン',
    });
    preview.replaceChildren(card);
  }

  async function loadGroups() {
    groupSelect.replaceChildren();
    addOption(groupSelect, '', 'グループを選択');
    const { data, error } = await otakuSupabase
      .from('otaku_idol_groups')
      .select('id,name')
      .eq('publication_status', 'published')
      .eq('is_demo', false)
      .order('name', { ascending: true });
    if (error) {
      submitStatus.textContent = 'グループ情報を取得できませんでした。';
      return false;
    }
    groups = data || [];
    groups.forEach(group => addOption(groupSelect, group.id, group.name));
    return true;
  }

  async function loadIdols() {
    const selectedGroup = groupSelect.value;
    currentIdols = [];
    idolSelect.replaceChildren();
    addOption(idolSelect, '', 'グループ全体');
    if (!selectedGroup) {
      idolSelect.disabled = true;
      renderPreview();
      return;
    }
    idolSelect.disabled = true;
    const { data, error } = await otakuSupabase
      .from('otaku_idols')
      .select('id,name,group_id')
      .eq('group_id', selectedGroup)
      .eq('publication_status', 'published')
      .eq('is_demo', false)
      .order('name', { ascending: true });
    if (groupSelect.value !== selectedGroup) return;
    if (error) {
      submitStatus.textContent = 'メンバー情報を取得できませんでした。';
      renderPreview();
      return;
    }
    currentIdols = data || [];
    currentIdols.forEach(idol => addOption(idolSelect, idol.id, idol.name));
    idolSelect.disabled = !eligible || submitted;
    renderPreview();
  }

  async function loadEligibility() {
    const { data, error } = await otakuSupabase.rpc('otaku_support_banner_eligibility');
    if (error) {
      eligibilityCounts.textContent = '申請条件を確認できませんでした。';
      eligibilityReason.textContent = '時間をおいてもう一度お試しください。';
      eligible = false;
      return;
    }
    const result = Array.isArray(data) ? data[0] : data;
    const attendanceCount = Number(result?.attendance_count || 0);
    const recordCount = Number(result?.record_count || 0);
    eligibilityCounts.textContent = `過去60日の参戦予定：${attendanceCount}公演 · 公演後の記録：${recordCount}件`;
    eligible = result?.eligible === true;
    if (eligible) {
      eligibilityReason.textContent = '今は申請できます。';
    } else if (result?.has_active) {
      eligibilityReason.textContent = '申請中または掲載予定の応援バナーがあるため、今は申請できません。';
    } else if (result?.cooldown_until) {
      eligibilityReason.textContent = `掲載後のクールダウン中です。${formatDate(result.cooldown_until)}まで申請できません。`;
    } else {
      eligibilityReason.textContent = '申請条件が足りません。参戦予定を3公演以上登録するか、公演後の記録を1件以上登録してください。';
    }
  }

  function statusLabel(row) {
    if (row.status === 'pending') return '確認待ち';
    if (row.status === 'approved') return row.show_on < jstToday() ? '掲載済み' : '掲載予定';
    if (row.status === 'rejected') return '見送り';
    if (row.status === 'hidden') return '非表示';
    return '';
  }

  async function loadApplications() {
    applicationList.replaceChildren();
    const loadingText = document.createElement('p');
    loadingText.className = 'muted';
    loadingText.textContent = '読み込み中...';
    applicationList.append(loadingText);
    const { data, error } = await otakuSupabase
      .from('otaku_support_banners')
      .select('id,group_id,idol_id,occasion,show_on,message,display_mode,status,created_at')
      .eq('user_id', currentUserId)
      .order('created_at', { ascending: false })
      .limit(20);
    applicationList.replaceChildren();
    if (error) {
      const errorText = document.createElement('p');
      errorText.className = 'muted';
      errorText.textContent = '申請一覧を取得できませんでした。';
      applicationList.append(errorText);
      return;
    }
    if (!data?.length) {
      const empty = document.createElement('p');
      empty.className = 'muted';
      empty.textContent = 'まだ申請はありません。';
      applicationList.append(empty);
      return;
    }
    const groupNames = new Map(groups.map(group => [group.id, group.name]));
    data.forEach(row => {
      const item = document.createElement('article');
      item.className = 'application';
      const head = document.createElement('div');
      head.className = 'application__head';
      const target = document.createElement('strong');
      target.textContent = groupNames.get(row.group_id) || '公開終了のグループ';
      const status = document.createElement('span');
      status.textContent = statusLabel(row);
      head.append(target, status);
      const message = document.createElement('div');
      message.className = 'application__message';
      message.textContent = row.message;
      const meta = document.createElement('div');
      meta.className = 'application__meta';
      meta.textContent = `掲載日：${formatDate(row.show_on)} · 申請日：${new Date(row.created_at).toLocaleDateString('ja-JP', { timeZone: 'Asia/Tokyo' })}`;
      item.append(head, message, meta);
      applicationList.append(item);
    });
  }

  function submitErrorMessage(error) {
    const message = String(error?.message || '');
    if (message.includes('banner_not_eligible')) return '今は申請できません（条件・申請中の件数を確認してください）';
    if (message.includes('banner_invalid_message')) return 'メッセージは40字以内で、URL・メールアドレス・電話番号は入れられません';
    if (message.includes('banner_invalid_date')) return '掲載日は今日から60日以内で選んでください';
    if (message.includes('banner_invalid_target')) return 'グループ・メンバーを選び直してください';
    return '申請できませんでした。時間をおいてもう一度お試しください';
  }

  bannerForm.addEventListener('submit', async event => {
    event.preventDefault();
    if (!eligible || submitted) return;
    submitStatus.textContent = '';
    submitButton.disabled = true;
    submitButton.textContent = '送信中...';
    const { error } = await otakuSupabase.rpc('otaku_submit_support_banner', {
      target_group: groupSelect.value,
      target_idol: idolSelect.value || null,
      target_occasion: occasionSelect.value,
      target_show_on: showOn.value,
      target_message: bannerMessage.value.trim(),
      target_display_mode: bannerForm.elements.displayMode.value,
    });
    submitButton.textContent = '申請する';
    if (error) {
      submitStatus.textContent = submitErrorMessage(error);
      submitButton.disabled = false;
      return;
    }
    submitted = true;
    eligible = false;
    bannerFields.disabled = true;
    submitStatus.textContent = '申請しました。運営者の確認後、掲載日に表示されます。';
    await loadApplications();
  });

  groupSelect.addEventListener('change', loadIdols);
  idolSelect.addEventListener('change', renderPreview);
  occasionSelect.addEventListener('change', renderPreview);
  showOn.addEventListener('change', renderPreview);
  bannerMessage.addEventListener('input', () => {
    messageCount.textContent = `残り${40 - bannerMessage.value.length}文字`;
    renderPreview();
  });
  bannerForm.elements.displayMode.forEach(radio => radio.addEventListener('change', renderPreview));

  (async () => {
    const user = await otakuGetUser();
    loading.hidden = true;
    if (!user) {
      loginLink.href = otakuLoginUrl(location.href);
      signedOut.hidden = false;
      return;
    }
    currentUserId = user.id;
    signedIn.hidden = false;
    const today = jstToday();
    showOn.min = today;
    showOn.max = addDays(today, 60);
    showOn.value = today;
    const [groupsLoaded] = await Promise.all([loadGroups(), loadEligibility()]);
    bannerFields.disabled = !(groupsLoaded && eligible);
    idolSelect.disabled = true;
    renderPreview();
    await loadApplications();
  })();
})();
