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

### I. 公演の自動チェック（2026-10-12 承認）
毎日、登録済みグループを約10件ずつ（1週間で一巡）、GitHub Actions 上の Claude（claude-code-action、WebFetch のみ）が公式サイトを確認し、未登録の公演候補を Issue「公演の追加候補（日付）」（ラベル event-candidates）に JSON 付きで挙げる。登録は運営者の指示で Claude が管理画面から行う（自動登録はしない）。出典は公式サイトのみ、開演時刻・会場が公式に書かれたもののみ、劇場の定期公演・特典会・配信は除外。

### J. 新グループ追加の週次ルーティン（2026-10-12 承認）
毎週木曜、GitHub Actions 上の Claude が、未登録の人気グループを約10件（国内5・K-POP 5）選び、公式サイトで正式名称・現メンバー・今後の公演・検索用の読みを調べ、Issue「新グループの追加候補（日付）」（ラベル group-candidates）に catalog-import 形式の JSON 付きで挙げる。登録は運営者の指示で Claude が管理画面から行う。

### K. 投稿の種類を増やす（2026-10-14 承認）
テンプレートに D（大型公演のカウントダウン）・E（地域別の今週末）・F（質問型）・G（新グループのお知らせ）を追加し、既存の成績による選択（ε-greedy）に含める。データが無い日は A にフォールバック。

### L. 投稿からサイトに来てもらう（直リンク・型の絞り込み・流入計測）— 承認待ち（2026-10-26）
**背景**：10/13〜10/19 に Threads は 15投稿・表示313 だったが、サイト閲覧は週38→翌週5、反応（いいね等）0。投稿は見られているがリンクが押されていない。全投稿のリンクがトップページ（`SITE_URL`）で、読んだ人の知りたいページに直接行けない。表示が多かったのは B（グループ別まとめ、平均35）・C（呼びかけ、平均34.5）、少なかったのは D（カウントダウン）・F（質問）・G（新グループ紹介）で各5〜7。

**目的**：投稿のリンクを「その投稿の内容のページ」に変え、成績の悪い型をやめ、どの投稿から何人来たかを数えられるようにする。

**スコープ外**：画像付き投稿、ハッシュタグの変更、Instagram の投稿内容（Instagram は本文のリンクが押せないので変更しない）、他人の投稿への返信などの自動操作、Vercel Web Analytics の有効化。

#### L1. 流入元の計測（DB → 画面の順。DB は Claude が dry-run 後に適用）
**実装・チェック完了（2026-10-26、ブランチ feat/sns-source-tracking）**：`db/page-source-counts.sql`・`supabase.js`・`privacy.html`。本番でロールバック付き dry-run 済み（許可外の source は数えない／大文字の Threads も threads に／不正な campaign は空／anon・authenticated はテーブルを直接読めない／`otaku_growth_stats` に source_views・sources が出る）。本番 DB に migration `otaku_page_source_counts` として適用済み（2026-10-26、RLS 有効・anon/authenticated の直接参照不可を確認）。
1. `db/page-source-counts.sql`（新規。追加のみ・戻し手順をファイル末尾にコメントで書く）
   - テーブル `public.otaku_page_source_counts(day date, source text, campaign text, views int not null default 0, primary key(day, source, campaign))`。RLS 有効、anon/authenticated の直接権限は revoke。
   - 関数 `public.otaku_count_page_source(source text, campaign text)`：SECURITY DEFINER、`set search_path = ''`。`source` は `threads` / `instagram` / `x` 以外なら何もしない。`campaign` は正規表現 `^[A-H]$` に一致しなければ `''`。day は日本時間の今日。既存 `otaku_count_page_view` と同じ形で upsert、1日1行上限1万回。anon/authenticated に execute を許可。
   - `public.otaku_growth_stats` を `create or replace` し、既存の戻り値はそのままに `'sources'`（今週の `source`・`campaign` 別合計の配列）と `'previous'` 内の `'source_views'`（前週の合計）を追加する。既存キーの名前・意味は変えない。
2. `supabase.js`（106行目の `otaku_count_page_view` 呼び出しの直後）：`new URLSearchParams(location.search).get('utm_source')` が `threads`/`instagram`/`x` のときだけ、`otaku_count_page_source` を1回呼ぶ（`utm_campaign` をそのまま渡す。検証は DB 側）。同じタブでの再読み込みで二重に数えないよう、`sessionStorage` のキー `otaku_src_counted` に `source:campaign:path` を保存し、同じなら呼ばない。`sessionStorage` は try/catch で囲み、使えなければそのまま1回呼ぶ。失敗は無視（既存と同じ `.then(() => {}, () => {})`）。管理画面では数えない（既存の判定に合わせる）。
3. `privacy.html` の「ページごとの閲覧回数」の項目を「ページごとの閲覧回数と、SNS など流入元ごとの閲覧回数（日別の合計のみ。…以下同じ）」に変え、改定日を 2026-10-26 にする。

