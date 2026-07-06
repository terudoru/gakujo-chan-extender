# 元 gakujo-chan-extender README 機能の実装状況

この文書は、`koji-genba/gakujo-chan-extender` の README に書かれている機能を、More Better Gakujo Flutter 版でどこまで実装しているかをまとめたものです。

## 実装済み

| 元READMEの機能 | Flutter版の実装 | 実装ファイル |
| --- | --- | --- |
| 時間制限120分ぐらいまで自動延長 | 残り時間が約11分以下になったら時計アイコン相当をクリックし、URLごとに最大10回まで延長します。 | `lib/src/gakujo_session_extender_script.dart` |
| レポートを提出期間順にソート | レポート表が表示されたら自動で提出期間順に並べ、ボタンも追加します。 | `lib/src/gakujo_report_sorter_script.dart` |
| レポートをタイトルでソート | `タイトルでソート` ボタンを追加します。 | `lib/src/gakujo_report_sorter_script.dart` |
| レポートを開講番号でソート | `開講番号でソート` ボタンを追加します。 | `lib/src/gakujo_report_sorter_script.dart` |
| 一時保存レポートを青字表示 | `一時保存` / `Temporarily saved` のセルを青字にします。 | `lib/src/gakujo_report_sorter_script.dart` |
| 成績を得点順にソート | `得点でソート` ボタンを追加します。 | `lib/src/gakujo_gpa_display_script.dart` |
| 成績を開講番号順にソート | `開講番号でソート` ボタンを追加します。 | `lib/src/gakujo_gpa_display_script.dart` |
| 成績をNo.順にソート | `No.でソート` ボタンを追加します。 | `lib/src/gakujo_gpa_display_script.dart` |
| GPA計算 | `main-frame-if` 内の `#taniReferListForm+table` を優先して検出し、GP列ヘッダー下に `GPA:xxxx` を表示します。 | `lib/src/gakujo_gpa_display_script.dart` |
| 連絡通知一括既読 | `指定した個数を既読にする` ボタンと個数入力欄を追加し、上から指定数の通知URLへアクセスして既読化を試みます。 | `lib/src/gakujo_message_reader_script.dart` |
| 二段階認証自動化 | 保存済みBase32秘密鍵からTOTPを生成し、`ninshoCode` に入力して送信します。 | `lib/src/two_factor_autofill_script.dart` |

## Flutter版の追加機能

