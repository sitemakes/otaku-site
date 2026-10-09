# CLAUDE.md — OTAKU LIVE 運用ガイド

AI・開発者がこのリポジトリを引き継ぐための要点。詳細な運用ルールは `README.md` と `docs/` を参照。

## サイト概要
アイドル現場向けの Web サービス（本番: https://otaku-live-mvp.vercel.app ）。
公演一覧・詳細、参戦予定、同行募集（→DM→同行成立→評価）、グッズ交換、掲示板、公演後の記録、通報・ブロック、管理画面。
チケット交換専用の機能は無い（同行募集の「同行枠あり」と、規約上の注意のみ）。
公演・グループ・メンバー情報は管理者が公式出典を確認して手入力する（自動取得・スクレイピング・転載はしない）。

### 主なページ
| 区分 | ページ |
|---|---|
| 一般 | `index.html`（ホーム・公演一覧）, `event.html`（公演詳細）, `companion.html`（同行募集）, `goods.html`（グッズ交換）, `boards.html` / `board.html`（掲示板）, `user.html`（他人のプロフィール） |
| 本人 | `login.html`, `reset-password.html`, `onboarding.html`, `profile.html`（マイページ）, `notifications.html`, `dm.html` / `chat.html`, `review.html`（同行評価）, `safety.html`（ブロック・通報・自分の募集）, `withdraw.html`（退会） |
| 管理者 | `admin.html`（グループ・メンバー・公演）, `venue-admin.html`, `reports.html`（通報）, `content-admin.html`（投稿・評価の通報）, `review-admin.html` |
| 静的 | `terms.html`, `privacy.html`, `contact.html`（Supabase を読み込まない） |

## 技術構成
- Frontend: ビルド無しの静的 HTML + 素の JavaScript（フレームワーク・npm・package.json 無し）
- Backend: Supabase（Postgres + RLS + Auth）にブラウザから直接アクセス。業務ロジックの権限制御は **すべて DB 側（RLS・トリガー・関数）**
- SDK: `@supabase/supabase-js@2.117.2` を jsDelivr から読み込む。**バージョンは固定**。上げる場合は全 HTML（現在21ファイル）を同時に更新して動作確認する
- Serverless: `api/*.js`（Vercel Node Functions、CommonJS）
  - `client-error.js` ブラウザ例外を Vercel ログへ記録（本番オリジン以外は 403）
  - `event-share.js` / `event-og.js` 公演の共有ページ・OGP画像（公開済み公演のみ、5分キャッシュ）
- Hosting: Vercel プロジェクト `otaku-live-mvp`（Framework Preset: Other、Build/Install コマンド無し、Root はリポジトリ直下）。`.vercelignore` で `db/` `tests/` `docs/` `README.md` `CLAUDE.md` は配信しない
- Storage: 未使用（プロフィール画像は外部 https URL を保存するだけ）
- Styling: 共通テーマ `theme.css`（"Stage Night" デザイン、全25ページで読み込み）＋各ページ inline `<style>`。法務ページは `legal.css`、安全系ページは `safety-pages.css`
- 外部サービス: Supabase、Vercel、jsDelivr、Google Fonts（Space Grotesk / Zen Kaku Gothic New）、Google/Apple Maps へのリンクのみ

## ディレクトリ・コード構成
- `*.html` 各ページ。ページ固有のスクリプトは同名 `.js` または inline。機能単位の小さな `.js`（`favorites.js`, `map-links.js` など）を複数ページで `<script>` 読み込みして共有する
- 読み込み順: jsDelivr の supabase-js → `supabase.js` → 各モジュール。モジュールはグローバル関数・`otakuSupabase` に依存するので順序を崩さない
- `supabase.js` 共通クライアント `otakuSupabase`・`otakuGetUser()`（ページ内で1回だけ getUser）・`otakuGetProfile()`（本人の全項目を RPC `otaku_my_profile` で取得）・`otakuNextUrl()`（同一オリジンのみ許可するリダイレクト）・例外送信
- `catalog.js` 管理画面の入力検証（出典URL・日本時間変換・公開要件）。ブラウザと Node テストの両方で使う
- `api/` Vercel Functions
- `db/` 適用済み SQL の記録（migration 名は README・`docs/launch-safety-checks.md` 参照）。`test-*.sql` は ROLLBACK する DB テスト
- `tests/` Node テスト（`node:test`）
- `docs/` 公開優先順位・公開前チェック・バックアップ手順・法務・本番2ユーザーE2E 記録