#### L2. 投稿の直リンクと型の整理（`scripts/marketing/post.mjs`）
**実装完了（2026-10-26、Codex が利用上限のため運営者の指示で Claude が直接実装、ブランチ feat/sns-direct-links）**：テスト21件・`scripts/check.sh` OK。本番データの dry-run で A/B/C/E/H の Threads 文面・リンク・utm、X 文面が280以内であることを確認。
1. 公演取得の `select` に `group_id` と `otaku_idol_groups(id,name)` を含める（G 用のグループ取得は残す）。
2. リンク作成の関数 `postLink(post, template, source)` を追加し、`finish()` の `SITE_URL` をこれに置き換える：
   - 投稿に含まれる公演が1件 → `event.html?id=<公演id>`
   - 公演が複数でもグループが1つ → `index.html?group=<グループid>`（ホームは既に `?group=` で絞り込める）
   - それ以外 → トップ（`SITE_URL`）
   - 末尾に `utm_source=<threads|x>&utm_medium=social&utm_campaign=<テンプレート1文字>` を付ける。Instagram は従来どおり「プロフィールのリンクから見られます」で URL なし。
   - URL の直前の行に「全日程・参戦予定の登録はこちら👇」を入れる（D/E/F/G で既に同様の行がある投稿は重ねない）。
3. 新しい型 H「グループ特集」を追加：今後30日以内に公演があるグループを公演数の多い順に並べ、`jstDayNumber(now) % 件数` 番目のグループを選ぶ（状態を持たずに日替わり）。1行目 `🎯 <グループ名>の今後の公演`、2行目以降は最大5公演 `・<M/D(曜)> <会場>`、残りは「ほか○件」。リンクはそのグループのページ。`detectTemplate` は 1行目が `🎯 ` で始まり `の今後の公演` で終わるものを H と判定する。該当グループが無ければ A にフォールバック。
4. 選ぶ型を A・B・C・E・H に絞る：`TEMPLATES` を選択用の `ACTIVE_TEMPLATES = ['A','B','C','E','H']` と、判定・集計用の全体（A〜H）に分ける。`chooseTemplate` は `ACTIVE_TEMPLATES` だけから選ぶ（3回未満優先・80%最良・20%ランダムの規則は同じ）。D・F・G の文面作成コードは消さずに残す（`FORCE_TEMPLATE` で dry-run は可能なまま。`FORCE_TEMPLATE` の正規表現を `^[A-H]$` に）。成績表（`--report`）は A〜H 全部を出す。
5. 文字数：Threads 500字・X 280（重み付き）以内に収める既存の削り方（`fitPost`/`fitLines`/`fitX`）をリンク変更後もそのまま使う。

#### L3. レポートに流入元を出す（`scripts/marketing/report-data.mjs`）
`otaku_growth_stats` の `sources` をそのまま `report.json` の `site.sources` に入れる。週次レポートの指示文（`.github/workflows/growth-report.yml` の prompt）に「SNS からのサイト流入（source・テンプレート別）と前週比を表に入れる」を1行追加する。

#### テスト（`tests/marketing.test.cjs` に追加）
- 1公演だけの投稿 → リンクが `event.html?id=` で、`utm_source=threads` と `utm_campaign=<型>` が付く。X 文面は `utm_source=x`。
- 同じグループの複数公演 → `index.html?group=<id>`。複数グループ → トップ＋utm。
- Instagram 文面に URL が入らない。
- H：公演数の多いグループが選ばれ、1行目が `🎯 …の今後の公演`、`detectTemplate` が H を返す。公演が無ければ A になる。
- `chooseTemplate` が D・F・G を返さない（random を固定して数パターン）。
- 既存テストがすべて通る（文面の1行目は変えないので既存の判定は壊れない想定）。

#### 完了条件
- `node --test tests/marketing.test.cjs` と `bash scripts/check.sh` がすべてOK。
- dry-run（`FORCE_TEMPLATE` を A/B/C/E/H で実行）で、各文面のリンク先と utm が上の規則どおり。
- DB：dry-run（BEGIN〜ROLLBACK）で、許可外の source を渡すと行が増えない・`threads`/`B` で1行増える・anon でテーブルを直接読めないことを確認してから適用。
- 本番で `https://otaku-live-mvp.vercel.app/index.html?utm_source=threads&utm_campaign=B` を開くと `otaku_page_source_counts` に1件入り、再読み込みでは増えない。

#### 進め方
L1 の SQL（Codex が書く）→ Claude が dry-run・運営者確認のうえ適用 → L1 の画面と L2・L3（Codex、1ステップずつ）→ Claude が差分確認 → PR → マージ。
