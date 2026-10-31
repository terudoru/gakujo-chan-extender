import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_crypto.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/widgets/star_sync_section.dart';

void main() {
  Widget section(
    ValueNotifier<StarSyncStatusSnapshot> status, {
    Future<void> Function(
      StarSyncConfig,
      String, {
      required bool resetExisting,
      required bool clearLocalStars,
    })?
    onSetUp,
    bool googleAvailable = false,
    bool google = false,
    Future<StarSyncPairingSetup> Function({required bool clearLocalStars})?
    onGoogleSignIn,
    Future<int> Function()? onLocalStarCount,
    Future<void> Function()? onGoogleReSignIn,
    Future<void> Function()? onResumeKeepingLocal,
    Future<void> Function()? onResumeDiscardingLocal,
    Future<StarSyncPairingSetup> Function({
      required bool resetExisting,
      required bool clearLocalStars,
    })?
    onSetUpWithPairing,
    Future<void> Function(String, {required bool clearLocalStars})? onJoin,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: StarSyncSection(
          status: status,
          googleAvailable: googleAvailable,
          isGoogleDrive: () => google,
          googleEmail: () => google ? 'user@example.com' : null,
          onGoogleSignIn:
              onGoogleSignIn ??
              ({required clearLocalStars}) async =>
                  StarSyncPairingSetup.created,
          onGoogleSignOut: () async {},
          onGoogleReSignIn: onGoogleReSignIn ?? () async {},
          onLocalStarCount: onLocalStarCount ?? () async => 0,
          onSetUpWithPairing:
              onSetUpWithPairing ??
              ({required resetExisting, required clearLocalStars}) async =>
                  StarSyncPairingSetup.created,
          onJoinWithCode: onJoin ?? (_, {required clearLocalStars}) async {},
          onPairingCode: () async => encodeStarSyncPairingCode(
            'AAAAAAAAAAAAAAAAAAAAAA',
            List.filled(32, 1),
          ),
          onRejoinWithCode: (_) async {},
          onResetWithPairing: () async => '',
          onSetUp:
              onSetUp ??
              (
                _,
                _, {
                required resetExisting,
                required clearLocalStars,
              }) async {},
          onSyncNow: () async {},
          onResumeKeepingLocal: onResumeKeepingLocal ?? () async {},
          onResumeDiscardingLocal: onResumeDiscardingLocal ?? () async {},
          onChangePassphrase: (_, _) async {},
          onListDevices: () async => <StarSyncDeviceInfo>[],
          onDeleteDevice: (_) async {},
          onDisable: ({deleteOwnRemoteFile = false}) async {},
          onReset: (_) async {},
          onRejoin: (_) async {},
        ),
      ),
    ),
  );

  testWidgets('account return asks before discarding local changes', (tester) async {
    var kept = 0;
    var discarded = 0;
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.accountReturned,
      ),
    );
    await tester.pumpWidget(section(
      status,
      onResumeKeepingLocal: () async { kept++; },
      onResumeDiscardingLocal: () async { discarded++; },
    ));
    expect(find.text('ログインIDが一時的に変わっていました。その間にこの端末で付け外ししたスターを同期に含めますか？'), findsOneWidget);
    await tester.tap(find.text('含めて再開'));
    await tester.pumpAndSettle();
    expect(kept, 1);
    await tester.tap(find.text('同期データの状態に戻して再開'));
    await tester.pumpAndSettle();
    expect(find.text('この端末で、その間に付け外ししたスターは元に戻ります。'), findsOneWidget);
    expect(discarded, 0);
    await tester.tap(find.text('戻して再開'));
    await tester.pumpAndSettle();
    expect(discarded, 1);
    expect(find.text('同期を無効にする'), findsOneWidget);
  });

  testWidgets('enabled state shows partial sync as a warning', (tester) async {
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.ok,
        lastError: '一部の端末のデータを読めませんでした（2台）',
      ),
    );
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status));
    expect(find.text('まだ同期していません'), findsOneWidget);
    expect(find.text('一部の端末のデータを読めませんでした（2台）'), findsOneWidget);
    status.value = const StarSyncStatusSnapshot(
      enabled: true,
      status: StarSyncStatus.ok,
    );
    await tester.pump();
    expect(find.text('一部の端末のデータを読めませんでした（2台）'), findsNothing);
  });

  testWidgets('disabled state offers setup', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot());
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status));
    expect(find.text('Google ドライブで同期'), findsNothing);
    await tester.tap(find.text('詳細設定：自分のサーバーを使う（WebDAV / S3互換）'));
    await tester.pumpAndSettle();
    expect(find.text('同期を設定'), findsOneWidget);
    await tester.pumpWidget(section(status, googleAvailable: true));
    expect(find.text('Google ドライブで同期'), findsOneWidget);
  });

  testWidgets('Google setup shows the account requirement', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot());
    addTearDown(status.dispose);
    await tester.pumpWidget(
      section(
        status,
        googleAvailable: true,
        onGoogleSignIn: ({required clearLocalStars}) async =>
            throw const StarSyncAccountRequiredException(),
      ),
    );
    await tester.tap(find.text('Google ドライブで同期'));
    await tester.pump();
    expect(find.text('同期を使うには、設定の『ログイン』でログインIDを保存してください。'), findsOneWidget);
  });

  testWidgets('setup validates passphrases and switches backend', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final status = ValueNotifier(const StarSyncStatusSnapshot());
    addTearDown(status.dispose);
    var calls = 0;
    await tester.pumpWidget(
      section(
        status,
        onSetUp:
            (_, _, {required resetExisting, required clearLocalStars}) async {
              calls++;
            },
      ),
    );
    await tester.tap(find.text('詳細設定：自分のサーバーを使う（WebDAV / S3互換）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同期を設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('接続'));
    await tester.pump();
    expect(find.text('パスフレーズは10文字以上で入力してください'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'パスフレーズ'),
      'abcdefghij',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'パスフレーズ（確認）'),
      'abcdefghik',
    );
    await tester.tap(find.text('接続'));
    await tester.pump();
    expect(find.text('パスフレーズが一致しません'), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.text('S3互換'));
    await tester.pumpAndSettle();
    expect(find.text('エンドポイント'), findsOneWidget);
    expect(find.text('リージョン'), findsOneWidget);
    expect(find.text('バケット'), findsOneWidget);
    expect(find.text('アクセスキーID'), findsOneWidget);
    expect(find.text('シークレットアクセスキー'), findsOneWidget);
  });

  testWidgets('enabled state shows last sync time', (tester) async {
    final status = ValueNotifier(
      StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.ok,
        lastSyncAt: DateTime(2026, 10, 31, 12, 34),
      ),
    );
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status));
    expect(find.text('最終同期: 2026/10/31 12:34'), findsOneWidget);
  });

  testWidgets('enabled state shows cooldown', (tester) async {
    final until = DateTime.now().add(const Duration(hours: 1));
    final status = ValueNotifier(
      StarSyncStatusSnapshot(enabled: true, cooldownUntil: until),
    );
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status));
    final hour = until.hour.toString().padLeft(2, '0');
    final minute = until.minute.toString().padLeft(2, '0');
    expect(find.text('混雑のため、$hour:$minute まで同期を控えています'), findsOneWidget);
  });

  testWidgets('needs passphrase offers rejoin', (tester) async {
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.needsPassphrase,
      ),
    );
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status));
    expect(find.widgetWithText(TextField, 'パスフレーズ'), findsOneWidget);
    expect(find.text('再接続'), findsOneWidget);
  });

  testWidgets('Google join validates and submits pairing code', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot());
    addTearDown(status.dispose);
    String? joined;
    var mismatch = true;
    final code = encodeStarSyncPairingCode(
      'AAAAAAAAAAAAAAAAAAAAAA',
      List.filled(32, 1),
    );
    await tester.pumpWidget(
      section(
        status,
        googleAvailable: true,
        onGoogleSignIn: ({required clearLocalStars}) async =>
            StarSyncPairingSetup.needsPairingCode,
        onJoin: (value, {required clearLocalStars}) async {
          if (mismatch) throw const StarSyncPairingMismatchException();
          joined = value;
        },
      ),
    );
    await tester.tap(find.text('Google ドライブで同期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('接続'));
    await tester.pump();
    expect(find.text('コードの形式が正しくありません'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '同期コード'), code);
    await tester.tap(find.text('接続'));
    await tester.pump();
    expect(find.text('コードが一致しません'), findsOneWidget);
    mismatch = false;
    await tester.tap(find.text('接続'));
    await tester.pumpAndSettle();
    expect(joined, code);
  });

  testWidgets('Google account and pairing QR are shown', (tester) async {
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(enabled: true, status: StarSyncStatus.ok),
    );
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true));
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('パスフレーズを変更'), findsNothing);
    await tester.tap(find.text('別の端末を追加'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('account mismatch offers only disable', (tester) async {
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.accountMismatch,
      ),
    );
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true));
    expect(find.text('ログインIDが同期を設定したときと違うため、同期を停止しています。'), findsOneWidget);
    expect(find.text('同期を無効にする'), findsOneWidget);
    expect(find.text('今すぐ同期'), findsNothing);
    expect(find.text('別の端末を追加'), findsNothing);
    expect(find.text('同期データをリセット'), findsNothing);
  });

  for (final replaceClipboard in [false, true]) {
    testWidgets(
      'pairing clipboard is cleared only if unchanged: $replaceClipboard',
      (tester) async {
        String? clipboard;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          } else if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': clipboard};
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final status = ValueNotifier(
          const StarSyncStatusSnapshot(
            enabled: true,
            status: StarSyncStatus.ok,
          ),
        );
        addTearDown(status.dispose);
        await tester.pumpWidget(section(status, google: true));
        await tester.tap(find.text('別の端末を追加'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('コピー'));
        await tester.pump();
        expect(clipboard, isNotEmpty);
        expect(find.text('コピーしました。60秒後にクリップボードから消去します。'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        if (replaceClipboard) clipboard = 'something else';
        await tester.pump(const Duration(seconds: 60));
        await tester.pump();
        expect(clipboard, replaceClipboard ? 'something else' : '');
      },
    );
  }

  testWidgets('pairing reset requires a new code', (tester) async {
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.needsPairingCode,
      ),
    );
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true));
    expect(find.widgetWithText(TextField, '同期コード'), findsOneWidget);
    expect(find.text('再接続'), findsOneWidget);
  });
  for (final choice in ['キャンセル', '空にして始める', '含めて同期する']) {
    testWidgets('local stars choice: $choice', (tester) async {
      final status = ValueNotifier(const StarSyncStatusSnapshot());
      addTearDown(status.dispose);
      bool? selected;
      await tester.pumpWidget(
        section(
          status,
          googleAvailable: true,
          onLocalStarCount: () async => 3,
          onGoogleSignIn: ({required clearLocalStars}) async {
            selected = clearLocalStars;
            return StarSyncPairingSetup.created;
          },
        ),
      );
      await tester.tap(find.text('Google ドライブで同期'));
      await tester.pumpAndSettle();
      expect(find.text('この端末のスター（3件）'), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(selected, choice == 'キャンセル' ? null : choice == '空にして始める');
    });
  }

  testWidgets('join reset requires confirmation and keeps local choice', (
    tester,
  ) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot());
    addTearDown(status.dispose);
    var resets = 0;
    bool? cleared;
    await tester.pumpWidget(
      section(
        status,
        googleAvailable: true,
        onLocalStarCount: () async => 1,
        onGoogleSignIn: ({required clearLocalStars}) async =>
            StarSyncPairingSetup.needsPairingCode,
        onSetUpWithPairing:
            ({required resetExisting, required clearLocalStars}) async {
              expect(resetExisting, isTrue);
              cleared = clearLocalStars;
              resets++;
              return StarSyncPairingSetup.created;
            },
      ),
    );
    await tester.tap(find.text('Google ドライブで同期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('空にして始める'));
    await tester.pumpAndSettle();
    final link = find.text('コードがない場合：同期データをリセットして新しく始める');
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(resets, 0);
    await tester.tap(find.text('キャンセル').last);
    await tester.pumpAndSettle();
    expect(resets, 0);
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(find.text('リセット'));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(cleared, isTrue);
  });

  testWidgets('lost Google sign in offers re-login', (tester) async {
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.needsGoogleSignIn,
      ),
    );
    addTearDown(status.dispose);
    var calls = 0;
    await tester.pumpWidget(
      section(
        status,
        google: true,
        onGoogleReSignIn: () async {
          calls++;
        },
      ),
    );
    expect(find.text('Google へのログインが切れました。'), findsOneWidget);
    await tester.tap(find.text('Google に再ログイン'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('同期を無効にする'), findsOneWidget);
  });

  testWidgets('add device is hidden for WebDAV', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot(enabled: true));
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status));
    expect(find.text('別の端末を追加'), findsNothing);
  });
}
