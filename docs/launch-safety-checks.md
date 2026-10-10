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
- 2026-10-09 に対応：
  - 通報の保存：`db/report-retention.sql`（migration `otaku_report_retention`）を適用した。通報者・対象者が退会してもIDが空になるだけで、通報・証拠・対応履歴は残る。通報ガード関数には、外部キーの連鎖更新（IDを空にするだけで、状態は変えないもの）だけを通す例外を追加した。一般ユーザーと管理者が通報のIDを直接書き換えることは、今までどおりできない。dry-run で12項目を確認した。管理画面と自分の通報一覧では「退会済みユーザー」と表示する。
  - 90日削除：`db/notification-retention.sql`（migration `otaku_notification_retention`）を適用した。pg_cron で毎日 03:30 JST に、作成から90日を過ぎた通知を削除する。適用時点で通知は0件だったので、既存データは消えていない。
  - バックアップ：Free プランのまま、`scripts/backup-db.ps1` による手動ダンプで運用する（`backup-restore-runbook.md`）。初回のダンプは未実施。
- 残り：対応終了後2年を過ぎた通報の削除は未実装（最も古い通報が2年に近づくまでに追加する）。
## メール送信と戻り先URL（2026-10-10）
- Supabase 標準のメール送信は、1時間に2通までの制限があり、本番向けではなかった。そこで運営者の承認を得て、Auth（student-chat と共通）のカスタム SMTP を Gmail に切り替えた（専用アカウント、アプリパスワード、送信者名「サービス通知」、`smtp.gmail.com:587`）。切り替え後は、Supabase 側の上限が30通/時になった。
- 設定の途中で、Gmail の認証エラー（535）とポート番号の入力ミスが一時的に起きた。その間は OTAKU LIVE と student-chat の確認メールが送れなかった。いったんカスタム SMTP をオフに戻してから、設定を入れ直した。
- Redirect URLs が未登録だったため、OTAKU LIVE の確認メールとパスワード再設定のリンクが、Site URL（student-chat）に飛んでいた。`https://otaku-live-mvp.vercel.app/**` を追加し、再設定のリンクで OTAKU LIVE の画面が開くことを確認した。Site URL は変えていない。
- 残り：利用者が増えたら、独自ドメイン＋専用のメール配信サービス（Resend など）への移行を検討する。

## 投稿・DM の使いすぎ対策（2026-10-10）
- `db/rate-limits.sql` を migration `otaku_rate_limits` として適用した。共通のトリガー関数 `otaku_private.enforce_rate_limit()` を追加し、8テーブルに BEFORE INSERT トリガー `otaku_rate_limit` を付けた（既存のガード関数は変更していない）。
- 制限値：DM の送信 1分10件・1日300件／DM の開始 10分5件・1日20件／同行募集 1時間5件・1日10件／掲示板の投稿 10分5件・1日30件／掲示板の返信 1分5件・1日100件／グッズ交換 1時間5件・1日10件／公演後の記録 10分5件・1日20件／フォロー 1時間30件・1日100件。
- 制限に当たると `rate_limited`（errcode 23514）で拒否し、画面には `otakuRateLimitMessage()` の共通の文言を出す。利用者×テーブルごとに advisory lock を取ってから数えるので、同時に送っても数え漏れが出ない。
- 関数は public・anon・authenticated から実行できない（トリガーからのみ）。advisor に新しい警告は無い。
- `db/test-rate-limits.sql` を本番 DB で dry-run し、5項目通過した。
- 画面での連投テストは未実施（2026-10-10）。アプリ内ブラウザが、このサイトの CSS・JS の読み込みを `ERR_BLOCKED_BY_CLIENT` で止めるようになったため。サーバーからはすべて 200 で返り、配信中の `supabase.js` に `otakuRateLimitMessage` が入っていることは確認した。運営者の判断で、DB での確認をもって完了とした。

