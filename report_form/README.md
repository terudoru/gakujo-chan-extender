# GitHub アカウント不要の報告フォーム

More Better Gakujo の不具合と要望を受け付ける Cloudflare Worker です。フォームから送った内容は D1 に非公開で保存します。開発者は Cloudflare Access で保護した `/dashboard/` で確認します。

「GitHub で Issue を作る」は、公開欄を入力した GitHub の新規 Issue 画面を開きます。開発者が内容を確認・編集し、GitHub 上で投稿します。Worker は GitHub の認証情報を持たず、Issue を投稿しません。

## 保存する内容と公開する内容

- D1 には種類、件名、内容、問題が起きるまでの手順、本来どうなってほしかったか、バージョン、OS、任意の診断情報、受付時刻、確認状態、関連 Issue 番号を保存します。フォームで個人情報を入力しないよう案内します。
- 診断情報は管理画面でだけ表示します。Issue 用のリンクとコピーには、件名と公開欄だけを渡します。`@` の直後にゼロ幅スペースを入れて、意図しないメンションを防ぎます。URL が6,000文字を超える場合は本文を省略します。コピーでは公開本文全体を取得できます。
- 報告は180日後に削除対象になります。毎時の処理で削除するため、最大1時間の差があります。`REPORT_RETENTION_DAYS` で変更できます。管理画面の「削除」では診断情報も含めて削除します。GitHub に投稿済みの Issue は削除しません。D1 の復元用バックアップには Cloudflare 側の保持期間が別に適用されます。
- 生の IP アドレスは保存しません。Turnstile の検証時だけ Cloudflare に送ります。送信制限にはソルト付き SHA-256 ハッシュを使い、IPv6 は `/64` 単位でまとめます。ハッシュは1日後に削除対象になり、毎時削除します。報告との対応表は作りません。

同じ IP の送信は直近10分で3件、直近24時間で10件までです。全体で直近24時間200件まで受け付けます。日付が変わる瞬間の集中を防ぐため、1日はローリング24時間で数えます。制限の確認と報告の保存は D1 の同じトランザクションで行います。

## ローカルで動かす

Node.js 22.13 以降が必要です。CI は Node.js 24 を使います。以下はすべて `report_form/` で実行します。

```sh
npm ci
npm test
cp .dev.vars.example .dev.vars
npm run db:migrate:local
npx wrangler dev --local --ip 127.0.0.1 --port 8787
```

Windows PowerShell では `cp` の代わりに `Copy-Item .dev.vars.example .dev.vars` を使えます。`http://localhost:8787/?type=bug&version=1.2.3&platform=windows` を開いて確認します。`type=request` なら要望が選ばれます。`platform` は `windows`、`macos`、`linux`、`android`、`ios`、`other` に対応します。

`.dev.vars.example` は Cloudflare の公開テストキーとローカル用ソルトです。本番に使わないでください。[Cloudflare のテストキー](https://developers.cloudflare.com/turnstile/troubleshooting/testing/)は hostname に `example.com` を返し、`action` は返しません。この Worker は `action=report` と hostname を厳密に確認するため、テストキーの実レスポンスは400で拒否します。送信成功は通信を置き換えたテストで確認し、実キーでの確認は管理者の本番設定後に行います。テストのために本番の検証を緩めないでください。

`DEV="true"` とループバックホストの両方が成立する場合だけ、未設定の `SITE_ORIGIN` をリクエスト先の origin で補えます。それでも Origin ヘッダーは必須です。本番設定では `DEV` を指定しません。テストは実際のマイグレーションを `node:sqlite` に適用し、Turnstile と Access の通信をスタブに置き換えます。Miniflare の実 Worker とローカル D1 でも、siteverify だけをテスト専用の `outboundService` に置き換えて201・保存・送信制限を確認します。GitHub や Cloudflare の管理 API は呼びません。

`wrangler.jsonc` の D1 `database_id` は未設定です。ローカルの D1 は ID なしで使えます。本番では次の手順で ID を設定してください。秘密値は `.dev.vars` または Wrangler のシークレットに置きます。`.dev.vars` と `.wrangler/` は Git の対象外です。

## 初回の本番設定

作業対象は Worker `gakujo-report`、D1 `gakujo-reports`、ホスト `gakujo-report.terudoru.com` です。Cloudflare の対象アカウントを確認してから進めてください。この手順は管理者が行います。CI はテストだけを実行し、デプロイしません。

1. `npx wrangler d1 create gakujo-reports` を実行します。出力された `database_id` を `wrangler.jsonc` の `d1_databases[0]` に設定します。
2. `npm run db:migrate:remote` で本番 D1 にテーブルを作ります。
3. Cloudflare で `gakujo-report.terudoru.com` 用の Turnstile ウィジェットを作ります。サイトキーを `TURNSTILE_SITE_KEY` に設定し、`TURNSTILE_HOSTNAMES` は `gakujo-report.terudoru.com` にします。`npx wrangler secret put TURNSTILE_SECRET` で秘密キーを登録します。ローカルホストやテストキーを本番設定に加えないでください。
4. 十分に長いランダムな値を秘密情報の保管先で作り、`npx wrangler secret put IP_HASH_SALT` で登録します。秘密値をコマンド引数や Git に残さないでください。
5. Cloudflare Access に self-hosted アプリを作ります。`gakujo-report.terudoru.com/dashboard` とその配下、`gakujo-report.terudoru.com/api/dashboard` とその配下を同じアプリで保護します。両パスに開発者本人だけを許可するポリシーを適用します。チームドメイン（例 `your-team.cloudflareaccess.com`、`https://` なし）を `ACCESS_TEAM_DOMAIN` に、アプリの Audience タグを `ACCESS_AUD` に設定します。別々のアプリに分けると Audience が異なるため、同じアプリの複数パスとして登録してください。
6. Worker のカスタムドメインとして `gakujo-report.terudoru.com` を追加します。Wrangler で管理する場合は `routes` に `{ "pattern": "gakujo-report.terudoru.com", "custom_domain": true }` を追加します。`SITE_ORIGIN` が `https://gakujo-report.terudoru.com`、`ISSUE_REPO` が `terudoru/gakujo-chan-extender` であることも確認します。
7. `npm test` を実行してから `npm run deploy` でデプロイします。Access 未ログインで管理画面と管理 API が開けないこと、許可した管理者では開けること、フォームの受付と非公開欄の分離を確認します。`workers_dev` とプレビュー URL は無効のままにします。
8. GitHub の対象リポジトリに `from-form` ラベルを作ります。`bug` と `enhancement` も存在することを確認します。試しに Issue 作成画面を開き、診断情報が含まれていないことを確認します。画面を開くだけでは投稿されません。

設定や必須シークレットが欠けた場合、送信は503で拒否します。Access の設定がない場合も管理画面を開きません。署名、issuer、audience、有効期限を Worker 内でも検証します。管理操作には同じ origin と JSON を要求します。

## 費用と運用

Workers・D1・Turnstile の無料枠内で運用する想定です。Cloudflare Access も利用人数とプランの条件を確認してください。利用量や料金条件が変われば無料枠を超える可能性があるため、Cloudflare の利用状況を確認してください。

参考: [Workers Static Assets のルーティング](https://developers.cloudflare.com/workers/static-assets/routing/worker-script/)、[D1 batch](https://developers.cloudflare.com/d1/worker-api/d1-database/)、[Access JWT の検証](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/)、[Turnstile のサーバー検証](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/)。Wrangler は公開から2週間以上経過した `4.156.2`（2026-11-02公開）に固定しています。
