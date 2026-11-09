# リリース手順

GitHub Releases に配布ファイルを出すメンテナー向けの資料です。開発環境とビルドの基本は [development.md](development.md) にあります。

## まず覚えること

1. `pubspec.yaml` の `version` とタグ（`vX.Y.Z`）を一致させ、そのコミットを main に入れてからタグを push する
2. タグの push で、Android・macOS・Windows・Linux の配布ファイルが1つのリリースにまとめて公開される
3. iOS/iPadOS 版は、あとから `release_scope: ios` で同じリリースに追加する
4. Android の署名鍵と4つの Repository secrets がないと、Android のジョブは失敗する

## リリースの流れ

`.github/workflows/release.yml`（workflow 名は `Release macOS Windows Linux Android`）が、`v*` のタグの push か手動実行で動きます。

1. `verify_release` が、タグのコミットが main に含まれていること、タグと `pubspec.yaml` の版が一致していることを確かめる
2. `android`、`macos`、`windows`、`linux` の4つのジョブが、それぞれビルドと検証をする
3. `publish_all` が、`scripts/staged_release.py all dist` で4つのプラットフォームの配布ファイルを1つのリリースに公開する。リリースノートでは、iOS/iPadOS は「デバッグ完了後に追加予定」と表示される

配布ファイルの名前は `MoreBetterGakujo-vX.Y.Z` にそろえます。

| ジョブ | 配布ファイル | ジョブの中で確かめること |
|---|---|---|
| `android` | `.apk` | `flutter analyze`、Windows と Android の境界のテスト、APK の署名と版の番号（versionCode は 71 より大きいこと） |
| `macos` | `.dmg` | macOS のキーチェーンのテスト、`flutter test`、アプリの構成と起動 |
| `windows` | `.exe`（インストーラー）、`.zip`（ポータブル版） | インストーラーで旧版から更新できること |
| `linux` | `-linux-x64.tar.gz`、`-linux-amd64.deb` | パッケージの内容、deb のインストール、実行ファイルとライブラリの依存関係 |

アプリの更新通知は、配布ファイルの拡張子で自分の OS 向けのファイルがあるかを判断するので、拡張子を変えるときは `AppUpdateInfo.hasInstallerFor` も直す。iOS 版は IPA を追加した時点で通知される。

macOS の DMG は Developer ID で署名していません。利用者は初回に「プライバシーとセキュリティ」で「このまま開く」を選びます。

### iOS/iPadOS 版をあとから追加する

1. `Release macOS Windows Linux Android` を手動で実行する
2. `tag_name` に既存のタグ、`release_scope` に `ios`、`platform_commit` に main にある検証済みのコミットの完全な SHA を入れる
3. `ios` ジョブが未署名の IPA を作り、`publish_ios` が `staged_release.py ios dist` で既存のリリースに追加する
4. タグが `-beta.1` のようなプレリリースでなければ、`publish_ios` が `distribution/altstore-source.json` を作り直して main にコミットする

`platform_commit` は、タグのコミットの子孫で、版の番号がタグと一致している必要があります。

### そのほかの workflow

| workflow | 動くとき | 用途 |
|---|---|---|
| `Cross-platform Flutter`（`cross-platform.yml`） | PR、main への push、手動 | Android・Apple・Windows・Linux でテストまたはビルドをする。署名していない iOS の `.app` を `ios-debug-app`、macOS の `.app` を `macos-debug-app` として Artifacts に残す |
| `Windows x64 Release Artifact`（`windows-x64-artifact.yml`） | PR、手動 | Windows のリリースビルドを Artifacts に残す |
| `Release Windows Installer`（`release-windows-installer.yml`） | 手動（タグを指定） | 既存のリリースに Windows のインストーラーを出し直す |
| `Check Android release signing`（`check-android-signing.yml`） | 手動 | 公開済みの APK の署名を調べる。必要ならタグから APK を作り直して調べる |
| `CodeQL Advanced`（`codeql.yml`） | main への push、PR、毎週 | コードの静的解析 |

`Cross-platform Flutter` と `Windows x64 Release Artifact` は、GitHub Release を公開しません。

## Android の署名

- ローカルに `android/key.properties` がなければ、リリースビルドはデバッグ署名になる
- CI では、`android/key.properties` がないとリリースビルドがエラーになる。デバッグ署名の APK を公開しないため
- APK を上から更新するには、同じ署名鍵が要る。署名鍵が変わると、利用者は古いアプリをアンインストールしてから入れ直すことになる（v0.68.0 以前と以降で、すでに一度変わっている）

