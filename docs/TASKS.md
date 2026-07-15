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
- [ ] 5. `gakujo_web_app.dart` 分割 (2/3): 末尾の私的データクラス（`_PageTextSnapshot`、`_MessageActivityCandidate`、`_ActivityScanResult`、`_ResolvedCalendarTerm`、`_ScheduleIntegrationDialogResult`、`_OfficialGoogleScheduleIntegration`、`_OfficialScheduleExportFetch`）と冒頭の enum 群を適切な別ファイルへ移動する。挙動変更なし
- [ ] 6. `lib/src/gakujo_activity_store.dart`（723行、テストなし）の主要ロジック（保存・差分検知・期限抽出）にユニットテストを追加する
- [ ] 7. 依存パッケージを制約内でマイナー更新する（`flutter pub upgrade`）。更新後に analyze/test を通し、`pubspec.lock` の差分をコミットする
- [ ] 8. `gakujo_web_app.dart` 分割 (3/3): `_GakujoWebAppState`（約6,300行）から独立性の高い機能グループ（例: 設定ダイアログ構築、データ管理画面、診断情報生成のいずれか1つ）をヘルパークラスまたは別ファイルへ抽出する。挙動変更なし

## 完了ログ

- 2026-07-15 タスク1: `test/base32_test.dart` を追加（6テスト）。analyze 0件、テスト258件全通過。
- 2026-07-15 タスク2: `test/gakujo_last_page_store_test.dart`（7テスト）と `test/two_factor_secret_store_test.dart`（3テスト）を追加。analyze 0件、テスト268件全通過。
- 2026-07-15 タスク3: `test/secure_storage_factory_test.dart` を追加（3テスト）。analyze 0件、テスト271件全通過。
- 2026-07-15 タスク4: Widget 15クラスを `lib/src/widgets/`（toolbar_actions / settings_sections / app_data_sections / private_widgets(part)）へ移動。`gakujo_web_app.dart` は 7,573行→6,763行。既存 import は export で維持。analyze 0件、テスト271件全通過。
