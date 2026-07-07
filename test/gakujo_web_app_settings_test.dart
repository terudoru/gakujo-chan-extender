import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/download_destination_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  test('javaScriptResultAsBool accepts platform-specific boolean strings', () {
    expect(javaScriptResultAsBool(true), isTrue);
    expect(javaScriptResultAsBool('true'), isTrue);
    expect(javaScriptResultAsBool('"true"'), isTrue);
    expect(javaScriptResultAsBool('"false"'), isFalse);
    expect(javaScriptResultAsBool('not-json'), isFalse);
    expect(javaScriptResultAsBool(1), isTrue);
    expect(javaScriptResultAsBool(0), isFalse);
    expect(javaScriptResultAsBool('1'), isTrue);
    expect(javaScriptResultAsBool('0'), isFalse);
  });

  test('isCancelledDownloadError only treats picker cancellation as cancel',
      () {
    expect(
      isCancelledDownloadError(
        PlatformException(code: 'cancelled', message: '保存をキャンセルしました'),
      ),
      isTrue,
    );
    expect(
      isCancelledDownloadError(
        PlatformException(code: 'download_failed', message: 'timeout'),
      ),
      isFalse,
    );
  });

  test('isLikelyMacosKeychainUserDeniedError detects denial statuses', () {
    expect(
      isLikelyMacosKeychainUserDeniedError(
        PlatformException(code: 'errSecUserCanceled', message: 'User canceled'),
      ),
      isTrue,
    );
    expect(
      isLikelyMacosKeychainUserDeniedError(
        PlatformException(code: 'keychain_error', message: 'OSStatus -25293'),
      ),
      isTrue,
    );
    expect(
      isLikelyMacosKeychainUserDeniedError(
        PlatformException(code: 'timeout', message: 'Keychain timed out'),
      ),
      isFalse,
    );
  });

  test('activity page reading follows independent feature toggles', () {
    expect(
      shouldReadPageForActivityFeatures(const GakujoAppSettings()),
      isTrue,
    );
    expect(
      shouldReadPageForActivityFeatures(
        const GakujoAppSettings(
          disabledFeatureFlags: {
            GakujoFeatureFlag.activityScan,
            GakujoFeatureFlag.reportListCache,
          },
        ),
      ),
      isTrue,
    );
    expect(
      shouldReadPageForActivityFeatures(
        const GakujoAppSettings(
          disabledFeatureFlags: {
            GakujoFeatureFlag.activityScan,
            GakujoFeatureFlag.deadlineScan,
          },
        ),
      ),
      isTrue,
    );
    expect(
      shouldReadPageForActivityFeatures(
        const GakujoAppSettings(
          disabledFeatureFlags: {
            GakujoFeatureFlag.activityScan,
            GakujoFeatureFlag.deadlineScan,
            GakujoFeatureFlag.reportListCache,
          },
        ),
      ),
      isFalse,
    );
  });

  test('activity bell toolbar button is disabled by default', () {
    expect(activityBellToolbarButtonEnabled, isFalse);
  });

  test('downloadRootLabel hides local path for lightweight diagnostics', () {
    const root = DownloadDestinationSettings(
      isConfigured: true,
      displayName: '授業資料',
      path: '/Users/student/Documents/Gakujo',
    );

    expect(downloadRootLabel(root, includePath: false), '授業資料');
    expect(
      downloadRootLabel(root, includePath: true),
      '授業資料\n/Users/student/Documents/Gakujo',
    );
  });

  test('downloadRootLabel avoids leaking path when no display name exists', () {
    const root = DownloadDestinationSettings(
      isConfigured: true,
      path: '/Users/student/Documents/Gakujo',
    );

    expect(downloadRootLabel(root, includePath: false), '設定済み');
    expect(
      downloadRootLabel(root, includePath: true),
      '/Users/student/Documents/Gakujo',
    );
  });

  testWidgets('navigation actions enable only available directions',
      (tester) async {
    var backCount = 0;
    var forwardCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              GakujoNavigationActions(
                canGoBack: true,
                canGoForward: false,
                onBack: () {
                  backCount += 1;
                },
                onForward: () {
                  forwardCount += 1;
                },
              ),
            ],
          ),
        ),
      ),
    );

    final backButton = find.widgetWithIcon(IconButton, Icons.arrow_back);
    final forwardButton = find.widgetWithIcon(IconButton, Icons.arrow_forward);

    expect(
      tester.widget<IconButton>(backButton).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<IconButton>(forwardButton).onPressed,
      isNull,
    );

    await tester.tap(backButton);
    await tester.tap(forwardButton, warnIfMissed: false);
    await tester.pump();

    expect(backCount, 1);
    expect(forwardCount, 0);
  });

  testWidgets('toolbar navigation buttons keep hittable compact targets',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 40,
            actions: [
              GakujoNavigationActions(
                canGoBack: true,
                canGoForward: true,
                onBack: () {},
                onForward: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.widgetWithIcon(IconButton, Icons.arrow_back)),
      const Size(40, 40),
    );
    expect(
      tester.getSize(find.widgetWithIcon(IconButton, Icons.arrow_forward)),
      const Size(40, 40),
    );
  });

  testWidgets('toolbar zoom buttons keep hittable compact targets',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 40,
            actions: [
              GakujoZoomActions(
                zoomPercent: 100,
                canZoomOut: true,
                canZoomIn: true,
                onZoomOut: () {},
                onReset: () {},
                onZoomIn: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.widgetWithIcon(IconButton, Icons.remove)),
      const Size(40, 40),
    );
    expect(
      tester.getSize(find.widgetWithIcon(IconButton, Icons.add)),
      const Size(40, 40),
    );
    expect(
      tester.getSize(find.widgetWithText(TextButton, '100%')),
      const Size(56, 40),
    );
  });

  testWidgets('message exclude keyword section exposes add and remove actions',
      (tester) async {
    final controller = TextEditingController(text: '説明会');
    var changedText = '';
    var addCount = 0;
    var removedKeyword = '';

    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageExcludeKeywordsSection(
            keywords: const ['アンケート'],
            controller: controller,
            canAdd: true,
            onChanged: (value) {
              changedText = value;
            },
            onAdd: () async {
              addCount += 1;
            },
            onRemove: (keyword) async {
              removedKeyword = keyword;
            },
          ),
        ),
      ),
    );

    expect(find.text('連絡通知の除外キーワード'), findsOneWidget);
    expect(find.text('アンケート'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '集中講義');
    expect(changedText, '集中講義');

    await tester.tap(find.widgetWithText(FilledButton, '追加'));
    await tester.pump();
    expect(addCount, 1);

    tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
    await tester.pump();
    expect(removedKeyword, 'アンケート');
  });

  testWidgets('settings expansion section hides and reveals its content',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsExpansionSection(
            title: '表示設定',
            icon: Icons.web_asset_outlined,
            child: Text('表示版の設定内容'),
          ),
        ),
      ),
    );

    expect(find.text('表示設定'), findsOneWidget);
    expect(find.text('表示版の設定内容'), findsNothing);

    await tester.tap(find.text('表示設定'));
    await tester.pumpAndSettle();

    expect(find.text('表示版の設定内容'), findsOneWidget);
  });

  testWidgets('secret save is disabled until input is present', (tester) async {
    var saved = false;
    var cleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TwoFactorSecretSection(
            canSave: false,
            onChanged: (_) {},
            onClear: () async {
              cleared = true;
            },
            onSave: () async {
              saved = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('2FA秘密鍵'), findsOneWidget);
    expect(
        find.textContaining('gakujo-chan-extender#2段階認証自動入力'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '秘密鍵を保存'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.widgetWithText(TextButton, '秘密鍵を削除'));
    await tester.pump();

    expect(saved, isFalse);
    expect(cleared, isTrue);
  });

  testWidgets('secret save calls only the secret save callback',
      (tester) async {
    var saved = false;
    var cleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TwoFactorSecretSection(
            canSave: true,
            onChanged: (_) {},
            onClear: () async {
              cleared = true;
            },
            onSave: () async {
              saved = true;
            },
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '秘密鍵を保存'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, '秘密鍵を保存'));
    await tester.pump();

    expect(saved, isTrue);
    expect(cleared, isFalse);
  });

  testWidgets(
      'login credentials save is disabled until both fields are present',
      (tester) async {
    var saved = false;
    var cleared = false;
    var loginId = '';
    var password = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginCredentialsSection(
            isConfigured: false,
            canSave: false,
            onLoginIdChanged: (value) {
              loginId = value;
            },
            onPasswordChanged: (value) {
              password = value;
            },
            onClear: () async {
              cleared = true;
            },
            onSave: () async {
              saved = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('ログイン自動入力'), findsOneWidget);
    expect(find.textContaining('現在の状態: 未設定'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ログイン情報を保存'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'ログイン情報を削除'),
          )
          .onPressed,
      isNull,
    );

    final loginIdField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'ログインID'));
    final passwordField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'パスワード'));
    expect(loginIdField.autofillHints, contains(AutofillHints.username));
    expect(loginIdField.keyboardType, TextInputType.emailAddress);
    expect(passwordField.autofillHints, contains(AutofillHints.password));

    await tester.enterText(find.widgetWithText(TextField, 'ログインID'), 'abc123');
    await tester.enterText(find.widgetWithText(TextField, 'パスワード'), 'secret');
    await tester.pump();

    expect(loginId, 'abc123');
    expect(password, 'secret');
    expect(saved, isFalse);
    expect(cleared, isFalse);
  });

  testWidgets('login credentials section saves and clears configured state',
      (tester) async {
    var saved = false;
    var cleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginCredentialsSection(
            isConfigured: true,
            canSave: true,
            onLoginIdChanged: (_) {},
            onPasswordChanged: (_) {},
            onClear: () async {
              cleared = true;
            },
            onSave: () async {
              saved = true;
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('現在の状態: 保存済み'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ログイン情報を保存'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'ログイン情報を削除'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'ログイン情報を保存'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'ログイン情報を削除'));
    await tester.pump();

    expect(saved, isTrue);
    expect(cleared, isTrue);
  });

  testWidgets('maintenance section exposes settings and diagnostics actions',
      (tester) async {
    var checkedUpdates = false;
    var createdBackup = false;
    var createdReport = false;
    var exported = false;
    var imported = false;
    var checked = false;
    var diagnostics = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMaintenanceSection(
            onCheckUpdates: () async {
              checkedUpdates = true;
            },
            onCreateBackup: () async {
              createdBackup = true;
            },
            onCreateErrorReport: () async {
              createdReport = true;
            },
            onExportSettings: () async {
              exported = true;
            },
            onImportSettings: () async {
              imported = true;
            },
            onCheckDownloadDestination: () async {
              checked = true;
            },
            onCopyDiagnostics: () async {
              diagnostics = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('バックアップと診断'), findsOneWidget);
    expect(find.textContaining('ログイン情報と2FA秘密鍵は含めません'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '更新を確認'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'バックアップ作成'));
    await tester.tap(find.widgetWithText(OutlinedButton, '設定をコピー'));
    await tester.tap(find.widgetWithText(OutlinedButton, '設定を読み込み'));
    await tester.tap(find.widgetWithText(OutlinedButton, '保存先を確認'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'エラー報告パッケージ作成'));
    await tester.tap(find.widgetWithText(TextButton, '診断情報をコピー'));
    await tester.pump();

    expect(checkedUpdates, isTrue);
    expect(createdBackup, isTrue);
    expect(createdReport, isTrue);
    expect(exported, isTrue);
    expect(imported, isTrue);
    expect(checked, isTrue);
    expect(diagnostics, isTrue);
  });

  testWidgets('data shortcuts section exposes stored data actions',
      (tester) async {
    final calls = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDataShortcutsSection(
            onShowDownloadHistory: () async => calls.add('history'),
            onShowFailedDownloads: () async => calls.add('failed'),
            onShowCourseMaterials: () async => calls.add('materials'),
            onShowCachedReports: () async => calls.add('reports'),
            onShowChangeHistory: () async => calls.add('changes'),
            onShowFavorites: () async => calls.add('favorites'),
            onShowDataManagement: () async => calls.add('data'),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'ダウンロード履歴'));
    await tester.tap(find.widgetWithText(OutlinedButton, '失敗したダウンロード'));
    await tester.tap(find.widgetWithText(OutlinedButton, '授業ごとの資料'));
    await tester.tap(find.widgetWithText(OutlinedButton, '保存済み課題一覧'));
    await tester.tap(find.widgetWithText(OutlinedButton, '変更履歴'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'お気に入り'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'データ管理'));
    await tester.pump();

    expect(
      calls,
      [
        'history',
        'failed',
        'materials',
        'reports',
        'changes',
        'favorites',
        'data'
      ],
    );
  });

  testWidgets('integration section exposes schedule integration action',
      (tester) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIntegrationSection(
            onScheduleIntegration: () async {
              opened = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'スケジュール連携'));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('download destination controls show unset state', (tester) async {
    var didPick = false;
    var didClear = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadDestinationSection(
            rootLabel: '未設定',
            isConfigured: false,
            saveMode: DownloadSaveMode.autoSortToConfiguredFolder,
            helperText: null,
            onSaveModeChanged: (_) {},
            onPick: () async {
              didPick = true;
            },
            onClear: () async {
              didClear = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('ダウンロード設定'), findsOneWidget);
    expect(find.text('ファイル保存モード'), findsOneWidget);
    expect(find.text('自動仕分け+指定場所保存'), findsOneWidget);
    expect(find.text('自動仕分けなし+指定場所保存'), findsOneWidget);
    expect(find.text('自動仕分けなし+適宜保存場所指定'), findsOneWidget);
    expect(find.text('保存先フォルダ'), findsOneWidget);
    expect(find.text('未設定'), findsOneWidget);
    expect(find.text('フォルダを選択'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '解除'))
            .enabled,
        isFalse);

    await tester.tap(find.widgetWithText(OutlinedButton, 'フォルダを選択'));
    await tester.pump();

    expect(didPick, isTrue);
    expect(didClear, isFalse);
  });

  testWidgets('download destination clear is enabled after configuration',
      (tester) async {
    var didClear = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadDestinationSection(
            rootLabel: 'Downloads',
            isConfigured: true,
            saveMode: DownloadSaveMode.flatToConfiguredFolder,
            helperText: null,
            onSaveModeChanged: (_) {},
            onPick: () async {},
            onClear: () async {
              didClear = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Downloads'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '解除'))
            .enabled,
        isTrue);

    await tester.tap(find.widgetWithText(TextButton, '解除'));
    await tester.pump();

    expect(didClear, isTrue);
  });

  testWidgets('download destination helper text is shown when provided',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadDestinationSection(
            rootLabel: '未設定',
            isConfigured: false,
            saveMode: DownloadSaveMode.flatWithPickerEachTime,
            helperText: 'Google Drive は毎回保存モードを使います。',
            onSaveModeChanged: (_) {},
            onPick: () async {},
            onClear: () async {},
          ),
        ),
      ),
    );

    expect(find.text('Google Drive は毎回保存モードを使います。'), findsOneWidget);
  });

  testWidgets('page mode section offers mobile and desktop', (tester) async {
    GakujoPageMode? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GakujoPageModeSection(
            pageMode: GakujoPageMode.mobile,
            onChanged: (mode) {
              selected = mode;
            },
          ),
        ),
      ),
    );

    expect(find.text('表示版'), findsOneWidget);
    expect(find.text('モバイル版'), findsOneWidget);
    expect(find.text('デスクトップ版'), findsOneWidget);

    await tester.tap(find.text('デスクトップ版'));
    await tester.pump();

    expect(selected, GakujoPageMode.desktop);
  });
}