| 追加機能 | 実装ファイル |
| --- | --- |
| ログインID/パスワードの自動入力 | `lib/src/login_autofill_assist_script.dart` |
| 資料ダウンロード捕捉 | `lib/src/gakujo_download_capture_script.dart` |
| Android/macOS/iOS/Windows向けの保存先選択と自動仕分け | `lib/src/file_system_gakujo_download_service.dart`, `lib/src/download_file_name_policy.dart`, `lib/src/gakujo_download_service.dart` |
| デスクトップWebViewのズーム調整 | `lib/src/desktop_page_zoom_script.dart` |
| ダウンロード履歴 | 保存した資料名、推定授業名、保存日時、保存場所をアプリ内で確認できます。 | `lib/src/gakujo_download_history_store.dart`, `lib/src/gakujo_web_app.dart` |
| 授業ごとの資料一覧 | ダウンロード履歴を授業名ごとにまとめて表示します。 | `lib/src/gakujo_download_history_store.dart`, `lib/src/gakujo_web_app.dart` |
| 設定のエクスポート/インポート | 保存モードと表示モードをクリップボード経由で移行できます。 | `lib/src/gakujo_web_app.dart` |
| 診断情報コピー | 問題報告用に、機密情報を含めない範囲で環境情報と状態をコピーできます。 | `lib/src/gakujo_web_app.dart` |
| ログイン状態の復帰改善 | ログイン後に前回ページへ戻れるよう、保存済みページを復帰候補として扱います。 | `lib/src/gakujo_last_page_store.dart`, `lib/src/gakujo_web_app.dart` |
| 更新通知/差分検知 | 成績、レポート、連絡通知、スケジュールなどの本文ハッシュを保存し、内容変化を未処理として表示します。 | `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_web_app.dart` |
| 未読/未処理リスト | 変化があったページと検出した提出期限をツールバーからまとめて確認できます。 | `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_web_app.dart` |
| 提出期限の抽出 | ページ本文から期限/締切/提出を含む日付行を抽出し、アプリ内の期限リストに表示します。 | `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_web_app.dart` |
| お気に入り/よく使うページ | 現在ページをお気に入りに追加し、後からツールバー経由で開けます。 | `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_web_app.dart` |
| 現在ページのURL操作 | 現在ページのURLコピーと外部ブラウザ起動に対応します。 | `lib/src/gakujo_web_app.dart` |
| セッション切れ検知 | ログイン/タイムアウト系URLへ遷移したときにステータスへ警告を表示します。 | `lib/src/gakujo_web_app.dart` |
| ダウンロード失敗時の再試行キュー | 保存に失敗したダウンロード要求を保持し、メニューから再試行できます。 | `lib/src/gakujo_download_history_store.dart`, `lib/src/gakujo_web_app.dart` |
| セッション切れ時の復帰ガイド | セッション切れらしき画面に遷移したとき、再ログイン後に直前ページへ戻る案内を表示します。 | `lib/src/gakujo_web_app.dart` |
| ダウンロード後のクイック操作 | 保存場所が分かる環境では、保存完了通知からファイルを外部アプリで開けます。 | `lib/src/gakujo_web_app.dart` |
| 課題・レポート一覧のローカル保存 | レポート/小テスト系ページから課題行を抽出し、後でアプリ内から確認できるよう保存します。 | `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_web_app.dart` |
| 通知・課題・成績の変更履歴 | ページ本文ハッシュの変化を履歴として保存し、メニューから確認できます。 | `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_web_app.dart` |
| 初回セットアップウィザード | 初回起動時に表示版、保存方式、保存先、機能オン/オフをまとめて設定できます。 | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_web_app.dart` |
| 機能のオン/オフ設定 | ダウンロード捕捉、GPA表示、並び替え、更新検知、自動入力などを個別に切り替えられます。 | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_web_app.dart` |
| ダウンロード保存先の健全性チェック | 設定画面と保存直前に保存先の状態を確認し、再設定が必要な場合に案内します。 | `lib/src/gakujo_web_app.dart`, `lib/src/file_system_gakujo_download_service.dart` |
| 学務メニューのクイックジャンプ | 成績、レポート、連絡通知、ダウンロード、シラバス、スケジュールへメニューから移動できます。 | `lib/src/gakujo_web_app.dart` |
| バックアップ対象の拡張 | ログイン情報と2FA秘密鍵を除外したまま、機能設定、履歴、お気に入り、課題キャッシュ、変更履歴も移行できます。 | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_activity_store.dart`, `lib/src/gakujo_download_history_store.dart`, `lib/src/gakujo_web_app.dart` |
| アプリ内更新チェック | 実行中アプリのバージョンとGitHub Releasesの最新リリースを比較し、更新があれば配布ページを開けます。 | `lib/src/app_update_service.dart`, `lib/src/gakujo_web_app.dart` |
| 自動バックアップ | 設定、履歴、お気に入り、課題キャッシュ、変更履歴を定期的にローカルJSONへ保存します。機能設定からオフにできます。 | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_web_app.dart` |
| 課題期限のOS通知 | 新しい提出期限を検出したときにOS通知を出します。Android/iOS/macOSはネイティブ通知、Windowsは標準ダイアログ通知に対応します。機能設定からオフにできます。 | `lib/src/gakujo_app_settings.dart`, `lib/src/gakujo_notification_service.dart`, `android/app/src/main/kotlin/net/yoshida/morebettergakujo/MainActivity.kt`, `ios/Runner/AppDelegate.swift`, `macos/Runner/AppDelegate.swift`, `windows/runner/flutter_window.cpp` |
| エラー報告パッケージ作成 | 軽量版または詳細版を選び、診断情報をJSONファイルに保存し、同じ内容をクリップボードへコピーします。 | `lib/src/gakujo_web_app.dart` |
| データ管理画面 | 履歴、失敗キュー、お気に入り、期限、変更履歴、課題キャッシュの件数確認と一括削除ができます。 | `lib/src/gakujo_web_app.dart` |

## 注入場所

元README互換機能は、すべて `GakujoWebApp` のページ読み込み完了時にWebViewへ注入されます。

- `lib/src/gakujo_web_app.dart`

## 注意

連絡通知一括既読はブラウザ拡張のように別タブを開く代わりに、同一WebView内で `fetch` と非表示 `iframe` のフォールバックを使います。学務情報システム側が既読化に追加操作を要求するよう変更された場合は、追加対応が必要です。
