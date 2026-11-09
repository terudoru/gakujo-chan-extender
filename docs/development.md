# 開発ガイド

このアプリは Flutter 製で、学情を WebView で開き、ページを読み込むたびに TypeScript から生成したスクリプトを注入して機能を追加しています。Android、iOS/iPadOS、macOS、Windows、Linux を同じコードベースで扱います。

## まず覚えること

1. Flutter 3.47.8 以降（Dart 3.13.7 以降）と Node.js 24 を使う
2. `lib/src/generated/*.g.dart` は手で編集しない。`web_scripts/src/` の TypeScript を直してから再生成する
3. `android/upload-keystore.jks`、`android/key.properties`、`android/local.properties` はコミットしない
4. 変更したら、`flutter analyze`、`flutter test`、`npm --prefix web_scripts run check` を実行し、エラーがないことを確かめる

初めての人は「開発環境」と「ビルドとテスト」を読んでください。ほかの節は、その部分を変更するときに開けば足ります。リリースの手順は [release.md](release.md) にあります。

## 開発環境

| 対象 | 必要なもの |
|---|---|
| 全体 | Flutter 3.47.8 以降（CI も 3.47.8 を使う）、Node.js 24 |
| Android | Android SDK。CI は Java 17 を使う |
| iOS/iPadOS・macOS | Xcode と CocoaPods。`xcode-select` がフルの Xcode を指していること（Command Line Tools だけを指していると `xcrun xcodebuild` が失敗する） |
| Windows | Windows ホスト、Visual Studio 2022 の C++ ワークロード、CMake 3.20 以降、Microsoft Edge WebView2 Runtime |
| Linux | Linux x64、`clang cmake ninja-build pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev libsecret-1-dev liblzma-dev dpkg-dev`（Ubuntu/Debian のパッケージ） |

リポジトリのルートで依存関係を入れます。

```sh
flutter pub get
npm --prefix web_scripts ci
```

`flutter test` の一部は `node` を起動して TypeScript のテストを動かすので、Node.js にパスを通しておいてください。

## ビルドとテスト

```sh
flutter analyze
flutter test
npm --prefix web_scripts run check
flutter run -d android
flutter build apk --release
./android/gradlew -p android bundleRelease
flutter build ios --debug --no-codesign
flutter build macos --debug
flutter build windows --debug
flutter build linux --debug
```

- `flutter build windows` は Windows ホストでだけ動く
- macOS と iOS のビルドには、上の表の Xcode の条件が要る
- ローカルに Android の署名鍵がなければ、リリースビルドはデバッグ署名になる（[release.md](release.md) の「Android の署名」）

出力先は次のとおりです。

| 成果物 | 場所 |
|---|---|
| Android リリース APK | `build/app/outputs/flutter-apk/app-release.apk` |
| Android デバッグ APK | `build/app/outputs/flutter-apk/app-debug.apk` |
| Android リリース AAB | `build/app/outputs/bundle/release/app-release.aab` |
| macOS アプリ | `build/macos/Build/Products/Debug/More Better Gakujo.app` |
| Windows アプリ | `build/windows/x64/runner/Debug/morebettergakujo_flutter.exe` |
| Linux アプリ | `build/linux/x64/debug/bundle/` |

## WebView に注入するスクリプト

`web_scripts/src/` の TypeScript を、主に Dart の文字列として `lib/src/generated/*.g.dart` に書き出しています。生成したファイルもコミットします。TypeScript を変えたら、次のコマンドで再生成してからコミットしてください。

```sh
npm --prefix web_scripts run build
npm --prefix web_scripts run check
```

`check` は型検査をしたうえで、コミット済みの `.g.dart` が TypeScript の内容と一致しているかを確かめます。

## Android の2段階認証の QA

エミュレーターを起動した状態で実行します。

```sh
flutter build apk --debug
./scripts/flutter_android_local_2fa_qa.sh
```

1. デバッグ APK をインストールする
2. デバッグビルドだけで開ける `file:///android_asset/qa/two_factor.html` を開く
3. Intent extra でテスト用の Base32 秘密鍵を渡し、6桁のコードを logcat に出さずに自動入力と送信が行われるかを確かめる

