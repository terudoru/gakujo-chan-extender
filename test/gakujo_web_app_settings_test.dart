import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
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
