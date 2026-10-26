'use strict';

async function otakuRenderSupportBanners(container, options = {}) {
  const showInviteWhenEmpty = Boolean(options.showInviteWhenEmpty);

  function makeLink(text, href, className) {
    const link = document.createElement('a');
    link.textContent = text;
    link.href = href;
    if (className) link.className = className;
    return link;
  }

  function showEmptyState() {
    container.replaceChildren();
    if (!showInviteWhenEmpty) {
      container.hidden = true;
      return;
    }

    const invite = document.createElement('p');
    invite.className = 'support-banner-invite';
    invite.append(
      document.createTextNode('推しへの応援メッセージを1日掲載できます → '),
      makeLink('応援バナーを申請する', 'support-banner.html')
    );
    container.append(invite);
    container.hidden = false;
  }

  container.replaceChildren();
  container.hidden = true;

  let banners;
  try {
    const { data, error } = await otakuSupabase.rpc('otaku_todays_support_banners', {
      target_group: options.groupId || null,
    });
    if (error) {
      showEmptyState();
      return;
    }
    banners = data || [];
  } catch {
    showEmptyState();
    return;
  }

  if (!banners.length) {
    showEmptyState();
    return;
  }

  const heading = document.createElement('div');
  heading.className = 'support-banner-heading';
  const title = document.createElement('h2');
  title.textContent = '今日の応援バナー';
  heading.append(
    title,
    makeLink('応援バナーを申請する', 'support-banner.html', 'support-banner-apply-link')
  );

  const items = document.createElement('div');
  items.className = 'support-banner-items';

  banners.forEach((banner) => {
    const item = document.createElement('div');
    item.className = 'support-banner-item';

    const card = otakuSupportBannerCard(banner);
    const actions = document.createElement('div');
    actions.className = 'support-banner-actions';

    const shareButton = document.createElement('button');
    shareButton.type = 'button';
    shareButton.textContent = '共有';

    const reportButton = document.createElement('button');
    reportButton.type = 'button';
    reportButton.textContent = '通報';

    const status = document.createElement('span');
    status.className = 'support-banner-status';
    status.setAttribute('role', 'status');
    status.setAttribute('aria-live', 'polite');

    shareButton.addEventListener('click', async () => {
      const url = `${location.origin}/index.html?group=${encodeURIComponent(banner.group_id)}`;
      const text = `「${banner.group_name}」への応援バナーが今日掲載されています #OTAKULIVE`;
      status.textContent = '';

      if (navigator.share) {
        try {
          await navigator.share({ text, url });
        } catch {
          // 共有のキャンセルは画面にエラーを出さない。
        }
        return;
      }

      try {
        await navigator.clipboard.writeText(url);
        status.textContent = 'リンクをコピーしました';
      } catch {
        status.textContent = 'リンクをコピーできませんでした';
      }
    });

    reportButton.addEventListener('click', async () => {
      reportButton.disabled = true;
      status.textContent = '';
      item.querySelector('.support-banner-report')?.remove();

      const report = document.createElement('div');
      report.className = 'support-banner-report';
      const currentUser = await otakuGetUser();

      if (!currentUser) {
        const loginNotice = document.createElement('p');
        loginNotice.append(
          document.createTextNode('通報にはログインが必要です。'),
          makeLink('ログイン', otakuLoginUrl())
        );
        report.append(loginNotice);
        item.append(report);
        return;
      }

      const form = document.createElement('form');
      const label = document.createElement('label');
      label.textContent = '通報理由';
      const textarea = document.createElement('textarea');
      textarea.maxLength = 500;
      textarea.required = true;
      textarea.rows = 4;
      label.append(textarea);

      const formActions = document.createElement('div');
      formActions.className = 'support-banner-report-actions';
      const submitButton = document.createElement('button');
      submitButton.type = 'submit';
      submitButton.textContent = '送信';
      const cancelButton = document.createElement('button');
      cancelButton.type = 'button';
      cancelButton.textContent = 'やめる';
      formActions.append(submitButton, cancelButton);
      form.append(label, formActions);
      report.append(form);
      item.append(report);
      textarea.focus();

      cancelButton.addEventListener('click', () => {
        report.remove();
        reportButton.disabled = false;
      });

      form.addEventListener('submit', async (event) => {
        event.preventDefault();
        const reason = textarea.value.trim();
        if (!reason) {
          textarea.setCustomValidity('通報理由を入力してください');
          textarea.reportValidity();
          return;
        }
        textarea.setCustomValidity('');
        submitButton.disabled = true;
        cancelButton.disabled = true;

        let error;
        try {
          ({ error } = await otakuSupabase.rpc('otaku_report_support_banner', {
            banner_id: banner.id,
            reason,
          }));
        } catch {
          error = { message: '' };
        }

        if (!error) {
          const success = document.createElement('p');
          success.className = 'support-banner-report-result';
          success.setAttribute('role', 'status');
          success.textContent = '通報しました。運営者が確認します。';
          item.replaceChildren(success);
          return;
        }

        const message = error.message || '';
        status.textContent = message.includes('report_invalid_context')
          ? 'このバナーは通報できません'
          : message.includes('report_rate_limit')
            ? '通報が多すぎます。時間をおいてください'
            : message.includes('duplicate key')
              ? 'すでに通報済みです'
              : '通報できませんでした';
        submitButton.disabled = false;
        cancelButton.disabled = false;
      });
    });

    actions.append(shareButton, reportButton, status);
    item.append(card, actions);
    items.append(item);
  });

  container.append(heading, items);
  container.hidden = false;
}
