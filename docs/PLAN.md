# PLAN: 集客の自動化（SEO・SNS 自動投稿）

**状態：承認済み（2026-10-11）。X は手動投稿のまま（自動投稿の対象外）**

## 目的
運営者が手を動かさなくても、(1) 検索から公演ページに人が来る、(2) SNS に新着公演・今週の公演が毎日自動で投稿される、状態にする。

## 前提（2026-10-11 調査）
- リポジトリは public → GitHub Actions は無料で使える。**ログは誰でも見られる**ので、秘密情報は必ず Actions secrets に置き、ログに出さない。
- X API：無料枠は廃止され従量課金。投稿 1 件 $0.015（1日2件で月約 $0.9）。認証は OAuth 1.0a（トークンの期限なし）を使う。
- Threads API：無料。権限 `threads_basic` `threads_content_publish`。24時間250件まで。長期トークン60日、期限内に更新が必要。自分のアカウントだけなら審査不要。
- Instagram API（Instagram Login）：無料。ビジネス/クリエイターアカウントが必要。画像は公開URLの JPEG。24時間25件まで。長期トークン60日、更新が必要。
- 公演データは公開 REST（publishable key、RLS で公開分のみ）から読める。`otaku_events.created_at` あり。

## スコープ外
- 他人のアカウントへの返信・いいね・フォローなどの自動操作（規約違反・凍結のおそれ）
- 公演ごとの画像の自動生成（今の OGP 画像は SVG で、X・Instagram は使えない。必要なら後で別 PLAN）
- 有料広告

## ステップ

### A. 検索からの集客（SEO）— 無料・アカウント不要
**A1・A2 完了（2026-10-11、PR #39）**：本番 /sitemap.xml に 201 URL（静的6＋公演195）、公演ページに Event の JSON-LD を確認。A3 は運営者の作業待ち。
1. **公演入りのサイトマップ**：`api/sitemap.js`（CommonJS、既存 `api/event-share.js` と同じ取得方法）を作り、静的ページ一覧＋公開済み・今後の公演の `https://otaku-live-mvp.vercel.app/event.html?id=<id>` を XML で返す（`lastmod` は `updated_at`、キャッシュ 1 時間）。`vercel.json` を新規作成し `/sitemap.xml` → `/api/sitemap` に rewrite。静的な `sitemap.xml` は削除。robots.txt は変更不要（URL は /sitemap.xml のまま）。
2. **公演ページの構造化データ**：`event.html` の公演読み込み後に、schema.org `Event`（name, startDate, location.name/address, url, eventStatus（中止・延期を反映）, organizer=グループ名）の JSON-LD を `<script type="application/ld+json">` として追加し、`meta[name=description]` も公演内容に更新する。値は textContent で入れる（innerHTML 不可）。
3. **運営者の作業**：Google Search Console にサイトを登録し、サイトマップを送信（手順は Claude が案内）。

### B. SNS 自動投稿の仕組み
**B1〜B3・B5 完了（2026-10-11、PR #40）**：GitHub Actions の手動 dry-run 成功（Threads・Instagram の文面を確認）。secrets 未登録のため本番投稿はまだ。B4（トークン更新）も完了（refresh-tokens.yml、毎週月曜 12:23 JST、失敗時は Issue）。
1. `scripts/marketing/post.mjs`（Node 20、依存なし、`fetch` のみ）：
   - 公開 REST から公演を取得し、投稿文を作る。
     - **毎日**：直近24時間に追加された公開済み・今後の公演があれば「新着公演」1投稿（最大5件をまとめ、残りは「ほか○件」）。無ければ「明日の公演」1投稿（無ければ投稿しない）。
     - **月曜**：上に加えて「今週の公演」1投稿（グループ名ごとに件数）。
     - 1チャネル1日最大2投稿。文面は事実だけ（グループ名・公演名・日付・会場）、ハッシュタグは `#OTAKULIVE` ＋最大2個、リンクはサイトのトップまたは公演一覧。
   - チャネルごとに送信（secret が無いチャネルは飛ばす）：Threads（テキスト＋リンク）、Instagram（固定画像 `og-default.jpg`＋キャプション）。X は対象外（運営者が手動で投稿。必要ならこのスクリプトの dry-run 出力をコピーして使う）。
   - `--dry-run` で投稿せず文面だけ出力。ログに秘密情報・トークンを出さない。
2. `og-default.jpg`：既存 `og-default.png` を JPEG に変換して配置（Instagram 用）。
3. `.github/workflows/marketing.yml`：毎日 19:07 JST（`7 10 * * *` UTC）に実行。手動実行（workflow_dispatch、dry-run 選択可）。secrets：`THREADS_USER_ID` `THREADS_TOKEN` `IG_USER_ID` `IG_TOKEN`。
4. **トークン更新**：週1回、Threads・Instagram の長期トークンを更新 API で延長し、`gh secret set` で secret を更新（secret 更新用の fine-grained PAT を `SECRETS_PAT` として登録）。失敗したら Issue を作って知らせる。
5. テスト：`tests/marketing.test.cjs`（投稿文の生成・文字数（Threads 500字以内・Instagram 2200字以内）・件数上限・dry-run）を node:test で。

### C. 運営者の作業（Claude が画面を出して案内。パスワード・トークンの入力は運営者が行う）
- Threads：Meta 開発者アプリ作成 → 長期トークン取得 → GitHub secrets に登録
- Instagram：アカウントをプロ（クリエイター）に切り替え → 同じ Meta アプリでトークン取得 → secrets 登録
- `SECRETS_PAT` の作成・登録

