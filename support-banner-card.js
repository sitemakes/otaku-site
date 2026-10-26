'use strict';

function otakuSupportBannerCard(banner) {
  const occasionLabels = {
    birthday: '誕生日',
    anniversary: '周年',
    event: '公演応援',
    other: '応援',
  };
  const card = document.createElement('article');
  card.className = 'support-banner';

  const label = document.createElement('div');
  label.className = 'support-banner__label';
  label.textContent = `応援バナー · ${occasionLabels[banner?.occasion] || occasionLabels.other}`;

  const target = document.createElement('div');
  target.className = 'support-banner__target';
  target.textContent = [banner?.group_name, banner?.idol_name].filter(Boolean).join(' · ');

  const message = document.createElement('div');
  message.className = 'support-banner__message';
  message.textContent = banner?.message || '';

  const from = document.createElement('div');
  from.className = 'support-banner__from';
  from.textContent = `from ${banner?.display_name || ''}`;

  const date = document.createElement('div');
  date.className = 'support-banner__date';
  const dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(banner?.show_on || '');
  date.textContent = dateMatch ? `${Number(dateMatch[2])}/${Number(dateMatch[3])}` : '';

  card.append(label, target, message, from, date);
  return card;
}