ローカルでリリースビルドに署名するには、次の内容で `android/key.properties` を作ります。このファイルは git の管理外です。

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
```

`android/upload-keystore.jks` と `android/key.properties` は、必ずバックアップを取っておいてください。

### GitHub Actions の secrets

リポジトリの `Settings` → `Secrets and variables` → `Actions` に、次の Repository secrets を登録します。リリース workflow は、この値から `android/upload-keystore.jks` と `android/key.properties` を作ります。

| secret | 中身 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `upload-keystore.jks` を base64 にしたもの |
| `ANDROID_KEYSTORE_PASSWORD` | キーストアのパスワード |
| `ANDROID_KEY_ALIAS` | リリースの署名に使う鍵のエイリアス |
| `ANDROID_KEY_PASSWORD` | リリースの署名に使う鍵のパスワード |

macOS では、キーストアのあるディレクトリで次のコマンドを実行し、出力の全体を `ANDROID_KEYSTORE_BASE64` に登録します。

```sh
base64 -i upload-keystore.jks
```

## iOS/iPadOS の配布

App Store では配布せず、利用者が自分の Apple Account で署名する前提で、未署名の IPA を配ります。利用者向けの手順と注意は [README](../README.md) の「iOS/iPadOS」にあります。

- Bundle ID は `net.yoshida.morebettergakujo` に固定する。変えると、Sideloadly と SideStore は別のアプリとして扱う
- 対象は iOS/iPadOS 14 以降
- SideStore の source は、`distribution/altstore-source.json` を raw の URL で案内する。source の `downloadURL` は、GitHub Releases の IPA の URL に合わせる

```text
https://raw.githubusercontent.com/terudoru/gakujo-chan-extender/main/distribution/altstore-source.json
```

### IPA と source を手で作る

ふだんはリリース workflow が作ります。検証や、workflow が使えないときの手段として残しています。Xcode と Flutter の入った macOS で実行します。

```sh
./scripts/package_ios_ipa.sh
./scripts/generate_altstore_source.sh dist/MoreBetterGakujo-vX.Y.Z.ipa
```

- `package_ios_ipa.sh` は、`pubspec.yaml` の版から `dist/MoreBetterGakujo-vX.Y.Z.ipa` を作る。出力先は環境変数 `OUTPUT_PATH` で変えられる
- `generate_altstore_source.sh` には、環境変数 `RELEASE_TAG` と `RELEASE_NOTES` を渡せる
- 手で作った source は、公開する IPA に合わせて `size`、`version`、`buildVersion`、リリースノートを確かめてからコミットする

## Linux のパッケージ

リリース workflow は Ubuntu 22.04 コンテナーで Linux x64 のビルドと deb のインストール検証を行います。手元では `flutter build linux --release` のあとに `bash scripts/package_linux.sh` を実行すると、`dist/` に tar.gz と deb を作ります。出力先は `OUTPUT_DIR`、タグは `RELEASE_TAG` で変えられます。

deb はアプリを `/opt/morebettergakujo/` に配置し、`/usr/bin/morebettergakujo` のリンク、`/usr/share/applications/` のデスクトップ項目、`/usr/share/icons/hicolor/` のアイコンを登録します。

## Windows のインストーラー

`distribution/windows/morebettergakujo.iss` が Inno Setup の定義です。リリース workflow では CI が版の番号と出力先を渡します。手元で作るときは、Windows でリポジトリのルートから次を実行します。

```powershell
flutter build windows --release
.\scripts\package_windows_inno.ps1
```

`ISCC.exe distribution\windows\morebettergakujo.iss` で直接コンパイルもできます。出力先は `dist\windows\` です。

インストーラーの動きは次のとおりです。

- アプリを `Program Files` に入れ、スタートメニューの項目とアンインストーラーを登録する。デスクトップのショートカットは任意
- 更新は Inno Setup の通常の上書き更新で行う。前の版のアンインストーラーを管理者権限で動かすことはしない
- 利用者ごとのアプリのデータは、`%AppData%` のようにインストール先の外に置く

### 更新時の古いファイルの削除

- 既定のインストール先では、入れたファイルのパスと SHA-256 を記録する
- 次の更新で、前の版が入れたファイルのうち、新しい版にはなく、中身が変わっていないものだけを消す。変更されたファイルと、記録にないファイルは残す
- 記録のない版からの最初の更新で消せるのは、既知の古いデバッグ用のファイルだけ。それ以外の古いファイルは安全に見分けられない
- インストール先を変えた場合は、自動の削除をしない。ディレクトリの権限によっては、管理者権限での更新中に、信頼できない利用者がファイルを書き換えられるため

## Google OAuth クライアント

端末間同期の「Google ドライブで同期」と、ダウンロードの Google ドライブ保存に使います。クライアント ID を組み込まないビルドでは、このボタンは出ず、WebDAV/S3 だけが選べます。リリース workflow は Repository secrets の `GOOGLE_OAUTH_DESKTOP_CLIENT_ID`、`GOOGLE_OAUTH_DESKTOP_CLIENT_SECRET`、`GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID`、`GOOGLE_OAUTH_IOS_CLIENT_ID` から dart-define ファイルと、iOS 用の `GoogleOAuth.xcconfig` を作ります。必要な secret がなければリリースは失敗します。

1. Google Cloud で External の同意画面を作り、下の「本番公開の手順」に従って本番として公開する。ダウンロードの Google ドライブ保存は、使うときに `drive.file` を追加で求める
2. Desktop クライアントを作り、Windows/macOS/Linux のビルドで `--dart-define=GOOGLE_OAUTH_DESKTOP_CLIENT_ID=...` と `--dart-define=GOOGLE_OAUTH_DESKTOP_CLIENT_SECRET=...` を渡す。インストール型アプリのシークレットは、Google の扱いでも機密ではない
3. Android クライアントを、パッケージ `net.yoshida.morebettergakujo` と、リリース用とデバッグ用の署名鍵の SHA-1 で登録する。Android クライアントの ID はアプリに渡さない
4. 同じプロジェクトに Web クライアントを作り、その ID を Android のビルドで `--dart-define=GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID=...` として渡す
5. iOS クライアントを Bundle ID `net.yoshida.morebettergakujo` で作り、ID を `--dart-define=GOOGLE_OAUTH_IOS_CLIENT_ID=...` で渡す
6. iOS の逆順のクライアント ID を、git で追跡しない `ios/Flutter/GoogleOAuth.xcconfig` に `GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.<id>` と書く。追跡しているほうの xcconfig は編集しない。このファイルがなければ、ダミーの `com.googleusercontent.apps.unset` が使われる

クライアント ID は配布するアプリに入るので、誰でも取り出せます。そのため、Drive API を意図して使い込まれるのを端末側では防げません。Google Cloud のプロジェクトには課金アカウントを付けず、コンソールで設定できるなら、無料枠より低い割り当ての上限を設定してください。端末ごとの利用量の上限は [star-sync.md](star-sync.md) の「Drive API の上限への対策」にあります。

### 本番公開の手順

1. リポジトリの Settings → Pages で Source を「GitHub Actions」にし、Custom domain に `gakujo.terudoru.com` を設定して、pages workflow で `site/` を公開する。Cloudflare の DNS には `gakujo` から `terudoru.github.io` への CNAME を「DNS のみ」で追加する（プロキシを有効にすると GitHub の HTTPS 証明書が発行されないことがある） `site/index.html` は `https://terudoru.com/apps/more-better-gakujo-flutter` へ転送するだけで、アプリの説明はそのページで管理する。プライバシーポリシーは `site/privacy.html` のまま公開する
2. 承認済みドメインには `terudoru.com` を登録する。所有確認は Search Console のドメインプロパティ `terudoru.com` で行い、案内された TXT レコードを Cloudflare の DNS に追加する。確認する Google アカウントは Cloud プロジェクトのオーナーか編集者にする。`terudoru.github.io` のままでは、Search Console で所有権を確認していてもブランドの確認が「ウェブサイトが登録されていません」で通らなかった
3. Google Auth Platform のブランディングに、アプリ名、サポートメール、ホームページ `https://gakujo.terudoru.com/`、プライバシーポリシー `https://gakujo.terudoru.com/privacy.html`、承認済みドメインを入力する
4. データアクセスに `openid`、`email`、`drive.appdata`、`drive.file` を登録する（いずれも非機密のスコープ）
5. 対象を「本番環境」に公開し、ブランドの確認を申請する

テスト中のままだと、登録したテストユーザー（最大100人）しかログインできず、更新トークンは7日で失効します。