## 完了条件
- `/sitemap.xml` に公開済みの今後の公演が全件出る。公演ページに JSON-LD が入り、Google のリッチリザルトテストで Event として認識される。
- dry-run で、新着あり／なし／月曜の3パターンの文面が期待どおり出る。テストが通り、`bash scripts/check.sh` がすべてOK。
- 各チャネルで1回、本番投稿が成功する。トークン更新ジョブが手動実行で成功する。

## 進め方
A → B（dry-run まで）→ C（アカウント準備）→ 本番投稿、の順。A と B の実装は Codex、確認は Claude。

### D. 投稿の書き方の自動最適化（2026-10-11 承認）
**D1〜D4 完了（PR #43）**
1. 書き方（テンプレート）を複数用意し、1行目で見分けられるようにする：A「🆕 新着公演を追加しました」の一覧型（公演名・日付・都道府県/会場）、B「🆕 新着公演」のグループ見出し型（【グループ名】日付 会場）、C 呼びかけ型（1行目を5パターンから選ぶ。例「今週末の現場、一緒に行く人いますか？👀」）。公演名がグループ名で始まるときはグループ名を重ねない。明日・今週の投稿も同じテンプレートの考え方で作る。
2. 反応の取得：Threads の自分の投稿一覧（`/me/threads`）と各投稿のインサイト（views, likes, replies, reposts, quotes。権限 `threads_manage_insights`）を取得し、投稿の1行目からテンプレートを判定する。保存先は作らない（状態なし）。
3. 選び方（ε-greedy）：直近30日でテンプレートごとの反応率＝(likes+replies+reposts+quotes)/views を出す。各テンプレート3回未満なら未使用のものを優先、それ以外は 80% 最良・20% ランダム。インサイト取得に失敗したらランダム。
4. 週1回（月曜の実行時）に成績表（テンプレート別の投稿数・平均表示・平均反応率）を GitHub Actions の Step Summary に出す。
5. Instagram は接続後に同じ仕組みへ追加（別ステップ）。

### E. X 用の1タップ投稿リンク（2026-10-11 承認、無料）
**完了（PR #44）**
X は API で自動投稿しない（有料のため）。毎日の実行で X 用の文面（重み付き280以内）を作り、`https://x.com/intent/post?text=...` のリンクを付けて、GitHub の Issue「X 投稿用の文面」（ラベル `x-post`）にコメントする。運営者は通知メールのリンクを押して「ポスト」するだけ。

### F. 週次の集客レポート（分析と改善案）— 承認待ち（2026-10-12）
目的：毎週、SNS の閲覧数・サイトのアクセス数・サイト内の利用状況を集め、分析と改善案を Issue で受け取る。

1. **アクセス数の計測（新規）**：個人を特定しない「日別・ページ別の閲覧回数」だけを数える。
   - DB（migration `otaku_page_view_counts`）：テーブル `otaku_page_view_counts(day date, path text, views int, primary key(day,path))`。RLS 有効・直接の読み書きは不可。`otaku_count_page_view(path text)` を SECURITY DEFINER で追加し anon/authenticated に実行を許可（path は許可リストのページ名＋`event` のような種類だけに正規化、1日1ページ上限1万回で打ち止め）。IP・ユーザーID・Cookie は保存しない。
   - 画面：共通の `supabase.js` で、ページ表示時に1回だけ `otaku_count_page_view` を呼ぶ（失敗は無視）。管理画面は数えない。
   - プライバシーポリシーに「個人を特定しない閲覧回数の集計」を追記（改定日更新）。
2. **集計用の関数**：`otaku_growth_stats(report_key text, days int)` を SECURITY DEFINER で追加し、集計値だけ（期間内の新規登録数、参戦予定の登録数、同行募集・DM・掲示板・グッズの投稿数、ページ別閲覧回数）を返す。個人の情報は返さない。誰でも呼べないよう、`otaku_private` に保存したレポート用キーのハッシュと一致したときだけ返す（キー本体は GitHub Secrets の `REPORT_KEY` にだけ置く。service_role キーは使わない）。
3. **レポートの仕事**：`.github/workflows/growth-report.yml`（毎週月曜 9:17 JST）
   - `scripts/marketing/report-data.mjs` が、Threads/Instagram のインサイト（投稿ごとの表示・反応、テンプレート別成績）と `otaku_growth_stats(7)`・前週比を集め `report.json` を作る。
   - 既存の Claude 連携（`anthropics/claude-code-action`、`CLAUDE_CODE_OAUTH_TOKEN`）に `report.json` と `docs/launch-priority.md` を読ませ、Issue「週次集客レポート（YYYY-MM-DD）」に、数字の要約・前週比・伸びた/伸びなかった投稿・改善案3つ（すぐできる順、根拠つき）を書かせる。コードの変更や PR は作らせない。
4. Search Console の検索流入は API 連携に Google の認証設定が要るため、今回は対象外（運営者が画面で確認、必要なら後で追加）。

完了条件：サイトの閲覧回数が日別に記録される／手動実行でレポート Issue が作られ、数字と改善案が入っている／`bash scripts/check.sh` すべてOK。

### G. グループの追加と検索用の読み（2026-10-12）
- DB：`otaku_idol_groups.search_aliases`（スペース区切りの読み・別名、500字以内）を追加済み（migration `otaku_group_search_aliases`、dry-run 済み）。
- 国内12・K-POP 12グループを追加調査（Codex）。既存43グループの読み・別名も作成し登録する。

### H. グループの文字検索（2026-10-12）
ホームのグループ絞り込みをプルダウンから文字入力の候補検索に変える。ひらがな・カタカナ・英字・略称・記号の有無・全角半角の違いがあっても一致し、表示は正式名称。管理画面で読み・別名を編集できるようにする。
