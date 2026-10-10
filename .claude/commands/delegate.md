---
description: docs/PLAN.md の指定ステップの実装を Codex に依頼する
argument-hint: <ステップ番号>（省略時は最初の未着手ステップ）
allowed-tools: Bash(codex exec:*), Bash(git status:*), Bash(git diff:*), Read
---

docs/PLAN.md のステップ「$ARGUMENTS」の実装を Codex に依頼してください。**自分ではコードを書かないでください。**

## 手順
1. docs/PLAN.md を読み、対象ステップを特定する（番号の指定がなければ最初の `未着手` のステップ）
2. 作業前の状態を `git status` で確認する
   - `docs/` 以下の未コミットの変更（/design で書いた PLAN.md など）は問題ない。そのまま進む
   - 対象ステップの末尾に「修正点」がある場合（/check で要修正になった後の再依頼）は、
     前回 Codex が書いたコードが未コミットで残っているのが正常。そのまま進む
   - それ以外で `docs/` 以外に未コミットの変更があれば、どのファイルかをユーザーに伝えて止まる
     （Codex の変更と混ざって /check でレビューできなくなるため）
   - 現在のブランチが `main` なら、ユーザーに作業用ブランチを作ってよいか確認する（main へ直接コミットしないため）
3. 次のコマンドで Codex に依頼する。時間がかかるため、タイムアウトを長め（最大10分）にするかバックグラウンドで実行する。
   `windows.sandbox="unelevated"` は、Codex デスクトップアプリ起動中に既定の elevated サンドボックスが起動できない問題を避けるための指定

```
codex exec -c 'windows.sandbox="unelevated"' --approve-for-me "AGENTS.md と docs/PLAN.md を読み、『ステップ <番号>』だけを実装してください。PLAN.md に書かれていない変更はしないでください。他のステップには手を付けないでください。終わったら bash scripts/check.sh と、そのステップの『確認方法』に書かれたコマンドを実行し、変更したファイルと確認結果を報告してください。ステップの末尾に『修正点』があれば、それも必ず反映してください。"
```

4. Codex の報告と `git diff --stat` の結果を短くまとめてユーザーに伝える
5. 「`/check` で設計どおりかレビューできます」と案内する

PLAN.md の状態欄はこの時点では更新しない（`/check` で問題がなければ `完了` にする）。
