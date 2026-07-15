# 自動作業ループ タスクリスト

このファイルは Claude（方針決定・レビュー）+ Codex（実装）の自動ループが消化するバックログです。

## 運用ルール

- ループは上から順に最初の未完了 `[ ]` タスクを1つ選び、1イテレーションで1タスクを処理します。
- 完了条件: `flutter analyze` が0件、`flutter test` が全件通過すること。
- 合格した変更はイテレーションごとに git コミットします（push はしません）。
- 完了したタスクは `[x]` にし、結果メモを1行追記します。
- このファイルは自由に編集してください（タスクの追加・削除・並び替え）。次のイテレーションから反映されます。

## タスク

- [x] 1. `lib/src/base32.dart` のユニットテストを追加する（RFC 4648 のテストベクタ、パディング有無、不正入力の扱いをカバー）
- [x] 2. `lib/src/gakujo_last_page_store.dart` と `lib/src/two_factor_secret_store.dart` のユニットテストを追加する
- [x] 3. `lib/src/secure_storage_factory.dart` のユニットテストを追加する
- [x] 4. `gakujo_web_app.dart` 分割 (1/3): 6596行目以降の独立 Widget クラス群（`GakujoNavigationActions`〜`_DataCountTile`。private クラスは公開が必要なら最小限のリネーム可）を `lib/src/widgets/` 配下の新ファイルへ移動する。挙動変更なし
- [x] 5. `gakujo_web_app.dart` 分割 (2/3): 末尾の私的データクラス（`_PageTextSnapshot`、`_MessageActivityCandidate`、`_ActivityScanResult`、`_ResolvedCalendarTerm`、`_ScheduleIntegrationDialogResult`、`_OfficialGoogleScheduleIntegration`、`_OfficialScheduleExportFetch`）と冒頭の enum 群を適切な別ファイルへ移動する。挙動変更なし
- [x] 6. `lib/src/gakujo_activity_store.dart`（723行、テストなし）の主要ロジック（保存・差分検知・期限抽出）にユニットテストを追加する
- [x] 7. 依存パッケージを制約内でマイナー更新する（`flutter pub upgrade`）。更新後に analyze/test を通し、`pubspec.lock` の差分をコミットする
- [x] 8. `gakujo_web_app.dart` 分割 (3/3): `_GakujoWebAppState`（約6,300行）から独立性の高い機能グループ（例: 設定ダイアログ構築、データ管理画面、診断情報生成のいずれか1つ）をヘルパークラスまたは別ファイルへ抽出する。挙動変更なし

## 第2バッチ: codex 調査で見つかった不具合（P1→P3順）

- [x] 9. [P1] iOS/macOS ダウンロードの Cookie 送信先検査を強化する。`lib/src/allowed_web_origins.dart` の `_isGakujoUrl` が scheme+host しか見ておらず、`https://gakujo...:8443/` や userinfo 付き URL にもセッション Cookie が送られうる（`lib/src/file_system_gakujo_download_service.dart` が明示的に Cookie を付与）。Android 側と同等に「ポートは443（既定）のみ・userinfo なし」まで検査し、テストを追加する
- [x] 10. [P1] Android リリース署名の暗黙フォールバックをなくす。`android/app/build.gradle.kts` は keystore がないと黙ってデバッグ署名になり、`.github/workflows/release.yml` も署名鍵未設定のため、公開APKが毎回異なる鍵で署名され上書き更新できない（v0.67.0=正式鍵、v0.68.0=CIのデバッグ鍵）。対応: (a) release.yml に GitHub Secrets（例: `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`）から keystore を復元して署名する工程を追加、(b) CI 環境（`CI=true`）では keystore 不在時にデバッグ署名へフォールバックせずビルドを失敗させる、(c) 必要な Secrets 登録手順を DEVELOPER_NOTES.md に追記。※Secrets の実登録と修正版リリースの発行はユーザー作業
- [x] 11. [P1] SideStore 配布ソースの自動更新をリリースフローに組み込む。`distribution/altstore-source.json` が 0.67.0 のまま停止している。`scripts/generate_altstore_source.sh` を iOS IPA リリース工程から呼び出して source を再生成し、リポジトリへコミット（または Release アセットとして公開）する工程を release workflow に追加し、今回分として 0.68.0 の内容にも更新する
- [ ] 12. [P1] macOS で起動時に保存設定が無視される問題を直す。`lib/src/gakujo_web_app.dart` の `_secureStorageAccessAllowed = !Platform.isMacOS`（305行付近）により、初回ウィザード・表示モード設定・最終ページ復元が起動時に効かない。ただしこれは Keychain プロンプト回避（コミット 857e8c5）の意図的な挙動なので、単純に外さないこと。方針例: 機密でない設定（表示モード・ウィザード完了フラグ・最終ページURL等）を Keychain 非依存のストレージへ移す、または初期URL決定を Keychain 読込完了まで遅延させる。トレードオフを検討して実装し、既存の macOS keychain UX テストを壊さないこと
- [ ] 13. [P2] カレンダー日付入力の検証を追加する。日付入力をそのまま `DateTime` に渡しており、`2026/02/31` が3月に自動補正されて誤った期間で予定追加・削除・ICS出力される。パース後に年月日を入力値と突き合わせて不一致なら入力エラーにする。テストを追加する
- [ ] 14. [P2] Windows の外部遷移遮断とダウンロードURL検査のタイミングを調査・改善する。`lib/src/web_view_service.dart` の Windows 実装は WebView2 の `SourceChanged` 後に `stop()` しており最初の通信は防げない。webview_windows が NavigationStarting 相当を公開しているか調査し、可能なら事前ブロックへ変更。Windows ダウンロード処理のリダイレクト追跡後検査も、追跡前/各ホップでの検査に改善できるか検討する。Windows 実機ビルドはこの Mac では検証不可のため、静的検証（analyze/test）+ 変更の保守性を重視し、確証が持てない変更はしないこと
- [ ] 15. [P3] `docs/ios-sideloading.md` を現在の CI 実態（Android・iOS・macOS・Windows すべてを GitHub Actions でビルド）に合わせて更新する