スクリーンショット、UI の XML、logcat は `build/qa/` に出力されます。

## 学情まわりの基本の動き

- 表示モードに応じて、学情の `campusportal.do`（デスクトップ版）か `campussmart.do`（モバイル版）を開く
- ページの読み込みと自動入力を許すのは `https://gakujo.iess.niigata-u.ac.jp/` だけ。デバッグビルドでは QA 用の `file:///android_asset/qa/` も許す
- 画面の遷移は、学情に加えて、`niigata-u.ac.jp` とそのサブドメイン、`univcoop.jp` とそのサブドメイン、Google の一部のサービス、YouTube、Zoom、`forms.gle` を許す。許すホストの一覧は `lib/src/allowed_web_origins.dart` にある
- 2段階認証は、6桁のコードではなく Base32 の秘密鍵だけを保存し、Dart で TOTP のコードを作る。注入したスクリプトが `input[name="ninshoCode"]` に入力して送信する
- 秘密鍵は `flutter_secure_storage` で保存する。Android では Keystore、iOS/macOS ではキーチェーンに入る
- 科目名は、授業連絡、レポート・小テスト・アンケートの提出画面、科目情報の表、ファイル名などから推定する

## プラットフォームごとの実装

プラットフォームによる分岐は `lib/src/platform/platform_service.dart` に集め、WebView は `lib/src/web_view_service.dart` の `GakujoWebViewService` で抽象化しています。

| プラットフォーム | WebView | ダウンロードと保存先 |
|---|---|---|
| Android | `webview_flutter` | 既存の MethodChannel のダウンロード処理を使う |
| iOS/iPadOS | `webview_flutter` | Dart でファイルを取得し、ネイティブのブリッジで「ファイル」アプリのフォルダ選択か書き出しに渡す。フォルダ選択には iOS/iPadOS 14 以降が要る |
| macOS | `webview_flutter` | Dart でダウンロードする。Sandbox で `network.client` と、利用者が選んだファイルの読み書きの entitlement を付け、保存先フォルダは security-scoped bookmark として持つ |
| Windows | 同梱の `webview_flutter_windows` 1.2.0 | Dart でダウンロードする |

学情に固有の処理は Dart と注入スクリプトに置き、Swift などのネイティブ側には移しません。

### Windows の WebView

- 選択メニューを WebView の表示位置に合わせるため、`webview_windows` 0.4.0 から、座標の通知とフォーカスの処理を直した同系統の `webview_flutter_windows` に移った
- `third_party/webview_flutter_windows` に同梱した 1.2.0 には、タッチパッドのスクロールの修正を入れている
- 上流はキャンセルできる `NavigationStarting` を公開していないので、同梱版に `setNavigationAllowlist` を追加した。`AllowedWebOrigins.navigationHosts` と `navigationHostSuffixes` にないホストへのメインフレームの遷移とリダイレクトを、リクエストを送る前にネイティブ側で取り消す
- `SourceChanged` のあとに `stop()` で止める処理も、二重の防御として残している
- `flutter_inappwebview` への移行も検討したが、Windows で実際にビルドできる構成を優先して見送った。将来差し替えるときは、`lib/src/web_view_service.dart` と `lib/src/platform/platform_service.dart` を直す

### Android のレンダラー終了

`webview_flutter_android`（4.14.1 の時点）は `WebViewClient.onRenderProcessGone` を実装していません。メモリ不足で WebView のレンダラーが終了されると、Android の既定の動きでアプリも終了します。カメラなど別のアプリに切り替えたあとに起きやすい現象です。

プラグインが管理する WebView はアプリ側で作り直せないので、いまは再起動後に前回のページを復元し、レポート本文は下書きの自動保存で守っています。上流が対応したら、レンダラーが終了したときに WebView を作り直して再読み込みするように直してください。

## 機能と実装ファイル

