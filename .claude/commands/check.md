---
description: Codex の実装が docs/PLAN.md どおりかレビューする
argument-hint: <ステップ番号>（省略時は直近に委任したステップ）
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(bash scripts/check.sh), Bash(node --test:*), Read, Grep, Glob, Edit(docs/**)
---

Codex が実装した変更を、docs/PLAN.md と照らし合わせてレビューしてください。**コードは修正しないでください。**

対象ステップ: $ARGUMENTS

## 手順
1. docs/PLAN.md の対象ステップと、`git status`・`git diff` の内容を読む
2. `bash scripts/check.sh` を実行する（「すべてOK」でなければその時点で要修正）
3. 次の観点で確認する
   - PLAN.md に書かれたファイル・関数・処理がすべて実装されているか
   - PLAN.md にない変更（余計なファイル・スコープ外の修正）が入っていないか
   - 完了条件・確認方法を満たしているか
   - CLAUDE.md「変更時の注意事項」に反していないか。特に:
     - ユーザー入力を `innerHTML` に入れるときに `esc()` / `textContent` を使っているか
     - `otaku_profiles` を直接 `select('*')` していないか
     - リダイレクトが `otakuNextUrl()` を通っているか
     - ボタンを隠すだけの権限制御になっていないか
     - Supabase URL/key・本番ドメインの重複箇所がずれていないか
   - 「変更してはいけない重要部分」に触れていないか
   - 明らかなバグ、エラー処理の抜け、スマートフォン幅での崩れの恐れがないか
4. 結果を以下の形で報告する
   - **判定**: OK / 要修正
   - **設計とのずれ**: 箇条書き（ファイル名と行の目安つき）
   - **その他の指摘**: 箇条書き
5. 判定が OK なら、PLAN.md の対象ステップの状態を `完了` に更新する。
   そのうえで「このステップの変更（コードと PLAN.md）をコミットしてよいか」をユーザーに確認し、
   了承されたらコミットする（main には直接コミットしない）。
   最後に次の未着手ステップを案内する
6. 要修正なら、PLAN.md の対象ステップの末尾に「修正点」として指摘を追記し、「`/delegate <番号>` で修正を Codex に依頼できます」と伝える。
   この時点ではコミットしない（Codex は未コミットのコードの上から修正する）
