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

## 注入場所

元README互換機能は、すべて `GakujoWebApp` のページ読み込み完了時にWebViewへ注入されます。

- `lib/src/gakujo_web_app.dart`

## 注意

連絡通知一括既読はブラウザ拡張のように別タブを開く代わりに、同一WebView内で `fetch` と非表示 `iframe` のフォールバックを使います。学務情報システム側が既読化に追加操作を要求するよう変更された場合は、追加対応が必要です。