## 重複公演のチェック（2026-10-10）
- 管理画面で公演を保存するとき、同じグループ・同じ種類（実在／DEMO）で、日本時間の同じ日に始まる公演がすでにあれば、確認ダイアログで警告する。下書き・公開・非公開・保管のすべてが対象。キャンセルすると保存しない。
- 警告には候補の公演名・日時・会場・公開状態を出し、開始時刻の差が30分以内なら「開始時刻がほぼ同じ」、会場名が同じなら「同じ会場」と添える（会場名は NFKC 正規化と空白の除去で比べる）。
- 昼夜公演などの正当な同日公演があるため、保存を止めきらない警告にとどめ、DB の一意制約は追加していない。編集でグループと開始日時を変えていない場合は確認しない。
- 判定は `catalog.js` の `jstDayRange`・`duplicateEvents` で行い、`tests/catalog.test.cjs` で日本時間の日付の境目、30分の内外、会場名の表記ゆれ、日時の形式の違い（`+00:00` と `Z`）を確認した。
- 画面での確認は、アプリ内ブラウザの不具合のため未実施（Node のテストとコードの読み合わせで確認）。

## 公演情報の更新・中止の対応（2026-10-10）
- `db/event-status-followups.sql` を migration `otaku_event_status_followups` として適用した。既存のガード関数は変更していない。
  - リマインダー（`run_event_reminders`）：中止・延期の公演を対象から外した。重複防止はリマインダーどうしだけで見るようにした（日時変更のお知らせが届いた人にも、リマインダーが届く）。
  - 日時・会場の変更の通知：公開中の公演の `starts_at`・`ends_at`・`venue` が変わり、状態と案内が変わっていないときに、参戦予定とお気に入り（通知オン）の人へ「公演情報変更のお知らせ」を1人1通送る（トリガー `otaku_event_schedule_notify`）。
  - 状態変更の通知（`notify_event_lifecycle`）：参戦予定とお気に入りの両方に入っている人に2通届いていたのを、1通にした。
  - 中止の公演には、新しい同行募集と公演の DM を作れない（`event_cancelled`、トリガー `otaku_cancelled_event_guard`）。既存の募集・DM は使える。延期の公演は止めない。
- 画面：ホームの公演一覧とおすすめ、マイページの参戦予定、お気に入り、近日の公演、他の人の参戦予定・記録に「中止」「延期」「変更あり」の印を付けた（中止は薄く表示）。カレンダー登録（ICS）は、中止なら「【中止】」と `STATUS:CANCELLED`、延期なら「【延期】」を付ける。中止の公演で募集・DM を作ろうとしたときの文言を追加した。
- `db/test-event-status-followups.sql` を本番 DB で dry-run し、6項目通過した。新しい関数は public・anon・authenticated から実行できない。
- 画面での確認は、アプリ内ブラウザの不具合のため未実施（コードの読み合わせと DB テストで確認）。

## 通知の停止・変更の確認（2026-10-10）
- 通知設定は、全体（`in_app_enabled`、初期値オフ）と種類ごと（DM・掲示板・公演）の4つ。マイページで変更でき、初回プロフィールでは4つともオフから始まって本人が選ぶ。お気に入りの公演・グループごとの通知も、お気に入りの画面でオン・オフできる。
- 通知を作る9つの処理は、どれも全体の設定と種類ごとの設定の両方を見ている。DM・掲示板の通知は、ブロックしている相手からは出ない。
- 権限：通知設定は本人の行だけ読み書きできる。通知は本人が既読（`read_at`）とアーカイブ（`archived_at`）だけを変えられ、作成・削除はできない。お気に入りは `notify` の列だけを変えられる。
- `db/test-notification-preferences.sql` を本番 DB で実行し（ロールバック）、9項目通過した（DM・掲示板の投稿・掲示板の返信・公演の通知が、オンなら届き、種類ごと・全体のどちらをオフにしても止まる）。
- 見つけて直した不具合：通知一覧の `safeHref()` が `board.html?event=<ID>` で終わるリンクしか許可しておらず、カテゴリや `#post-<ID>` が付く掲示板の通知が、すべて `#`（移動しないリンク）になっていた。カテゴリと投稿へのジャンプを許可する形に直した（外部 URL・`javascript:`・余計なパラメータは引き続き拒否）。
- 使われていなかった古い関数2つ（`public.otaku_create_event_reminders`・`otaku_private.notify_event_status`）は、どこからも参照されていないことを確認したうえで、運営者の承認を得て削除した（`db/drop-unused-functions.sql`、migration `otaku_drop_unused_functions`。戻すための定義は同じファイルに記録）。
