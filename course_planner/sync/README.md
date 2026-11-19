# 履修プランナーを自分の端末間で同期する

各端末で同じプランナーの同期画面を開き、同じ同期先とペアリングコードで接続する。接続直後は両方の項目がオフになっている。「候補リストと時間割」をオンにすると、その端末で保存したリストと履修予定を同期先のデータと統合する。「履修履歴と成績」は別に選べる。履歴には修得科目、本人が確認したシラバスとの対応、認定・重複の扱い、区分別単位、所属とGPAを含む。

## 本人専用サーバーで使う

Node.js 24 と、各端末で開ける HTTPS のプランナーが必要。鍵の初期化は自分の端末で行う。例ではリポジトリの隣に、本人だけが読めるフォルダー `planner-private` を用意し、リポジトリのルートで実行する。`relay-data` と `planner-recovery.txt` は新規に作られる。

```sh
node course_planner/sync/relay.mjs init ../planner-private/relay-data ../planner-private/planner-recovery.txt
```

`planner-recovery.txt` は本人が各端末に入力する43文字のコード。安全な場所に保管する。サーバーには `relay-data` だけを移す。次の最後の引数はプランナーを開くオリジン。異なるオリジンのアプリも使う場合はスペース区切りで追加する。

```sh
node course_planner/sync/relay.mjs serve ../planner-private/relay-data https://planner.example
```

サーバーは `127.0.0.1:8788` で待ち受ける。別端末から接続するときは、本人管理の HTTPS リバースプロキシからこのポートへ転送する。同期画面の「同期サーバーのURL」にはプロキシのベースURLを指定する。任意のサブパスに設置する場合は、その下の `/v1/` をリレーの `/v1/` へ転送する。同じPCのブラウザで試す場合は、起動時にローカルのプランナーのオリジンを指定し、同期画面に `http://127.0.0.1:8788` を入力できる。待受ポートは `PLANNER_RELAY_PORT` で変更できる。

## Google ドライブで使う

サイト管理者が、プランナーのオリジンを登録した Web 用の公開 OAuth クライアント ID を `VITE_PLANNER_GOOGLE_CLIENT_ID` に設定してビルドすると、同期先に Google ドライブが表示される。Drive API を有効にしたプロジェクトを使う。初めて接続する端末で「新しいコードを作成」を押し、コードを控えてから Google に接続する。ほかの端末では同じコード・アカウントを選ぶ。

ブラウザ版は GIS のトークンモデルを使い、要求するスコープは `drive.appdata` のみ。Drive が返す本人の `permissionId` に接続を結び付ける。アクセストークンはメモリ内に保持する。ページを開き直したときやトークン期限後は「Googleに再接続」を押す。[Google のトークンモデル](https://developers.google.com/identity/oauth2/web/guides/use-token-model)・[Drive のアプリ専用領域](https://developers.google.com/workspace/drive/api/guides/appdata)・[about.get](https://developers.google.com/workspace/drive/api/reference/rest/v3/about/get)

## 編集の競合と接続解除

リスト名、各リストの授業、時間割の選択、履修履歴の各行は個別に統合する。同じ項目を同時に編集した場合は、観測済みの更新回数と端末IDで優先順位を決める。削除も更新として記録する。別々の端末で同時に選んだ授業のコマが重なる場合は、同期画面で授業を確かめて外せる。端末がオフラインの間の編集は再接続後に取り込む。画面を開いている間は編集後・オンライン復帰時・定期的に確認する。

項目をオフにするとその端末での新しい送受信を止め、処理中の応答を破棄する。接続解除で端末の同期鍵を削除する。すでに送信したデータや各端末のプランナーの内容は残る。データは同期先に暗号化した変更履歴として蓄積する。持ち主が同期領域全体を廃棄する場合は、先にすべての端末で接続を解除する。

## プランナーとの接続と検証

`src/sync/SyncPanel.jsx` の名前付き export `SyncPanel` を App から常時マウントする。props は `state`、React の `setState`、`catalog`、設定画面のときだけ true にする `visible`。表示中のページに関わらず、同期は App と同じ `loadLocal/changeLocal` を使う。ローカル保存形式では `plannerSync` が更新の世代・削除・送信待ちを保持する。ストレージの正規化ではこのプロパティを保つ。共有リンクは既存の `snapshot()` の許可項目だけで作る。

下のコマンドは合成データで Chrome の独立した2つのコンテキストと一時リレーを起動する。Chrome のチャンネルは `CHROME_CHANNEL` で選べる。

```sh
npm --prefix course_planner ci
npm --prefix course_planner test
node course_planner/tools/check-planner-sync.mjs
```
