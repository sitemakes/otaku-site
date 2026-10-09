# OTAKU LIVE バックアップ・復元手順

この手順は OTAKU LIVE の公開前運用向けです。student-chat のデータ、共通Authアカウント、他サービスのデータは対象にしません。

## バックアップ（Free プラン：手動ダンプ、2026-10-09 決定）

Free プランでは Supabase の自動バックアップを使えないので、運営者が `scripts/backup-db.ps1` で定期的にダンプを取る。共用DBのため、ダンプには student-chat のデータと共通Authも含まれる。復元はOTAKU LIVEだけを選んで行えないので、扱いに注意する。

**頻度**：毎週1回と、DBの migration を本番に適用する直前。

**初回の準備**
1. Docker Desktop をインストールして起動する（Supabase CLI は Docker 上で `pg_dump` を動かす）。Node.js は導入済み（`npx supabase` を使う）。
2. Supabase Dashboard の **Connect** から、**Session pooler** の接続文字列をコピーする。DBパスワードが分からなければ Database Settings で再設定する。パスワードを再設定すると、そのパスワードを使っている他の接続も更新が必要になる（現状、リポジトリやVercelに保存している箇所は無い）。

**毎回の手順**（PowerShell）
1. `$env:OTAKU_DB_URL = "<接続文字列>"`：この環境変数はそのターミナルの中だけで使う。接続文字列はチャット・リポジトリ・メモに貼らない。
2. `powershell -ExecutionPolicy Bypass -File scripts\backup-db.ps1`
   - `%USERPROFILE%\otaku-db-backups\<日時>\` に `roles.sql` `schema.sql` `data.sql` が保存される。リポジトリ内やOneDriveの同期フォルダには保存しない。
   - 30日を過ぎたバックアップフォルダは、このスクリプトが自動で削除する（プライバシーポリシーの「バックアップは最長30日」）。
3. `Remove-Item Env:OTAKU_DB_URL`
4. 実施日、保存先、`data.sql` に含まれる OTAKU LIVE のテーブル数（スクリプトの出力）を、下の「バックアップ記録」に追記する。ダンプの中身はチャットやGitHubにコピーしない。

**復元**：新しい Supabase プロジェクトを作り、公式手順（Backup and Restore using the CLI）の `psql --single-transaction ... --file roles.sql --file schema.sql --command 'SET session_replication_role = replica' --file data.sql` で戻す。本番プロジェクトへ直接流し込まない。

### バックアップ記録

| 実施日 | 実施者 | 保存先 | OTAKU LIVE テーブル数 | 備考 |
|---|---|---|---|---|
| （未実施） | | | | 初回は公開前に実施する |

## 復元演習

本番データを直接巻き戻さず、Supabaseの復元先または一時ブランチで行う。

1. 復元先を作成し、バックアップの日時を固定する。
2. 復元後にスキーマとRLSが適用されていることを確認する。
3. 次の代表データを読み取り専用で確認する。
   - 公開済みの実在公演が表示できる
   - 同行募集、DM、掲示板、通報、評価の関連が壊れていない
   - 管理者以外がカタログ管理操作を実行できない
   - student-chat のテーブルやデータに変更がない
4. 本番環境へ戻す判断は、確認結果と復元時刻を運営記録に残してから行う。

## 障害時の連絡

Vercelの実行ログとSupabaseのログを突き合わせ、発生時刻、画面URL、リクエストID、影響範囲を記録する。利用者のメールアドレス、DM本文、通報詳細などを障害報告へ転載しない。問い合わせ窓口は法務ページの確定後に案内する。

## 現在の状態

- 手順: 整備済み
- Supabaseの保持期間・料金プラン（2026-10-09 確認）: 組織は Free プラン。公式ドキュメントでは、日次バックアップを使えるのは Pro 以上（Pro は7日分）で、Free プランは `supabase db dump` による自前のバックアップが推奨されている。現在はダッシュボードから使えるバックアップが無い
- 復元演習: Freeプランではブランチ作成が利用できないため未実施。本番の読み取り専用確認では、OTAKU LIVE 38テーブルのRLS未設定が0件、student-chat側の代表テーブルもRLS有効を確認済み。
