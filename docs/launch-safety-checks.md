# 公開前の安全対策（2026-09-30）

適用順: `db/launch-safety.sql` → `db/content-safety.sql` → `db/content-report-visibility.sql`。
変更対象は OTAKU LIVE 専用テーブル・関数のみ。共通 Auth と student-chat のデータは変更しない。

## 確認済み
- 全48 JavaScriptスクリプトの構文チェック。
- `db/test-launch-safety.sql` を実DB上のトランザクションで実行し、終了時にROLLBACK。一般ユーザーの管理操作拒否、通報・非表示・再公開・履歴、双方向ブロック、退会後の他サービスと共通Authの維持を確認。
- `db/test-social-safety.sql` を実DB上のトランザクションで実行し、42項目を通過。DM、同行募集、通報、ブロック、匿名アクセス、管理者監査を確認し、終了時にROLLBACK。
- ブラウザーで未ログイン時の管理画面が通報データを表示しないことを確認。
- 認証済み管理者セッションで本番の管理画面を確認。グループ・メンバー・公演の登録画面、会場ガイド、通報、掲示板・評価通報、同行評価の各管理導線が表示され、コンソールエラーなし。データ変更は行っていない。
- 全ページ共通のクライアントエラー収集を追加。予期しないブラウザー例外と未処理Promise拒否を、入力値・メールアドレス・認証情報を含めず `/api/client-error` 経由でVercel実行ログへ記録する。重複は同一ページ内で抑制し、収集失敗は画面動作に影響しない。
- バックアップ・復元手順を `docs/backup-restore-runbook.md` に整備。復元演習は本番を巻き戻さず、一時環境で実施する。

## 公開前に残る確認
- 運営者名、問い合わせ窓口、保存期間、未成年の利用条件、施行日、本人確認手順を確定し、法務ページを正式公開状態へ更新した。
- 漏洩パスワード保護はSupabase Freeでは利用不可。Pro以上への変更は未実施。
- セキュリティ検査で退会・通報管理の2つの SECURITY DEFINER API が警告対象。意図的な権限処理であり、固定search_path、本人・管理者判定、匿名実行禁止を実装。一般ユーザーの管理操作拒否を実動確認済み。
- 認証した管理者による本番ブラウザー操作の通し確認は完了。実データ登録・公開を伴う運用確認は別途必要。

退会は関連DM会話も削除する。共通認証アカウントは削除しない。通報に保存された証拠やバックアップの扱いは運営ルール確定時に明記する。

## プロフィール公開設定のDB強制（2026-10-09）
- `db/profile-privacy.sql` を migration `otaku_profile_privacy_additive` → フロント反映（PR #2）→ `otaku_profile_privacy_enforce` の順に適用。
- 修正前は `otaku_profiles`・`otaku_event_attendees`・`otaku_user_favorites` をログイン中の全ユーザーがAPIで全件取得でき、`show_*` の非公開設定を迂回できた。
- 現在は他人の年代・性別・都道府県・自己紹介・同行条件は列権限で取得不可（42501）。参戦予定・推しは本人または公開設定オンの行のみ。未ログインはプロフィール系をすべて拒否。本番で確認済み。
- 本人の全項目は `otaku_my_profile()`、参戦人数は `otaku_event_attendee_count()`、他人の公開プロフィールは `otaku_public_profiles` を使う。
- セキュリティ検査の `security_definer_view`（otaku_public_profiles）と2つの SECURITY DEFINER 関数の警告は意図的。ビューは公開設定でマスクする唯一の経路で、関数は本人の行・件数のみを返し、anon は実行不可。
- 戻す場合の手順は `db/profile-privacy.sql` 末尾に記載。

## P0 最終確認（2026-10-09）
- RLS：public / otaku_private の全テーブルで有効（OTAKU LIVE・student-chat とも）。
- advisor で SECURITY DEFINER と警告される6関数を確認した。既知の4つに加え、`otaku_set_board_pinned`（管理者判定あり）と `otaku_toggle_board_reaction`（ログイン必須・表示可能な投稿のみ）も、`search_path` が固定され anon からは実行できない。意図どおり。
- 退会時の削除範囲：ユーザーに関わる列はすべて `otaku_profiles` からの連鎖削除の対象。外部キーが無いのは管理者の監査 `actor_id`（管理者は退会できない）と、`otaku_content_reports.target_id`（対象が複数種類ある列）だけ。
- 同行評価・一般ユーザーへの通報・退会を `db/test-p0-review-report-withdraw.sql` で検証した（21項目通過、結果は `two-user-e2e.md` に記録）。
- 未解決：
  - 通報者または対象者が退会すると通報と証拠が消える（ポリシーでは2年保存）。
  - 「通知・操作ログ90日」を削除する定期処理が無い（pg_cron のジョブは公演リマインダーだけ）。
  - Free プランなのでバックアップが無い。
