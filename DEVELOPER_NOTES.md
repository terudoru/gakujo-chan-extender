# 開発者向けメモ

このリポジトリは、新潟大学の学務情報システムを Flutter の WebView で使うための
クロスプラットフォームアプリです。More Better Gakujo / Gakujo-chan-extender 系の
アイデアを Android アプリとして移植したものを、iOS/iPadOS、Windows、macOS へ
広げています。

## 現在のアプリに含まれる主な機能

- ローカルに保存したBase32秘密鍵から2段階認証コードを生成し、自動入力する
- 2段階認証、ダウンロード動作、モバイル版/デスクトップ版の表示モードを設定する
- ダウンロード保存モードを選ぶ
  - 科目ごとに自動仕分けして、指定フォルダに保存する
  - 自動仕分けせず、指定フォルダに保存する
  - 自動仕分けせず、毎回保存場所を選ぶ
- リンク、フォーム、ボタン経由の学務情報システム内ダウンロードを捕捉する
- 授業連絡、レポート・小テスト・アンケート提出画面、科目情報テーブル、
  ファイル名などから科目名を推定する

Android リリースAPKは次の場所に出力されます。

```text
build/app/outputs/flutter-apk/app-release.apk
```

## ライセンスと上流プロジェクト

このアプリは、ブラウザ拡張機能リポジトリのGitHubフォークとしてではなく、
独立したリポジトリとして公開しています。

主な上流プロジェクト:

- https://github.com/koji-genba/gakujo-chan-extender

関連するフォーク:

- https://github.com/yangniao23/gakujo-chan-extender

再配布や大きな改変を配布する場合は、このリポジトリの `LICENSE.md` と
`NOTICE.md` を含めてください。

## セットアップ

Flutterをインストールしたあと、依存関係を取得します。

```sh
cd morebettergakujo-flutter
flutter pub get
```

Dart側のコードがアプリ本体の実装です。Android/iOS/macOS/Windows のランナーを
含みます。Apple プラットフォームではローカルの Xcode と CocoaPods、Windows では
Windows ホストと WebView2 Runtime が必要です。

## 確認コマンド

```sh
flutter test
flutter analyze
flutter run -d android
flutter build apk --release
./android/gradlew -p android bundleRelease
flutter build ios --debug --no-codesign
flutter build macos --debug
flutter build windows --debug
```

出力先:

- リリースAPK: `build/app/outputs/flutter-apk/app-release.apk`
- デバッグAPK: `build/app/outputs/flutter-apk/app-debug.apk`
- リリースAAB: `build/app/outputs/bundle/release/app-release.aab`
- macOSアプリ: `build/macos/Build/Products/Debug/More Better Gakujo.app`
- Windowsアプリ: `build/windows/x64/runner/Debug/morebettergakujo_flutter.exe`

iOS/iPadOS の自己署名配布では、GitHub Releases に
`morebettergakujo-ios.ipa` をアップロードします。Sideloadly 向けにはIPAを直接渡し、
SideStore 向けには `distribution/altstore-source.json` を公開します。
ローカルでIPAを作る場合は次のコマンドを使います。

```sh
./scripts/package_ios_ipa.sh
./scripts/generate_altstore_source.sh dist/morebettergakujo-ios.ipa
```

GitHub Releases へ出す場合は、`Release iOS Sideload IPA` workflow がIPAと
`altstore-source.json` を同じリリースへアップロードします。

詳しい運用は [docs/ios-sideloading.md](docs/ios-sideloading.md) を参照してください。

`flutter build windows` は Windows ホストでのみ実行できます。macOS/iOS ビルドは
`xcode-select` がフル Xcode を指している必要があります。Command Line Tools のみを
指している環境では `xcrun xcodebuild` が失敗します。

ローカルに秘密鍵ストアがない場合、リリースビルドはデバッグ署名にフォールバック
します。Play Store向けのAABを作る場合は、ローカルに
`android/key.properties` を作成してください。

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
```

`android/key.properties` はgit管理外です。

`android/upload-keystore.jks` と `android/key.properties` は必ずバックアップして
ください。APKの更新には同じ署名鍵が必要です。署名鍵が変わると、利用者は古い
アプリをアンインストールしてから新しいAPKを入れる必要があります。

次のファイルはコミットしないでください。

- `android/upload-keystore.jks`
- `android/key.properties`
- `android/local.properties`

## Androidのローカル2段階認証QA

エミュレータを起動した状態で実行します。

```sh
flutter build apk --debug
./scripts/flutter_android_local_2fa_qa.sh
```

このQAスクリプトはデバッグAPKをインストールし、デバッグビルド限定の
`file:///android_asset/qa/two_factor.html` を開きます。その後、Androidの
Intent extra経由でテスト用Base32秘密鍵を注入し、6桁コードをlogcatに出さずに
自動入力と送信が行われることを確認します。

スクリーンショット、UI XML、logcatは `build/qa/` 以下に出力されます。

## 移植した主な挙動

- `https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do` を開く
- `https://gakujo.iess.niigata-u.ac.jp/*` 以外への遷移をブロックする
- デバッグビルドでは、ローカルQA用に `file:///android_asset/qa/*` のみ追加で許可する
- 6桁のワンタイムコードではなく、長いBase32秘密鍵だけを保存する
- `flutter_secure_storage` を使って、AndroidではKeystore、iOSではKeychainに保存する
- Dartで6桁のTOTPコードを生成する
- 許可済みページの読み込み後にJavaScriptを注入し、
  `input[name="ninshoCode"]` を見つけて入力・送信する
- Androidでは利用者がダウンロード保存先フォルダを選べる
- 選択された保存モードに従って学務情報システムのダウンロードを保存する
- ページ内の「科目名」欄や表から科目名を検出する
- ページから科目名を取れない場合は、ファイル名のパターンから推定する

## クロスプラットフォーム移植メモ

アプリ本体のコードは Android 専用 API に寄せすぎないようにしています。
プラットフォーム分岐は `lib/src/platform/platform_service.dart` を入口にし、
WebView とダウンロード処理を抽象化しています。

- Android は既存の MethodChannel ダウンロード処理を使います。
- iOS/iPadOS は Dart でファイルを取得し、ネイティブブリッジで Files の
  フォルダ選択またはファイル書き出しへ渡します。フォルダ選択には iOS/iPadOS 14
  以降が必要です。
- macOS は `webview_flutter` と Dart ダウンロード処理を使います。Sandbox で
  `network.client` と user-selected read/write entitlement を付与し、保存先フォルダは
  ネイティブブリッジで security-scoped bookmark として保持します。
- Windows は `webview_windows` と Dart ダウンロード処理を使います。実行環境には
  Microsoft Edge WebView2 Runtime が必要です。

元の移植メモでは `flutter_inappwebview` への移行も候補にしていましたが、現時点では
WebView を `GakujoWebViewService` で抽象化したうえで、Windows は `webview_windows`、
Android/iOS/macOS は `webview_flutter` を使っています。Windows の実ビルドまで通る
構成を優先した判断です。将来 `flutter_inappwebview` の Windows 対応を採用する場合も、
差し替え箇所は `lib/src/web_view_service.dart` と
`lib/src/platform/platform_service.dart` に寄せています。

学務情報システム固有のロジックは、基本的にSwift側へ移す必要はありません。
