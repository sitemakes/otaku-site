'use strict';
(() => {
  const robots = document.querySelector('meta[name="robots"]');
  if (robots) robots.content = 'index,follow';
  document.title = document.title.replace('（公開準備中）', '（暫定公開）');
  const draft = document.querySelector('.draft');
  if (draft) {
    draft.innerHTML = draft.innerHTML
      .replace('公開準備中の文書です。', '暫定公開中の文書です。')
      .replace('問い合わせ窓口は公開準備中です。', '問い合わせ窓口を暫定公開しています。')
      .replace('現時点では正式な利用規約として適用しません。', '未確定項目は確定後に更新します。')
      .replace('確定前は正式なプライバシーポリシーとして適用しません。', '未確定項目は確定後に更新します。')
      .replace('正式な外部受付としてはまだ開始していません。', '受付手順は整備中です。');
  }
  if (document.querySelector('.legal-footer')) return;
  const footer = document.createElement('footer');
  footer.className = 'legal-footer';
  footer.innerHTML = '<a href="terms.html">利用規約</a><a href="privacy.html">プライバシー</a><a href="contact.html">お問い合わせ</a><span class="legal-draft-label">暫定公開：施行日・保存期間等は確定後に更新します</span>';
  document.body.append(footer);
  if (!document.querySelector('link[href="legal.css"]')) {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = 'legal.css';
    document.head.append(link);
  }
})();
