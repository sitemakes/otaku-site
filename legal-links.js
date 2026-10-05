'use strict';
(() => {
  const effectiveDate = '2026年10月5日';
  const page = location.pathname.split('/').pop();
  const robots = document.querySelector('meta[name="robots"]');
  if (robots) robots.content = 'index,follow';
  document.title = document.title.replace('（公開準備中）', '').replace('（暫定公開）', '');

  const draft = document.querySelector('.draft');
  if (draft) {
    draft.innerHTML = `<strong>正式公開中の文書です。</strong><br>施行日：${effectiveDate}`;
  }

  const metaValues = document.querySelectorAll('.meta dd');
  if (page === 'terms.html' && metaValues[1]) metaValues[1].textContent = effectiveDate;
  if (page === 'privacy.html' && metaValues[2]) metaValues[2].textContent = effectiveDate;

  const replacements = new Map([
    ['未成年者の利用条件は公開前に確定します。', '18歳未満の利用には保護者の同意が必要です。13歳未満は利用できません。'],
    ['施行日、未成年者の利用条件、保存期間、委託先の取扱い等が未確定のため、現時点では正式な利用規約として適用しません。', `施行日は${effectiveDate}です。`],
    ['施行日、保存期間および委託先の取扱地域が未確定のため、確定前は正式なプライバシーポリシーとして適用しません。', `施行日は${effectiveDate}です。`],
    ['問い合わせ窓口は公開準備中です。', '問い合わせ窓口を公開しています。'],
    ['受付手順と本人確認方法が未確定のため、正式な外部受付としてはまだ開始していません。', '登録メールから受け付け、本人確認後に対応します。'],
    ['共通アカウントの削除手続は問い合わせ窓口の確定後に掲載します。', '共通アカウントの削除手続はお問い合わせページで受け付けます。'],
    ['具体的な保存期間、バックアップ、委託先ログの保持期間は公開前に確定します。', '通常データは退会まで、通知・操作ログは90日、安全対応・通報・監査記録は対応終了後2年間、バックアップは最長30日保存します。'],
    ['その他の開示、訂正、利用停止、共通認証アカウントの削除は、公開前に確定する問い合わせ窓口で本人確認のうえ受け付けます。', 'その他の開示、訂正、利用停止、共通認証アカウントの削除は、登録メールによる本人確認のうえお問い合わせ窓口で受け付けます。'],
    ['利用地域、保管場所、契約上の保護措置を公開前に確認して記載します。', '国外取扱いが生じる可能性があります。利用地域、保管場所、契約上の保護措置はお問い合わせ窓口で説明します。'],
    ['委託先で国外取扱いが生じる可能性があるため、国外取扱いが生じる可能性があります。利用地域、保管場所、契約上の保護措置はお問い合わせ窓口で説明します。', '国外取扱いが生じる可能性があります。利用地域、保管場所、契約上の保護措置はお問い合わせ窓口で説明します。'],
    ['具体的な安全管理措置の概要は、問い合わせ窓口の確定後に請求方法を掲載します。', '安全管理措置の概要は本ページに記載し、具体的な確認はお問い合わせ窓口で受け付けます。'],
    ['公開前に整備する受付', '問い合わせ受付'],
    ['重要な変更を行う場合の通知方法と適用時期は、公開前に確定します。', '重要な変更は、サイト内通知と法務ページの更新で案内します。'],
    ['サービス変更・停止の通知方法、責任範囲、準拠法および管轄は、運営形態の確定後に法令上無効となる免責を避けて定めます。', 'サービス変更・停止はサイト内で案内します。準拠法は日本法とし、第一審の専属的合意管轄裁判所は運営者所在地を管轄する裁判所とします。'],
    ['この文書はサービス仕様を整理するための下書きです。公開前に運営実態との一致を確認し、必要に応じて専門家の確認を受けます。', `施行日：${effectiveDate}。運営実態に変更が生じた場合は法務ページを更新します。`],
    ['参考：個人情報保護委員会「個人情報の保護に関する法律についてのガイドライン（通則編）」', '施行日：2026年10月5日'],
    ['公開準備中：運営者情報と窓口は未確定です', `正式公開：施行日 ${effectiveDate}`],
    ['暫定公開：施行日・保存期間等は確定後に更新します', `正式公開：施行日 ${effectiveDate}`],
    ['（暫定）', ''],
  ]);

  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  nodes.forEach(node => {
    let value = node.nodeValue;
    replacements.forEach((to, from) => { value = value.split(from).join(to); });
    node.nodeValue = value;
  });

  if (!document.querySelector('.legal-footer')) {
    const footer = document.createElement('footer');
    footer.className = 'legal-footer';
    footer.innerHTML = `<a href="terms.html">利用規約</a><a href="privacy.html">プライバシー</a><a href="contact.html">お問い合わせ</a><span class="legal-draft-label">正式公開：施行日 ${effectiveDate}</span>`;
    document.body.append(footer);
  }
  if (!document.querySelector('link[href="legal.css"]')) {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = 'legal.css';
    document.head.append(link);
  }
})();