`lib/src/gakujo_web_app.dart` は、`gakujo_web_app_*.dart` の part ファイルに分かれています。下の表で `gakujo_web_app.dart` と書いた機能は、その part ファイルにある場合もあります。元のブラウザ拡張にあった機能は、どれも `GakujoWebApp` がページの読み込みを終えたときに WebView に注入します。

### 元のブラウザ拡張にあった機能

| 元の README の機能 | このアプリでの実装 | 実装ファイル |
| --- | --- | --- |
| 時間制限120分ぐらいまで自動延長 | 残り時間が約11分以下になったら時計のアイコンに相当する要素をクリックする。URL ごとに最大10回まで延長する | `lib/src/gakujo_session_extender_script.dart` |
| レポートを提出期間順にソート | レポートの表が表示されたら自動で提出期間順に並べ、ボタンも追加する | `lib/src/gakujo_report_sorter_script.dart` |
| レポートをタイトルでソート | `タイトルでソート` ボタンを追加する | `lib/src/gakujo_report_sorter_script.dart` |
| レポートを開講番号でソート | `開講番号でソート` ボタンを追加する | `lib/src/gakujo_report_sorter_script.dart` |
| 一時保存レポートを青字表示 | `一時保存` / `Temporarily saved` のセルを青字にする | `lib/src/gakujo_report_sorter_script.dart` |
| 成績を得点順にソート | `得点でソート` ボタンを追加する | `lib/src/gakujo_gpa_display_script.dart` |
| 成績を開講番号順にソート | `開講番号でソート` ボタンを追加する | `lib/src/gakujo_gpa_display_script.dart` |
| 成績を No. 順にソート | `No.でソート` ボタンを追加する | `lib/src/gakujo_gpa_display_script.dart` |
| GPA 計算 | `main-frame-if` の中の `#taniReferListForm+table` を優先して探し、GP 列の見出しの下に `GPA:xxxx` を表示する | `lib/src/gakujo_gpa_display_script.dart` |
| 連絡通知一括既読 | `指定した個数を既読にする` ボタンと個数の入力欄を追加し、上から指定した数の通知の URL を開いて既読にする | `lib/src/gakujo_message_reader_script.dart` |
| 二段階認証自動化 | 保存した Base32 秘密鍵から TOTP を作り、`ninshoCode` に入力して送信する | `lib/src/two_factor_autofill_script.dart` |

連絡通知の一括既読は、ブラウザ拡張のように別のタブを開く代わりに、同じ WebView の中で `fetch` を使い、だめなら非表示の `iframe` で開きます。学情が既読にするために別の操作を求めるように変わったら、対応が必要です。

### このアプリで加えた機能

