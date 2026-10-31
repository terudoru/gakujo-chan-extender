# スターの複数端末共有（設計メモ）

状態: `star-sync` ブランチで実装済み（未リリース）。実装は `lib/src/star_sync/` と設定画面の「スターの端末間同期」です。S3 互換は SeaweedFS 3.80（SigV4 認証あり）、WebDAV は Apache httpd 2.4.62 の mod_dav（Basic 認証あり）で動作を確認済みです。

連絡通知のスターを、同じユーザーの複数端末で共有します。同期先のストレージは各ユーザーが用意し、More Better Gakujo 側ではサーバーを運用しません。アプリは利用者が入力した WebDAV または S3 互換ストレージへ、端末ごとに暗号化したファイルを置き、他端末のファイルを読み込んでマージします。

## 確定した仕様

- **同期先は WebDAV と S3 互換の両方に対応する。** WebDAV は Nextcloud、NAS、InfiniCLOUD などでURLとパスワードだけで始められます。S3 互換は Cloudflare R2、Backblaze B2、MinIO などを想定します。
- **端末ごとに1ファイルを書き、共有ファイルを上書きしない。** 条件付き書き込み（`If-Match`）は AWS S3 などでは使えますが、R2 と B2 は公式資料で対応を確認できませんでした。ヘッダーを黙って無視する実装があっても変更が消えないよう、書き込み競合そのものが起きない構成にします。
- **同期するのは ID と件名だけ。** 本文、送信者、ジャンル、期間、掲載日は端末内にだけ保存します。他端末で付いたスターは件名だけで表示し、メッセージを開いたときに既存の `refreshStarredMessage` で本文を補います。
- **パスフレーズによる暗号化を必須にする。** 件名にも人名や手続き内容が含まれうるため、同期先の管理者から中身を読めない状態にします。

## 同期先のファイル構成

利用者が指定したフォルダ（WebDAV のURL、または S3 のバケットとプレフィックス）の下に次を置きます。

```
<指定フォルダ>/more-better-gakujo/stars/
  keyring.json          共有の鍵情報（パスフレーズで包んだデータ鍵）
  devices/<deviceId>    端末ごとの暗号化ファイル
```

`deviceId` はインストールごとにランダム生成して端末内の安全な保存領域に置きます。バックアップには含めません。含めると、バックアップを復元した別端末が同じファイルに書き込み、単一書き込みの前提が崩れるためです。

## 端末ファイルの中身とマージ規則

暗号化前の中身は次の形です。

```json
{
  "schema": 1,
  "deviceId": "…",
  "writtenAt": "2026-10-31T12:00:00Z",
  "clock": 42,
  "stars": {
    "1|23|456": {
      "title": "…",
      "starred": true,
      "starredAt": "2026-10-30T09:00:00Z",
      "clock": 41,
      "deviceId": "…"
    }
  }
}
```

- **1件ごとに勝者を決める。** 同じ ID のレコードは `clock`（ランポート時計）が大きい方を採用し、同じ値なら `deviceId` の辞書順で決めます。端末の時計がずれていても結果が変わらないよう、壁時計の時刻は判定に使いません。
- **削除は削除マーカーとして残す。** スターを外したら `starred: false` のレコードを残し、他端末で復活しないようにします。マーカーは一定期間（案: 180日）後に消します。それより長くオフラインだった端末からは、外したスターが復活しうる点を許容します。
- **上限300件は全端末で同じ規則で切る。** マージ後、スター中のレコードを `starredAt` の新しい順に300件残します。端末ごとに別の基準で切ると、切ったスターが他端末から戻ってくるためです。
- **端末内の本文を消さない。** マージで変わるのはスター状態と件名だけです。勝者の件名が空なら端末内の件名を残します。
- **各端末は自分のマージ結果を書く。** 他端末の内容を取り込んだ状態で自分のファイルを書くので、使われなくなった端末のファイルが残っても害はありません。設定画面から古い端末のファイルを削除できるようにします。