## 完了ログ

- 2026-07-15 タスク1: `test/base32_test.dart` を追加（6テスト）。analyze 0件、テスト258件全通過。
- 2026-07-15 タスク2: `test/gakujo_last_page_store_test.dart`（7テスト）と `test/two_factor_secret_store_test.dart`（3テスト）を追加。analyze 0件、テスト268件全通過。
- 2026-07-15 タスク3: `test/secure_storage_factory_test.dart` を追加（3テスト）。analyze 0件、テスト271件全通過。
- 2026-07-15 タスク4: Widget 15クラスを `lib/src/widgets/`（toolbar_actions / settings_sections / app_data_sections / private_widgets(part)）へ移動。`gakujo_web_app.dart` は 7,573行→6,763行。既存 import は export で維持。analyze 0件、テスト271件全通過。
- 2026-07-15 タスク5: enum 5個とデータクラス7個を `lib/src/gakujo_web_app_models.dart`（part）へ移動（6,763行→6,577行、完全一致の機械的移動を確認）。analyze 0件、テスト271件全通過。
- 2026-07-15 タスク6: 既存の `gakujo_activity_store_model_test.dart` に未カバーだった `mergeDeadlines` / `markSnapshotsSeen` / お気に入り操作 / `saveReportList` のテスト7件を追記（既存テストは無変更）。analyze 0件、テスト278件全通過。
- 2026-07-15 タスク7: `flutter pub upgrade` で6依存を更新（webview_flutter 4.14.1、package_info_plus 10.2.0、path_provider 2.1.6 ほか）。コマンド実行のみのため codex 委譲なしで直接実施。analyze 0件、テスト278件全通過。
- 2026-07-15 タスク8: 診断・エラー報告系4メソッド（116行）を `lib/src/gakujo_web_app_diagnostics.dart`（part + extension）へ抽出（本体 6,577行→6,458行、完全一致の機械的移動を確認）。analyze 0件、テスト278件全通過。第1バッチ完了。
- 2026-07-15 タスク9: `_isGakujoUrl` にポート（既定/443のみ）と userinfo 空の検査を追加し、Android 側 `GakujoDownloadRedirectPolicy` と同等化。テスト3ケース追加。analyze 0件、テスト279件全通過。
- 2026-07-15 タスク10: release.yml に Secrets からの署名鍵復元ステップ（未設定なら失敗）を追加。build.gradle.kts は taskGraph.whenReady で「CI かつリリースタスクかつ鍵なし」のみ失敗（初版は configuration 時 error() で CI デバッグビルドまで壊す問題をレビューで検出し修正）。CI デバッグ成功/CI リリース鍵なし失敗/ローカルリリース成功を Gradle 実行で確認。DEVELOPER_NOTES.md に Secrets 登録手順を追記。**残作業（ユーザー）: 4件の Secrets 登録と修正版リリースの発行。**
- 2026-07-15 タスク11: `altstore-source.json` を v0.68.0 の実リリース値（size 8079465、2026-07-07）に更新。release.yml の publish ジョブに source 再生成 → main へ bot コミット/push する工程を追加（push 失敗はリリースを壊さず警告）。将来リリース向けに RELEASE_NOTES は汎用文言へ調整。YAML/JSON 構文確認、analyze 0件、テスト279件全通過。※main へ push されるのはこのブランチが main へマージされてから。
