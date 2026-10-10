# プロジェクト運用ルール（Codex 向け）

## 役割分担
- **Claude（Claude Code）**: 設計・レビュー担当。設計は docs/PLAN.md に書かれる。
- **Codex（あなた）**: 実装担当。docs/PLAN.md に書かれた内容だけを実装する。

技術構成・DB・セキュリティ上の注意は CLAUDE.md にまとまっている。実装前に必ず読むこと。

## 実装するとき
- 依頼されたステップだけを実装する。他のステップには手を付けない
- docs/PLAN.md に書かれたファイル名・関数名・処理の流れに従う
- そのステップの末尾に「修正点」が追記されていれば、必ず反映する
- 終わったら `bash scripts/check.sh` と、そのステップの「確認方法」に書かれたコマンドを実行し、通ることを確認する

## このリポジトリで必ず守ること（詳細は CLAUDE.md）
- ビルド無しの静的 HTML + 素の JavaScript。npm パッケージ・package.json・フレームワークを追加しない
- `supabase-js` のバージョンは固定。変えない
- ユーザー入力を `innerHTML` に入れるときは `esc()` を通すか `textContent` を使う
- `otaku_profiles` を直接 `select('*')` しない。リダイレクトは `otakuNextUrl()` を通す
- 権限制御をボタンを隠すだけで済ませない
- Supabase URL/key・本番ドメインは複数ファイルにある。変えるときは全箇所を揃える

## してはいけないこと
- docs/PLAN.md、CLAUDE.md、AGENTS.md、.claude/、.github/ を編集しない
- PLAN.md にない機能追加、リファクタリング、依存の追加をしない
- DB（Supabase）に接続・SQL を実行しない。DB 変更が PLAN.md にあれば `db/` に SQL ファイルとして書くだけにする
- service_role key などの秘密情報をファイルに書かない
- git commit や git push をしない（レビュー後にユーザーが行う）

## 迷ったとき
- PLAN.md があいまいで判断が必要なとき、または PLAN.md どおりでは動かないときは、
  勝手に決めずに実装を止め、何が問題かを報告する

## 終わったら
- 変更したファイルの一覧と、完了条件をどう確認したかを短く報告する
