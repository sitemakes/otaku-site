/* Shared, dependency-free catalog validation. No URL is fetched automatically. */
(function (root) {
  'use strict';
  function sourceUrl(value) {
    const text = String(value || '').trim();
    if (!text) return null;
    if (text.length > 2048 || !/^https:\/\/[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+(\/[!-~]*)?$/.test(text) || /[<>"'\\]/.test(text)) {
      throw new Error('出典は https:// から始まるURLを入力してください。日本語URLはブラウザのアドレス欄からコピーしてください。');
    }
    const url = new URL(text);
    if (url.username || url.password || url.port) throw new Error('認証情報やポート番号を含むURLは使えません。');
    return text;
  }
  function jst(value) {
    if (!value) return null;
    if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d$/.test(value)) throw new Error('日時を入力してください。');
    const date = new Date(value + ':00+09:00');
    if (!Number.isFinite(date.getTime()) || toJst(date.toISOString()) !== value) throw new Error('存在する日時を入力してください。');
    return date.toISOString();
  }
  function toJst(value) {
    return value ? new Date(new Date(value).getTime() + 9 * 3600000).toISOString().slice(0, 16) : '';
  }
  function payload(kind, values) {
    const result = { publication_status: values.publication_status, is_demo: !!values.is_demo,
      source_url: sourceUrl(values.source_url), source_kind: values.source_kind || null,
      source_checked_at: values.source_checked_at || null };
    if (!['draft', 'published', 'archived'].includes(result.publication_status)) throw new Error('公開状態を選択してください。');
    if (result.source_kind && !['official','organizer','venue','ticketing'].includes(result.source_kind)) throw new Error('出典の種類を選択してください。');
    if (result.source_checked_at && (!Number.isFinite(Date.parse(result.source_checked_at)) || Date.parse(result.source_checked_at) > Date.now())) throw new Error('確認日は現在以前の日時にしてください。');
    if (!result.is_demo && result.publication_status === 'published' && (!result.source_url || !result.source_kind || !result.source_checked_at)) throw new Error('公開には出典URL・出典の種類・公式情報の確認が必要です。');
    function required(key, max) {
      const text = String(values[key] || '').trim();
      if (!text || text.length > max) throw new Error(`${key === 'venue' ? '会場' : '名称'}は1〜${max}文字で入力してください。`);
      result[key] = text;
    }
    if (kind === 'events') {
      required('title', 200); required('venue', 200);
      result.starts_at = jst(values.starts_at); result.ends_at = jst(values.ends_at);
      if (!result.starts_at) throw new Error('開演日時は必須です。');
      if (result.ends_at && result.ends_at < result.starts_at) throw new Error('終演日時は開演日時以降にしてください。');
      for (const key of ['prefecture','city']) result[key] = String(values[key] || '').trim() || null;
    } else required('name', 100);
    if (kind === 'groups') {
      result.slug = String(values.slug || '').trim();
      if (!/^[a-z0-9-]{2,80}$/.test(result.slug)) throw new Error('識別名は半角英小文字・数字・ハイフンの2〜80文字にしてください。');
    } else {
      result.group_id = values.group_id;
      if (!result.group_id) throw new Error('グループを選択してください。');
    }
    return result;
  }
  function errorMessage(error) {
    if (error.code === '23505') return '同じグループ・メンバー・公演が登録済みです。一覧を確認してください。';
    if (error.code === '42501') return '管理者権限がありません。ログイン状態を確認してください。';
    const messages = {
      catalog_source_required: '公開には出典URL・出典の種類・確認日時が必要です。',
      catalog_publish_group_first: '先に所属グループを公開してください。',
      catalog_unpublish_children_first: '所属する公開中のメンバー・公演を先に非公開にしてください。',
      catalog_group_type_mismatch: '実在データとDEMOデータを同じグループに混在させることはできません。',
      catalog_invalid_source_url: '出典URLを確認してください。',
      catalog_future_verification: '確認日時を確認してください。',
      catalog_identity_immutable: '既存データの実在・DEMO区分は変更できません。'
    };
    return messages[error.message] || (error.code ? '保存できませんでした。入力内容と接続を確認してください。' : error.message);
  }
  root.OtakuCatalog = { sourceUrl, jst, toJst, payload, errorMessage };
  if (typeof module !== 'undefined') module.exports = root.OtakuCatalog;
})(typeof globalThis !== 'undefined' ? globalThis : window);