## 実行方法
```bash
node --test tests/catalog.test.cjs                      # 単体テスト（Node 18+、依存パッケージ無し）
for f in *.js api/*.js; do node --check "$f"; done      # 構文チェック
npx serve .                                             # ローカル表示（任意の静的サーバーで可）
bash scripts/check.sh                                   # 上の2つ＋supabase-js の版ズレ・設定値の不一致・秘密情報混入をまとめて確認
```
- **作業の完了条件は `bash scripts/check.sh` が「すべてOK」になること**（Claude Code では終了時に hooks が自動実行し、NG なら差し戻す）
- `/api/*` はローカル静的サーバーでは動かない（`vercel dev` が必要）。ローカルでの例外送信の失敗は無視してよい
- ローカルでも **本番 Supabase に接続する**。ローカル操作で作ったデータは本番データになる
- DB テスト（`db/test-*.sql`）は Supabase の SQL エディタ等でトランザクション内実行しロールバックする。管理者1名・公開公演などの前提データが必要（各ファイル冒頭・README 参照）

## ビルド・デプロイ
- ビルド工程は無い。GitHub `sitemakes/otaku-site` の `main` へのマージで Vercel が本番デプロイ、PR はプレビュー（SSO 保護）
- 変更はブランチ → PR → マージ。`main` へ直接 push しない
- DB 変更は **フロントより先に** 適用する。旧フロントでも動く形（追加のみ）→フロント反映→旧権限の削除、の順に migration を分ける（例: `otaku_profile_privacy_additive` → PR #2 → `otaku_profile_privacy_enforce`）
- 適用済みの `db/*.sql` は再実行しない。新しい変更は新ファイル（または追記）として記録し、戻し手順も残す
- student-chat の Vercel プロジェクトや共通 DB へ誤ってデプロイしない

## データベース
- Supabase プロジェクト `pfyvsweuvdnpmvabfflh`（表示名 student-chat）を **別サービス student-chat と共用**。OTAKU LIVE は `public.otaku_*` と `otaku_private` スキーマのみ
- 全 `otaku_*` テーブルで RLS 有効。ユーザーが書ける列は列単位 GRANT で限定（`hidden`・`user_id` 等は更新不可）
- 管理者は `otaku_catalog_admins` の許可リスト（DB 管理者のみ追加可）。判定は `otaku_is_catalog_admin()`
- プロフィールの読み方: 本人は `otaku_my_profile()`、他人は `otaku_public_profiles`（`show_*` の公開設定を反映）、参戦人数は `otaku_event_attendee_count()`
- カタログ（グループ・メンバー・公演）は `revision` で上書き競合を検知。物理削除は不可で「非公開・保管」にする
- Supabase advisor の `security_definer_view`（`otaku_public_profiles`）と退会・通報管理・プロフィール系の SECURITY DEFINER 関数の警告は **意図的**（理由は `docs/launch-safety-checks.md`）。「直す」目的で変更しない
- 破壊的 SQL（DROP / TRUNCATE / 大量 DELETE）は実行前に必ず人間の確認を取る