| 機能 | 内容 | 実装ファイル |
| --- | --- | --- |
| ログイン ID/パスワードの自動入力 | | `lib/src/login_autofill_assist_script.dart` |
| 資料ダウンロードの捕捉 | | `lib/src/gakujo_download_capture_script.dart` |
| 保存先の選択と自動仕分け | Android/macOS/iOS/Windows 向け | `lib/src/file_system_gakujo_download_service.dart`, `lib/src/download_file_name_policy.dart`, `lib/src/gakujo_download_service.dart` |
| デスクトップの WebView のズーム調整 | | `lib/src/desktop_page_zoom_script.dart` |
| ダウンロード履歴 | 保存した資料名、推定した授業名、保存日時、保存場所をアプリ内で確かめられる | `lib/src/gakujo_download_history_store.dart`, `lib/src/gakujo_web_app.dart` |
| 授業ごとの資料一覧 | ダウンロード履歴を授業名ごとにまとめて表示する | `lib/src/gakujo_download_history_store.dart`, `lib/src/gakujo_web_app.dart` |
| 設定のエクスポート/インポート | 保存モードと表示モードをクリップボード経由で移す | `lib/src/gakujo_web_app.dart` |
| 診断情報のコピー | 問題の報告用に、機密情報を含めない範囲で環境と状態をコピーする | `lib/src/gakujo_web_app.dart` |
| ログイン状態からの復帰 | ログイン後に前回のページへ戻れるよう、保存したページを復帰の候補にする | `lib/src/gakujo_last_page_store.dart`, `lib/src/gakujo_web_app.dart` |
| 提出期限の抽出 | ページ本文から、期限・締切・提出を含む日付の行を取り出し、アプリ内の期限リストに出す | `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_web_app.dart` |
| お気に入り | 今のページをお気に入りに入れ、あとでツールバーから開く | `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_web_app.dart` |
| 今のページの URL の操作 | URL のコピーと、外部ブラウザでの表示 | `lib/src/gakujo_web_app.dart` |
| セッション切れの検知 | ログインやタイムアウトの URL に移ったとき、ステータスに警告を出す | `lib/src/gakujo_web_app.dart` |
| ダウンロード失敗の再試行キュー | 保存に失敗したダウンロードの要求を残し、メニューから再試行できる | `lib/src/gakujo_download_history_store.dart`, `lib/src/gakujo_web_app.dart` |
| セッション切れからの復帰ガイド | セッション切れらしい画面に移ったとき、再ログイン後に直前のページへ戻る案内を出す | `lib/src/gakujo_web_app.dart` |
| ダウンロード後のクイック操作 | 保存場所が分かる環境では、保存完了の通知からファイルを外部アプリで開ける | `lib/src/gakujo_web_app.dart` |
| 課題・レポート一覧のローカル保存 | レポートや小テストのページから課題の行を取り出し、あとでアプリ内から見られるよう保存する | `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_web_app.dart` |
| 初回セットアップ | 初回起動時に、表示モード、保存方式、保存先、機能のオン/オフをまとめて設定する | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_web_app.dart` |
| 機能のオン/オフ | ダウンロードの捕捉、GPA 表示、並べ替え、自動入力などを個別に切り替える | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_web_app.dart` |
| 保存先の状態の確認 | 設定画面と保存の直前に保存先を確かめ、設定し直しが必要なら案内する | `lib/src/gakujo_web_app.dart`, `lib/src/file_system_gakujo_download_service.dart` |
| 学情メニューへのクイックジャンプ | 成績、レポート、連絡通知、ダウンロード、シラバス、スケジュールへメニューから移る | `lib/src/gakujo_web_app.dart` |
| バックアップ対象の拡張 | ログイン情報と2段階認証の秘密鍵を除いたまま、機能の設定、履歴、お気に入り、課題のキャッシュも移せる | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_download_history_store.dart`, `lib/src/gakujo_web_app.dart` |
| アプリ内の更新確認 | GitHub Releases の最新版を1日1回自動で確認し、新しい版があればバナーから配布ページを開ける。手動でも確認できる | `lib/src/app_update_service.dart`, `lib/src/gakujo_web_app.dart`, `lib/src/widgets/app_update_banner.dart` |
| 自動バックアップ | 設定、履歴、お気に入り、課題のキャッシュを定期的にローカルの JSON に保存する。機能の設定でオフにできる | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_web_app.dart` |
| 課題の期限の OS 通知 | 新しい提出期限を見つけたら OS の通知を出す。Android/iOS/macOS はネイティブの通知、Windows は標準のダイアログで通知する。機能の設定でオフにできる | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_notification_service.dart`, `android/app/src/main/kotlin/net/yoshida/morebettergakujo/MainActivity.kt`, `ios/Runner/AppDelegate.swift`, `macos/Runner/AppDelegate.swift`, `windows/runner/flutter_window.cpp` |
| エラー報告パッケージ | 軽量版か詳細版を選び、診断情報を JSON ファイルに保存して、同じ内容をクリップボードにもコピーする | `lib/src/gakujo_web_app.dart` |
| データ管理画面 | 履歴、失敗キュー、お気に入り、期限、課題のキャッシュの件数を見て、まとめて削除できる | `lib/src/gakujo_web_app.dart` |
| 端末間の同期 | 設計は [star-sync.md](star-sync.md) | `lib/src/star_sync/`, `lib/src/widgets/star_sync_section.dart` |

## PDF ビューア

`tools/pdf_preview/` は、[pdfrx 2.10.1](https://github.com/espresso3389/pdfrx)（MIT）のビューアの例をもとにした Flutter Web アプリです。生成したファイルを `assets/pdf_preview/web` に入れてアプリに埋め込みます。アプリは、推測できないトークンで守ったループバックのアドレスでこの静的ファイルを配信し、選ばれた PDF を、sandbox を付けたフレームにメモリ上で渡します。ビューアは任意の URL を開かず、文書のデータを保存もしません。

上流 2.10.1 に当てているパッチは次の2つです。どちらも上流のファイルのハッシュに合わせて作っているので、pdfrx を更新するときは見直してください。ブラウザのプロセス全体の使用量までは制限しません。

- `pdfium_worker.patch`：同梱の代替フォントを永続ストレージなしで読み込む。ページと描画の大きさ、WebAssembly のヒープに上限を付ける。固定した版の PDFium のバイナリに対応する
- `pdfium_client.patch`：プレビューのページを閉じたときに worker を終了する

### 再ビルドの手順

1. Flutter 3.47.8 を使い、`tools/pdf_preview/` で `flutter pub get` を実行する
2. [PDFium 158.0.8125.0](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F8125) の `pdfium-wasm.tgz` をダウンロードする
3. アーカイブの SHA-256 が `77db4ef8c9ab0ecef2af659fe7d407279a0ebacff4cfcc1b3cc28160be2abfbd` であることを確かめる
4. アーカイブから `lib/pdfium.wasm` を取り出す
5. `python build_viewer.py --pdfium-wasm PATH` を実行する。スクリプトはバイナリと worker のハッシュを確かめてから、同梱するファイルを生成する

確かめていないアーカイブのバイナリはコミットしないでください。この版の固定を変えるときは、PDFium のセキュリティ更新も確かめてください。

### 代替フォント

- 代替フォントは Noto Sans CJK と GNU Unifont 18.0.01
- `MBGPreviewUI.otf` は、画面のラベルにだけ使う Noto Sans CJK のサブセットを改名したもの。操作部品の表示に要るメモリを減らすために使う
- `MBGPreviewUI.otf` は、`subset_ui_font.py` と fontTools 4.60.1 で作り直す。lockfile にある版の `material_ui` と `cupertino_ui` の日本語のローカライズの Dart ファイルを渡す
- 文字の集合はビューアのソースとそのローカライズから作るので、ラベルを追加したら作り直す
- 代替フォントがあっても、フォントを埋め込んでいない文書の字形や組版が意図どおりになるとは限らない。フォントを埋め込んだ文書のほうが確実
- ライセンスと PDFium の第三者の告知は `tools/pdf_preview/licenses/` にある

## 端末間同期のテスト

通常の `flutter test` では、偽の Google ドライブ API を使い、通信と2端末間の同期を確かめます。

## `scripts/` の一覧

| スクリプト | 用途 |
|---|---|
| `flutter_android_local_2fa_qa.sh` | Android の2段階認証の QA（上の節） |
| `package_ios_ipa.sh` / `generate_altstore_source.sh` | iOS の IPA と SideStore の source を作る（[release.md](release.md)） |
| `package_windows_inno.ps1` | Windows のインストーラーを作る（[release.md](release.md)） |
| `package_linux.sh` | Linux の tar.gz と deb を作る（[release.md](release.md)） |
| `staged_release.py` | リリース workflow から GitHub Release を公開する |
| `verify_android_signature.py` / `verify_macos_release.sh` | リリース workflow で、APK の署名と macOS アプリの起動を確かめる |
| `test_darwin_secure_storage.sh` | 同梱の `flutter_secure_storage_darwin` のキーチェーン処理を、Swift のテストで確かめる |
| `build_qpdf_wasm.sh` / `build_pdfjs_cmaps.py` | 添付ファイルの圧縮に使う qpdf の WebAssembly 版と、pdf.js のファイルを作る |

同梱しているサードパーティのコードと、そこに入れた修正は [NOTICE.md](../NOTICE.md) にあります。再配布するときや、大きく変更したものを配布するときは、`LICENSE.md` と `NOTICE.md` を含めてください。
