import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/widgets/star_sync_section.dart';
import 'package:morebettergakujo_flutter/src/widgets/settings_sections.dart';

void main() {
  Widget section(
    ValueNotifier<StarSyncStatusSnapshot> status, {
    bool boundEmailMissing = false,
    bool Function(String)? collectionEnabled,
    Future<void> Function(String, bool)? onCollectionChanged,
    bool googleAvailable = false,
    bool google = false,
    ValueChanged<bool>? onBusyChanged,
    Future<void> Function()? onBackup,
    Future<List<StarSyncBackupInfo>> Function()? onListBackups,
    Future<void> Function(String)? onRestoreBackup,
    Future<StarSyncDriveSetup> Function({
      required Map<String, String> clearLocalStars,
      required String expectedAccount,
      required int expectedGeneration,
    })?
    onGoogleSignIn,
    Future<int> Function()? onLocalStarCount,
    Future<Map<String, int?>> Function()? onLocalCollectionCounts,
    Future<Map<String, String>> Function()? onSnapshotLocalStars,
    Future<void> Function()? onGoogleReSignIn,
    Future<void> Function()? onGoogleSignOut,
    VoidCallback? onGoogleCancelSignIn,
    Future<void> Function()? onResumeKeepingLocal,
    Future<void> Function()? onResumeDiscardingLocal,
    Future<StarSyncDriveSetup> Function({
      required bool resetExisting,
      required Map<String, String> clearLocalStars,
      required String expectedAccount,
      required int expectedGeneration,
    })?
    onSetUpWithDrive,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: StarSyncSection(
          status: status,
          onBusyChanged: onBusyChanged,
          onBackup: onBackup,
          onListBackups: onListBackups,
          onRestoreBackup: onRestoreBackup,
          collectionEnabled: collectionEnabled,
          onCollectionChanged: onCollectionChanged,
          googleAvailable: googleAvailable,
          googleEmail: () => boundEmailMissing
              ? null
              : google
              ? 'user@example.com'
              : null,
          onGoogleSignIn:
              onGoogleSignIn ??
              ({
                required clearLocalStars,
                required expectedAccount,
                required expectedGeneration,
              }) async => StarSyncDriveSetup.created,
          onGoogleSignOut: onGoogleSignOut ?? () async {},
          onGoogleReSignIn: onGoogleReSignIn ?? () async {},
          onGoogleCancelSignIn: onGoogleCancelSignIn,
          onLocalStarCount: onLocalStarCount ?? () async => 0,
          onLocalCollectionCounts: onLocalCollectionCounts,
          onSnapshotLocalStars:
              onSnapshotLocalStars ?? () async => {'id': 'time'},
          onRequireAccount: () => 'account',
          onAccountGeneration: () => 7,
          onSetUpWithDrive:
              onSetUpWithDrive ??
              ({
                required resetExisting,
                required clearLocalStars,
                required expectedAccount,
                required expectedGeneration,
              }) async => StarSyncDriveSetup.created,
          onResetWithDrive: () async {},
          onSyncNow: () async {},
          onResumeKeepingLocal: onResumeKeepingLocal ?? () async {},
          onResumeDiscardingLocal: onResumeDiscardingLocal ?? () async {},
          onListDevices: () async => <StarSyncDeviceInfo>[],
          onDeleteDevice: (_) async {},
          onDisable: ({deleteOwnRemoteFile = false}) async {},
        ),
      ),
    ),
  );

  testWidgets('backup actions list and select backups', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot(enabled: true));
    addTearDown(status.dispose);
    var uploads = 0;
    String? selected;
    await tester.pumpWidget(
      section(
        status,
        onBackup: () async {
          uploads++;
        },
        onListBackups: () async => [
          const StarSyncBackupInfo(deviceId: 'a', isThisDevice: true),
          const StarSyncBackupInfo(deviceId: 'b', isThisDevice: false),
        ],
        onRestoreBackup: (id) async {
          selected = id;
        },
      ),
    );
    await tester.ensureVisible(find.text('今すぐバックアップ'));
    await tester.tap(find.text('今すぐバックアップ'));
    await tester.pumpAndSettle();
    expect(uploads, 1);
    await tester.tap(find.text('バックアップから復元'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('他の端末'));
    expect(find.text('この端末'), findsOneWidget);
    await tester.tap(find.text('他の端末'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('バックアップから復元しますか？'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('他の端末'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('復元する'));
    await tester.pumpAndSettle();
    expect(selected, 'b');
  });

  testWidgets('Drive download switch renders value and invokes callback', (tester) async {
    bool? requested;
    Widget drive(bool value) => MaterialApp(home: Scaffold(body: DriveDownloadSwitch(
      value: value, signingIn: false, enabled: true, onChanged: (value) => requested = value,
    )));
    await tester.pumpWidget(drive(false));
    await tester.tap(find.byType(SwitchListTile));
    expect(requested, isTrue);
    await tester.pumpWidget(drive(true));
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });

  testWidgets('busy is set while an action runs and cleared on dispose', (
    tester,
  ) async {
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.accountReturned,
      ),
    );
    final busy = <bool>[];
    final pending = Completer<void>();
    await tester.pumpWidget(
      section(
        status,
        onBusyChanged: busy.add,
        onResumeKeepingLocal: () => pending.future,
      ),
    );
    await tester.tap(find.text('含めて再開'));
    await tester.pump();
    expect(busy, [true]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(busy, [true, false]);
    pending.complete();
    await tester.pump();
    expect(busy, [true, false]);
    status.dispose();
  });

  testWidgets('collection switches invoke the callback', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot(enabled: true));
    final enabled = <String, bool>{};
    await tester.pumpWidget(
      section(
        status,
        collectionEnabled: (name) => enabled[name] ?? true,
        onCollectionChanged: (name, value) async {
          enabled[name] = value;
        },
      ),
    );
    for (final entry in const {
      'favorites': 'お気に入り',
      'settings': '設定',
      'report-drafts': 'レポート下書き',
      'notified-deadlines': '通知済みの締切',
    }.entries) {
      await tester.ensureVisible(find.byKey(ValueKey(entry.key)));
      expect(find.text(entry.value), findsOneWidget);
      await tester.tap(find.byKey(ValueKey(entry.key)));
      await tester.pumpAndSettle();
      expect(enabled[entry.key], isFalse);
    }
    status.dispose();
  });

  testWidgets('account return asks before discarding local changes', (
    tester,
  ) async {
    var kept = 0;
    var discarded = 0;
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.accountReturned,
      ),
    );
    await tester.pumpWidget(
      section(
        status,
        onResumeKeepingLocal: () async {
          kept++;
        },
        onResumeDiscardingLocal: () async {
          discarded++;
        },
      ),
    );
    expect(
      find.text('ログインIDが一時的に変わっていました。その間にこの端末で付け外ししたスターを同期に含めますか？'),
      findsOneWidget,
    );
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
    expect(find.text('このビルドでは Google ドライブ同期を使えません。'), findsOneWidget);
    expect(find.textContaining('共用の端末'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
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
        onGoogleSignIn: ({
          required clearLocalStars,
          required expectedAccount,
          required expectedGeneration,
        }) async => throw const StarSyncAccountRequiredException(),
      ),
    );
    await tester.tap(find.text('Google ドライブで同期'));
    await tester.pumpAndSettle();
    // The local data choice is always asked now (settings always exist).
    await tester.tap(find.text('含めて同期する'));
    await tester.pumpAndSettle();
    expect(find.text('同期を使うには、設定の「ログイン」でログインIDを保存してください。'), findsOneWidget);
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

  testWidgets('account mismatch offers only disable', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot(
      enabled: true, status: StarSyncStatus.accountMismatch,
    ));
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true));
    expect(find.text('ログインIDが同期を設定したときと違うため、同期を停止しています。'), findsOneWidget);
    expect(find.text('同期を無効にする'), findsOneWidget);
    expect(find.text('今すぐ同期'), findsNothing);
    expect(find.text('同期データをリセット'), findsNothing);
  });

  testWidgets('legacy data offers recreation', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot(
      enabled: true, status: StarSyncStatus.needsLegacyReset,
    ));
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true));
    expect(find.textContaining('古い方式で保存されているか壊れているため'), findsOneWidget);
    expect(find.text('作り直す'), findsOneWidget);
  });

  testWidgets('Google account appears without an add-device action', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot(enabled: true));
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true));
    expect(find.textContaining('user@example.com'), findsOneWidget);
    expect(find.text('別の端末を追加'), findsNothing);
  });

  testWidgets('cancelling legacy recreation signs out', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot());
    addTearDown(status.dispose);
    var signedOut = false;
    await tester.pumpWidget(section(
      status,
      googleAvailable: true,
      onGoogleSignIn: ({required clearLocalStars, required expectedAccount,
        required expectedGeneration}) async => StarSyncDriveSetup.needsLegacyReset,
      onGoogleSignOut: () async { signedOut = true; },
    ));
    await tester.tap(find.text('Google ドライブで同期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('含めて同期する'));
    await tester.pumpAndSettle();
    expect(find.text('以前の同期データが見つかりました'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });
  testWidgets('shows collection counts even with no stars', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot());
    addTearDown(status.dispose);
    await tester.pumpWidget(
      section(
        status,
        googleAvailable: true,
        onLocalCollectionCounts: () async => {
          'favorites': 2,
          'settings': 6,
          'report-drafts': null,
          'notified-deadlines': 4,
        },
      ),
    );
    await tester.tap(find.text('Google ドライブで同期'));
    await tester.pumpAndSettle();
    expect(find.textContaining('お気に入り（2件）'), findsOneWidget);
    expect(find.textContaining('下書き（未確認件）'), findsOneWidget);
    expect(find.text('空にして始める'), findsOneWidget);
  });

  for (final choice in ['キャンセル', '空にして始める', '含めて同期する']) {
    testWidgets('local stars choice: $choice', (tester) async {
      final status = ValueNotifier(const StarSyncStatusSnapshot());
      addTearDown(status.dispose);
      Map<String, String>? selected;
      var captures = 0;
      await tester.pumpWidget(
        section(
          status,
          googleAvailable: true,
          onLocalStarCount: () async => 3,
          onSnapshotLocalStars: () async {
            captures++;
            return {'id': 'time'};
          },
          onGoogleSignIn:
              ({
                required clearLocalStars,
                required expectedAccount,
                required expectedGeneration,
              }) async {
                selected = clearLocalStars;
                expect(expectedAccount, 'account');
                expect(expectedGeneration, 7);
                return StarSyncDriveSetup.created;
              },
        ),
      );
      await tester.tap(find.text('Google ドライブで同期'));
      await tester.pumpAndSettle();
      expect(find.text('この端末のスター（3件）'), findsOneWidget);
      expect(captures, 0);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(captures, choice == '空にして始める' ? 1 : 0);
      expect(
        selected,
        choice == 'キャンセル'
            ? null
            : choice == '空にして始める'
            ? {'id': 'time'}
            : isEmpty,
      );
    });
  }

  testWidgets('join reset requires confirmation and keeps local choice', (
    tester,
  ) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot());
    addTearDown(status.dispose);
    var resets = 0;
    Map<String, String>? cleared;
    await tester.pumpWidget(
      section(
        status,
        googleAvailable: true,
        onLocalStarCount: () async => 1,
        onGoogleSignIn: ({
          required clearLocalStars,
          required expectedAccount,
          required expectedGeneration,
        }) async => StarSyncDriveSetup.needsLegacyReset,
        onSetUpWithDrive:
            ({
              required resetExisting,
              required clearLocalStars,
              required expectedAccount,
              required expectedGeneration,
            }) async {
              expect(expectedAccount, 'account');
              expect(expectedGeneration, 7);
              expect(resetExisting, isTrue);
              cleared = clearLocalStars;
              resets++;
              return StarSyncDriveSetup.created;
            },
      ),
    );
    await tester.tap(find.text('Google ドライブで同期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('空にして始める'));
    await tester.pumpAndSettle();
    expect(find.text('以前の同期データが見つかりました'), findsOneWidget);
    expect(resets, 0);
    await tester.tap(find.text('作り直す'));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(cleared, {'id': 'time'});
  });

  testWidgets('desktop initial sign-in can be cancelled', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
    final status = ValueNotifier(const StarSyncStatusSnapshot(enabled: false));
    addTearDown(status.dispose);
    final pending = Completer<StarSyncDriveSetup>();
    var cancelled = false;
    await tester.pumpWidget(section(status, googleAvailable: true,
      onGoogleSignIn: ({required clearLocalStars, required expectedAccount,
          required expectedGeneration}) => pending.future,
      onGoogleCancelSignIn: () {
        cancelled = true;
        pending.completeError(const StarSyncGoogleAuthException(
          StarSyncGoogleAuthErrorKind.cancelled));
      },
    ));
    await tester.tap(find.text('Google ドライブで同期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('含めて同期する'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('キャンセル'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pump();
    expect(cancelled, isTrue);
    expect(find.text('Google へのログインに失敗しました'), findsNothing);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  testWidgets('desktop re-sign-in can be cancelled', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
    final status = ValueNotifier(const StarSyncStatusSnapshot(
      enabled: true, status: StarSyncStatus.needsGoogleSignIn));
    addTearDown(status.dispose);
    final pending = Completer<void>();
    var cancelled = false;
    await tester.pumpWidget(section(status, google: true,
      onGoogleReSignIn: () => pending.future,
      onGoogleCancelSignIn: () {
        cancelled = true;
        pending.completeError(const StarSyncGoogleAuthException(
          StarSyncGoogleAuthErrorKind.cancelled));
      },
    ));
    await tester.tap(find.text('Google に再ログイン'));
    await tester.pump();
    expect(find.text('キャンセル'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pump();
    expect(cancelled, isTrue);
    expect(find.text('キャンセル'), findsNothing);
    expect(find.text('Google へのログインに失敗しました'), findsNothing);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  testWidgets('desktop Drive download permission can be cancelled', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DriveDownloadSwitch(
      value: false, signingIn: true, enabled: true, onChanged: (_) {},
      onCancel: () => cancelled = true,
    ))));
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    expect(cancelled, isTrue);
  });

  testWidgets('Google permission error is shown', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot(
      enabled: true, status: StarSyncStatus.needsGoogleSignIn));
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true,
      onGoogleReSignIn: () async => throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.permissionDenied),
    ));
    await tester.tap(find.text('Google に再ログイン'));
    await tester.pump();
    expect(find.text('Google ドライブへのアクセスが許可されませんでした。同意画面でチェックを入れて、もう一度お試しください'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    testWidgets('Google storage error is shown on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final status = ValueNotifier(const StarSyncStatusSnapshot(
          enabled: true, status: StarSyncStatus.needsGoogleSignIn));
        addTearDown(status.dispose);
        await tester.pumpWidget(section(status, google: true,
          onGoogleReSignIn: () async => throw const StarSyncGoogleAuthException(
            StarSyncGoogleAuthErrorKind.storageUnavailable),
        ));
        await tester.tap(find.text('Google に再ログイン'));
        await tester.pump();
        expect(find.text(platform == TargetPlatform.linux
          ? 'ログイン情報を安全に保管するサービス（GNOME Keyring や KWallet など）を使えないため、Google にログインできません。保管サービスを有効にしてから、もう一度お試しください'
          : 'この端末の安全な保存領域を使えないため、Google にログインできません'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('lost Google sign in names the account sync uses', (tester) async {
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.needsGoogleSignIn,
      ),
    );
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true));
    expect(find.text('同期に使うアカウント: user@example.com'), findsOneWidget);
  });

  testWidgets('settings with no recorded account send the student to re-setup', (tester) async {
    final status = ValueNotifier(
      const StarSyncStatusSnapshot(
        enabled: true,
        status: StarSyncStatus.needsGoogleSignIn,
      ),
    );
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true, boundEmailMissing: true));
    expect(find.textContaining('再ログインできません'), findsOneWidget);
    expect(find.text('Google に再ログイン'), findsNothing);
    expect(find.text('同期を無効にする'), findsOneWidget);
  });

  testWidgets('sync screen says how to change the account', (tester) async {
    final status = ValueNotifier(const StarSyncStatusSnapshot(enabled: true));
    addTearDown(status.dispose);
    await tester.pumpWidget(section(status, google: true));
    expect(find.textContaining('別のアカウントにするには、同期を無効にしてから'), findsOneWidget);
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


}