## 認証
Supabase Auth（メール + パスワード、確認メール、パスワード再設定）。セッションはブラウザの localStorage。
Auth 設定は student-chat と共通のため変更しない。退会（`otaku_withdraw`）は OTAKU LIVE のデータ（関連 DM 含む）のみ削除し Auth ユーザーは残す。
運営者の承認を得て変更済みの共通設定（2026-10-10）:
- メール送信: カスタム SMTP（Gmail `smtp.gmail.com:587`、専用アカウント `sitemakes.6925@gmail.com` のアプリパスワード、送信者名「サービス通知」）。student-chat のメールも同じ送信元になるため、送信者名にサービス名を入れない。Gmail の送信上限は1日約500通、Supabase 側の上限は30通/時
- Redirect URLs: `https://otaku-live-mvp.vercel.app/**` を許可。Site URL は student-chat のまま変えない。確認メール・パスワード再設定は `emailRedirectTo` / `redirectTo` で OTAKU LIVE に戻るので、新しいドメインを使うときはここにも追加する

## 環境変数・秘密情報
現状 **使用していない**（`api/` にも `process.env` 参照は無いため `.env.example` も置いていない）。Supabase URL と publishable key は公開前提の値（権限は RLS で制御）。
service_role key・DB パスワードなどの秘密情報は **絶対にリポジトリやフロントに置かない**。必要になったら Vercel の Environment Variables に置き、`api/` からのみ参照する。

## 運用ルール
- 本番での動作確認データは本文先頭に `[公開前テスト]` を付け、確認後に片付ける
- 公演情報の登録・公開手順は README「情報の登録手順」に従う（公式出典の確認が必須）
- 公開前チェックや本番検証をしたら `docs/` の該当ファイルに日付付きで記録する
- 公開・実装の優先順位は `docs/launch-priority.md`（P0〜P3）を参照
- 障害・バックアップ・復元は `docs/backup-restore-runbook.md`

## 変更時の注意事項
- ボタンを隠すだけの権限制御は不可。必ず RLS/トリガーで拒否されることを確認する（未ログイン・一般ユーザー・管理者の3視点）
- ユーザー入力を `innerHTML` に入れる場合は各ファイルの `esc()` を通すか `textContent` を使う。`api/` の HTML/SVG 出力も同様
- `otaku_profiles` を直接 `select('*')` しない（他人の非公開項目を読む経路になり、列権限で 42501 になる）
- 未ログイン時はエラー表示や無限ローディングではなくログイン導線を出す（`otakuLoginUrl()`）
- `next` パラメータのリダイレクトは必ず `otakuNextUrl()` を通す（オープンリダイレクト防止）
- 同じ値が複数箇所にある: Supabase URL/key は `supabase.js`・`api/event-share.js`・`api/event-og.js`、本番ドメインは `api/client-error.js`・`api/event-share.js`・`calendar.js`（ICS の UID）。変更時は全箇所を揃える
- スマートフォン幅での表示崩れ（タブのはみ出し等）を確認する
- 共通 Auth・student-chat のテーブル/ポリシーには触れない

## 自動化（Claude Code / GitHub Actions）
- `.claude/settings.json`: 権限（聞かずに実行 / 確認 / 禁止）と hooks。`.js` 編集直後に構文チェック、終了時に `scripts/check.sh`
- `.github/workflows/claude.yml`: Issue・PR で `@claude` → 対応してPR作成。Actions からは DB に接続しないので、DB 変更は `db/` に SQL として記録し適用・戻し手順を PR に書く
- `.github/workflows/claude-monitor.yml`: 毎朝 08:50 JST に本番の応答・内部資料の非公開・外部依存・`scripts/check.sh` を確認し、異常時は `health-check` ラベルの Issue を作る
- `.claude/` `.github/` `scripts/` は `.vercelignore` で配信対象外

## 変更してはいけない重要部分
- `otaku_private` スキーマのガード関数・トリガー（募集終了・ブロック・なりすまし防止）
- `otaku_catalog_admins` の付与方法（ブラウザから付与できない設計）
- 監査・通報履歴テーブル（`otaku_catalog_audit`, `otaku_report_actions` 等）の削除
- `api/client-error.js` の送信内容（入力値・メール・認証情報を送らない）
- 利用データのある列・監査履歴の削除（旧 UI に戻す場合も追加列は残す）