`GakujoActivityStore` の既存操作との対応は次のとおりです。

| 既存操作 | 同期上の扱い |
|---|---|
| `toggleStarredMessage` / `upsertStarredMessage` / `removeStarredMessage` | 利用者の編集として `clock` を進める |
| `refreshStarredMessage`（詳細表示で中身を補う） | 端末内の補完なので `clock` を進めない |
| `replaceStarredMessages`（バックアップ復元） | 復元したスターは新しい編集として追加・更新し、バックアップにないスターは削除扱いにしない |
| `replaceStarredMessages(const [])`（データをすべて削除） | 先に同期を無効にし、空の一覧を他端末への削除として伝えない |

実装では各操作に同期処理を差し込まず、同期のたびに端末内のスター一覧と前回のマージ結果を比べて、この端末での追加・削除を導きます（`reconcileLocalStars`）。上限300件で端末内から押し出されたスターは、削除として扱いません。

## 同期の流れ

1. `devices/` を一覧する。
2. 前回から変わったファイルだけを取得する（ETag や更新日時を端末内に記録して比較）。
3. 復号して認証タグを検証し、失敗したファイルは無視してエラーとして記録する。
4. 端末内のスターとマージし、端末内の保存領域へ書き戻す。
5. 自分のファイルの内容が変わった場合だけ書き込む。

同期のきっかけは、起動時、アプリに戻ったとき、スターを付け外ししてから約5秒後、設定画面の手動同期です。通信に失敗しても端末内のスターが正本なので、操作はそのまま続けられます。設定画面には最終同期時刻と直近のエラーを表示します。

## 暗号化

- **データ鍵**: 256ビットのランダムな鍵で、端末ファイルを AES-256-GCM で暗号化します。追加認証データにはファイルのヘッダーと `deviceId` を入れ、ファイル名の付け替えを検出します。
- **keyring.json**: パスフレーズから Argon2id で作った鍵でデータ鍵を包んで保存します。KDF のパラメータ、ソルト、鍵ID（`keyId`）を平文で持ちます。
- **新しい端末の参加**: 接続設定とパスフレーズを入力し、`keyring.json` からデータ鍵を取り出します。取り出したデータ鍵は端末内の安全な保存領域に置き、パスフレーズ自体は保存しません。
- **最初の端末**: `keyring.json` がなければ作成します。2台が同時に作成した場合に備え、作成後に読み直し、別の鍵があればそちらを採用してから端末ファイルを書きます。
- **パスフレーズの変更**: データ鍵を包み直して `keyring.json` だけを書き換えます。端末ファイルは作り直しません。
- **パスフレーズを忘れた場合**: 同期データは復元できません。同期をリセットして同期先の `stars/` を作り直します。端末内のスターは残るため、リセット後に再び共有できます。設定画面にこの点を明記します。

## 接続方式ごとの実装

どちらの方式も Dart 標準の `dart:io` の `HttpClient` を使い、HTTP用の依存パッケージは追加しません。接続情報は `FlutterSecureStorage` に保存し、バックアップには含めません。HTTPS 以外の接続は受け付けません。同期先は学情や大学関連ホスト向けの `AllowedWebOrigins` に含まれないため、同期用のクライアントは許可リストを広げず、設定で入力されたホストにだけ接続します。

- **WebDAV**: URL、ユーザー名、パスワード（アプリパスワード推奨）。`PROPFIND`（Depth: 1）で一覧し、`GET`、`PUT`、`MKCOL` を使います。
- **S3 互換**: エンドポイント、リージョン（R2 は `auto`）、バケット、プレフィックス、アクセスキー、シークレット、パス形式URLの切り替え（MinIO・R2向け）。署名 SigV4 は既存の `crypto` パッケージの HMAC-SHA256 で実装し、`ListObjectsV2`、`GetObject`、`PutObject` を使います。案内では、そのバケットとプレフィックスに限定したキーの作成を勧めます。

## 実装時に決めたこと

