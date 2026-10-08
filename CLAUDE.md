# CLAUDE.md — OTAKU LIVE 運用ガイド

AI・開発者がこのリポジトリを引き継ぐための要点。詳細な運用ルールは `README.md` と `docs/` を参照。

## サービス概要
アイドル現場向けの Web サービス。公演一覧・詳細、参戦予定、同行募集（→DM→同行成立→評価）、グッズ交換、掲示板、公演後の記録、通報・ブロック、管理画面。
チケット交換専用の機能は無い（同行募集の「同行枠あり」と、規約上の注意のみ）。

## 技術構成
- Frontend: ビルド無しの静的 HTML + 素の JavaScript（フレームワーク・npm・package.json 無し）
- Backend: Supabase（Postgres + RLS + Auth）にブラウザから直接アクセス。業務ロジックの権限制御は **すべて DB 側（RLS・トリガー・関数）**
- SDK: `@supabase/supabase-js@2.117.2` を jsDelivr から読み込む。**バージョンは固定**。上げる場合は全 HTML を同時に更新して動作確認する
- Serverless: `api/*.js`（Vercel Node Functions）
  - `client-error.js` ブラウザ例外を Vercel ログへ記録
  - `event-share.js` / `event-og.js` 公演の共有ページ・OGP画像
- Hosting: Vercel プロジェクト `otaku-live-mvp`（Framework Preset: Other、Build/Install コマンド無し、Root はリポジトリ直下）
- Storage: 未使用（プロフィール画像は外部 https URL を保存するだけ）
- 外部サービス: Supabase、Vercel、jsDelivr、Google/Apple Maps へのリンクのみ

## ディレクトリ
- `*.html` 各ページ。ページ固有のスクリプトは同名 `.js` または inline
- `supabase.js` 共通クライアント・`otakuGetUser()`・`otakuGetProfile()`・エラー収集。**全ページが最初に読み込む**
- `api/` Vercel Functions
- `db/` 適用済み SQL の記録（migration 名は README 参照）。`test-*.sql` は ROLLBACK するDBテスト
- `tests/` Node テスト
- `docs/` 公開前チェック・バックアップ手順・法務・E2E 記録

## 開発コマンド
```bash
node --test tests/catalog.test.cjs        # 単体テスト
for f in *.js api/*.js; do node --check "$f"; done   # 構文チェック
```
ローカル起動は任意の静的サーバーで可（例: `npx serve .`）。`/api/*` はローカル静的サーバーでは動かない（`vercel dev` が必要）。
ローカルでも **本番 Supabase に接続する**ため、ローカル操作で作ったデータは本番データになる点に注意。

## ビルド・デプロイ
- ビルド工程は無い。GitHub `sitemakes/otaku-site` の `main` へのマージで Vercel が本番デプロイ、PR はプレビュー（SSO 保護）
- DB 変更は **フロントより先に** 適用する。旧フロントでも動く形（追加のみ）→フロント反映→旧権限の削除、の順に分ける

## データベース
- Supabase プロジェクト `pfyvsweuvdnpmvabfflh`（表示名 student-chat）を **別サービス student-chat と共用**。OTAKU LIVE は `public.otaku_*` と `otaku_private` スキーマのみ
- 全 `otaku_*` テーブルで RLS 有効。ユーザーが書ける列は列単位 GRANT で限定（`hidden`・`user_id` 等は更新不可）
- 管理者は `otaku_catalog_admins` の許可リスト（DB 管理者のみ追加可）。判定は `otaku_is_catalog_admin()`
- 公開プロフィールは `otaku_public_profiles` 経由で読む（`show_*` の公開設定を反映）
- 破壊的 SQL（DROP / TRUNCATE / 大量 DELETE）は実行前に必ず人間の確認を取る

## 認証
Supabase Auth（メール + パスワード、確認メール、パスワード再設定）。セッションはブラウザの localStorage。
Auth 設定は student-chat と共通のため変更しない。退会（`otaku_withdraw`）は OTAKU LIVE のデータのみ削除し Auth ユーザーは残す。

## 環境変数
現状 **使用していない**。`supabase.js` と `api/*.js` の Supabase URL と publishable key は公開前提の値（権限は RLS で制御）。
service_role key・DB パスワードなどの秘密情報は **絶対にリポジトリやフロントに置かない**。必要になったら Vercel の Environment Variables に置き、`api/` からのみ参照する。

## 開発時の注意
- ボタンを隠すだけの権限制御は不可。必ず RLS/トリガーで拒否されることを確認する
- ユーザー入力を `innerHTML` に入れる場合は各ファイルの `esc()` を通すか `textContent` を使う
- `otaku_profiles` を直接 `select('*')` しない（他人の非公開項目を読む経路になる）
- 共通 Auth・student-chat のテーブル/ポリシーには触れない
- 本番での動作確認データは本文先頭に `[公開前テスト]` を付ける

## 変更してはいけない重要部分
- `otaku_private` スキーマのガード関数・トリガー（募集終了・ブロック・なりすまし防止）
- `otaku_catalog_admins` の付与方法（ブラウザから付与できない設計）
- 監査・通報履歴テーブル（`otaku_catalog_audit`, `otaku_report_actions` 等）の削除
- `api/client-error.js` の送信内容（入力値・メール・認証情報を送らない）