- **暗号ライブラリ**: 純粋な Dart 製の `cryptography` を使います（XML の解析には `xml`）。Argon2id（19 MiB・2回）は開発機の `flutter test` で鍵の作成が約0.14秒、取り出しが約0.09秒でした。UI を止めないよう別 isolate で実行します。モバイル実機での時間は未計測です。
- **アカウントの取り違え防止**: 保存済みのログインIDから作ったハッシュを、暗号化した端末ファイルに入れます。両方に値があって一致しない端末ファイルは、マージに使いません。ログインIDを保存していない端末では確認しません。

## 未決事項

- **削除マーカーの保持期間**: 180日は暫定値です。
- **実サービスでの確認**: S3 互換は、ローカルの SeaweedFS 3.80 を相手に `test/star_sync_live_s3_test.dart` の5シナリオ（2台での追加・削除・付け直し、誤ったパスフレーズ、パスフレーズ変更、リセット後の再接続、保存ファイルの暗号化）が通りました。WebDAV は、ローカルの Apache httpd 2.4.62（mod_dav）を相手に `test/star_sync_live_webdav_test.dart` の同じ5シナリオと、誤ったパスワードでの設定失敗が通りました。末尾に `/` のないコレクションURLに 301 を返すサーバーでも、一覧取得とフォルダ作成が動くことを確かめています。どちらのテストも `STAR_SYNC_LIVE_S3_ENDPOINT` や `STAR_SYNC_LIVE_WEBDAV_URL` などの環境変数を設定したときだけ動きます。Nextcloud・InfiniCLOUD などの WebDAV サービスや、Cloudflare R2・AWS S3 などのクラウドサービスでは未確認です。MinIO はコミュニティ版のコンテナイメージを取得できず、試せませんでした。

## 検証方針

- マージの単体テスト: 適用順を変えても結果が同じこと、削除マーカー、上限300件での収束、時計ずれ、空の件名の扱い。
- 通信層のテスト: `dart:io` の `HttpServer` で WebDAV と S3 の最小限の偽サーバーを立て、一覧・取得・書き込み・SigV4 署名・エラー応答を確認します。
- 実環境での確認: WebDAV は Nextcloud または InfiniCLOUD、S3 互換は R2 と MinIO で、2台の端末間の追加・削除・オフライン後の復帰を確認します。

## 参考

条件付き書き込みの対応状況の確認に使った資料です。

- [AWS S3 conditional writes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.md)
- [Servercore conditional requests](https://docs.servercore.com/s3/objects/conditional-requests/)
- [Scaleway conditional writes](https://www.scaleway.com/en/docs/object-storage/api-cli/using-conditional-writes/)
- [CoreWeave conditional requests](https://docs.coreweave.com/products/storage/object-storage/buckets/conditional-requests.md)
- [Cloudflare R2 runtime APIs](https://cloudflare-docs-siq.pages.dev/r2/runtime-apis)
- [multistore issue #120](https://github.com/developmentseed/multistore/issues/120)（S3互換の経路で `If-Match` が無視された事例）

## Google ドライブ同期のための OAuth クライアント設定

- Google Cloud で External の同意画面を作成し、`drive.appdata`、`openid`、`email` を設定して本番公開します。`drive.appdata` は非機密スコープです。
- Desktop クライアントを作成し、Windows/macOS のビルド時に ID とシークレットをそれぞれ `--dart-define=GOOGLE_OAUTH_DESKTOP_CLIENT_ID=...`、`--dart-define=GOOGLE_OAUTH_DESKTOP_CLIENT_SECRET=...` で渡します。
- Android クライアントはパッケージ `net.yoshida.morebettergakujo` と、リリース用・デバッグ用それぞれの署名鍵の SHA-1 で登録します。
- iOS クライアントはバンドル ID `net.yoshida.morebettergakujo` で作成し、ID を `--dart-define=GOOGLE_OAUTH_IOS_CLIENT_ID=...`、逆順 ID をビルド設定 `GOOGLE_REVERSED_CLIENT_ID` に指定します。
