import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/download_destination_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';

void main() {
  testWidgets('notification denial warning follows permission and app settings',
      (tester) async {
    final permission = ValueNotifier<bool?>(null);
    final keywords = TextEditingController();
    addTearDown(permission.dispose);
    addTearDown(keywords.dispose);
    var opened = 0;

    Future<void> show(
        {bool enabled = true, bool canOpenSettings = true}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotificationTopicsSection(
              topics: const {},
              messages: const GakujoMessageNotificationSettings(),
              notificationsEnabled: enabled,
              notificationPermission: permission,
              onOpenNotificationSettings: canOpenSettings
                  ? () {
                      opened += 1;
                    }
                  : null,
              onChanged: (_, __) {},
              onMessagesChanged: (_) async {},
              keywordController: keywords,
              canAddKeyword: false,
              onKeywordInputChanged: (_) {},
              preferences: const GakujoNotificationPreferences(),
              onPreferencesChanged: (_) async {},
              knownCourses: const [],
            ),
          ),
        ),
      ));
    }

    final warning = find.text('端末の設定で通知が許可されていません');
    final button = find.text('端末の通知設定を開く');
    await show();
    expect(warning, findsNothing);
    expect(button, findsNothing);
    permission.value = false;
    await tester.pump();
    expect(warning, findsOneWidget);
    await tester.tap(button);
    expect(opened, 1);
    permission.value = true;
    await tester.pump();
    expect(warning, findsNothing);
    expect(button, findsNothing);
    permission.value = false;
    await show(enabled: false);
    expect(warning, findsNothing);
    expect(button, findsNothing);
    await show(canOpenSettings: false);
    expect(warning, findsOneWidget);
    expect(button, findsNothing);
    permission.value = null;
    await tester.pump();
    expect(warning, findsNothing);
  });

  test('queued topic and preference saves preserve the latest local settings',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('notification_prefs_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final local = GakujoLocalPrefsStore(directory: directory);
    final operations = StorageOperationQueue();
    var settings = const GakujoAppSettings();
    final savingTopics = Completer<void>();
    final topicsStarted = Completer<void>();
    var preferencesStarted = false;
    final topicSave = saveGakujoSettingsChange(
      operations: operations,
      save: () async {
        topicsStarted.complete();
        await savingTopics.future;
      },
      currentSettings: () => settings,
      update: (latest) => latest.copyWith(
        notificationTopics: {GakujoNotificationTopic.other},
      ),
      apply: (latest) => settings = latest,
      mirror: local.saveAppSettings,
    );
    await topicsStarted.future;
    // Another kind of setting completes while the topic save is awaiting I/O.
    settings = settings.copyWith(
      disabledFeatureFlags: {GakujoFeatureFlag.uploadCompression},
    );
    await local.saveAppSettings(settings);
    final preferenceSave = operations.run(() => saveGakujoSettingsChange(
          save: () async {
            preferencesStarted = true;
            await local.saveAppSettings(settings.copyWith(
              notificationPreferences: const GakujoNotificationPreferences(
                reminderOffsets: {GakujoReminderOffset.threeHours},
              ),
            ));
          },
          currentSettings: () => settings,
          update: (latest) => latest.copyWith(
            notificationPreferences: const GakujoNotificationPreferences(
              reminderOffsets: {GakujoReminderOffset.threeHours},
            ),
          ),
          apply: (latest) => settings = latest,
          mirror: (_) async {},
        ));
    await Future<void>.delayed(Duration.zero);
    expect(preferencesStarted, isFalse);
    savingTopics.complete();
    await Future.wait([topicSave, preferenceSave]);

    final persisted = (await local.load())!.appSettings!;
    for (final actual in [settings, persisted]) {
      expect(actual.notificationTopics, {GakujoNotificationTopic.other});
      expect(
          actual.disabledFeatureFlags, {GakujoFeatureFlag.uploadCompression});
      expect(actual.notificationPreferences.reminderOffsets,
          {GakujoReminderOffset.threeHours});
    }
  });

  test('overlapping feature toggles merge before a pending mirror completes',
      () async {
    var settings = const GakujoAppSettings();
    final firstSave = Completer<void>();
    final secondSave = Completer<void>();
    final firstMirror = Completer<void>();
    final mirrorStarted = Completer<void>();
    final mirrored = <GakujoAppSettings>[];
    Future<void> toggle(GakujoFeatureFlag flag, Future<void> save) {
      return saveGakujoSettingsChange(
        save: () => save,
        currentSettings: () => settings,
        update: (latest) => latest.copyWith(
          disabledFeatureFlags: {...latest.disabledFeatureFlags, flag},
        ),
        apply: (latest) => settings = latest,
        mirror: (latest) async {
          mirrored.add(latest);
          if (mirrored.length == 1) {
            mirrorStarted.complete();
            await firstMirror.future;
          }
        },
      );
    }

    final first = toggle(GakujoFeatureFlag.messageStars, firstSave.future);
    final second =
        toggle(GakujoFeatureFlag.uploadCompression, secondSave.future);
    firstSave.complete();
    await mirrorStarted.future;
    secondSave.complete();
    await second;
    firstMirror.complete();
    await first;

    final expected = {
      GakujoFeatureFlag.messageStars,
      GakujoFeatureFlag.uploadCompression,
    };
    expect(settings.disabledFeatureFlags, expected);
    expect(mirrored.last.disabledFeatureFlags, expected);
  });

  test('failed notification preference save retains the saved settings',
      () async {
    var settings = const GakujoAppSettings(
      notificationPreferences: GakujoNotificationPreferences(
        reminderOffsets: {GakujoReminderOffset.threeHours},
      ),
    );
    final savedPreferences = settings.notificationPreferences;
    var mirrorCalls = 0;
    final failure = StateError('storage unavailable');
    await expectLater(
      saveGakujoSettingsChange(
        save: () async => throw failure,
        currentSettings: () => settings,
        update: (latest) => latest.copyWith(
          notificationPreferences: const GakujoNotificationPreferences(),
        ),
        apply: (latest) => settings = latest,
        mirror: (_) async {
          mirrorCalls++;
        },
      ),
      throwsA(same(failure)),
    );
    expect(settings.notificationPreferences, same(savedPreferences));
    expect(mirrorCalls, 0);
  });

  testWidgets(
      'deleting a keyword preserves the draft and only a saved add clears it',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var messages = const GakujoMessageNotificationSettings(
      mode: GakujoMessageNotificationMode.keywords,
      keywords: ['アンケート'],
    );
    var input = '';
    final addSave = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SingleChildScrollView(
            child: NotificationTopicsSection(
              topics: const {},
              messages: messages,
              notificationsEnabled: true,
              onChanged: (_, __) {},
              onMessagesChanged: (next) async {
                if (next.keywords.contains('集中講義')) await addSave.future;
                setState(() => messages = next);
              },
              keywordController: controller,
              canAddKeyword: input.trim().isNotEmpty,
              onKeywordInputChanged: (value) => setState(() => input = value),
              preferences: const GakujoNotificationPreferences(),
              onPreferencesChanged: (_) async {},
              knownCourses: const [],
            ),
          );
        }),
      ),
    ));
    await tester.enterText(find.byType(TextField), '集中講義');
    await tester.pump();
    tester
        .widget<InputChip>(find.widgetWithText(InputChip, 'アンケート'))
        .onDeleted!();
    await tester.pump();
    expect(messages.keywords, isEmpty);
    expect(controller.text, '集中講義');
    expect(input, '集中講義');

    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '追加'))
        .onPressed!();
    await tester.pump();
    expect(controller.text, '集中講義');
    addSave.complete();
    await tester.pump();
    expect(messages.keywords, ['集中講義']);
    expect(controller.text, isEmpty);
    expect(input, isEmpty);
  });

  testWidgets(
      'backup restore requires confirmation and cancellation does nothing',
      (tester) async {
    for (final confirm in [false, true]) {
      var restored = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (await showGakujoBackupRestoreConfirmation(context) ==
                    true) {
                  restored = true;
                }
              },
              child: const Text('読み込み'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('バックアップから復元しますか？'), findsOneWidget);
      expect(
        find.text('現在の設定、スター、通知履歴、ダウンロード履歴はバックアップの内容に置き換えられます。'),
        findsOneWidget,
      );
      expect(restored, isFalse);
      await tester.tap(find.text(confirm ? '復元する' : 'キャンセル'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(restored, confirm);
    }
  });

  test('credential save returns the values captured before storage completes',
      () async {
    final store = _PendingLoginSettingsStore();
    var loginId = ' student-a ';
    var password = 'password-a';
    final saving = saveGakujoLoginCredentials(
      store: store,
      loginId: loginId,
      password: password,
    );
    loginId = 'student-b';
    password = 'password-b';
    store.release.complete();
    final runtimeCredentials = await saving;

    expect(store.saved?.loginId, 'student-a');
    expect(store.saved?.password, 'password-a');
    expect(runtimeCredentials.loginId, store.saved?.loginId);
    expect(runtimeCredentials.password, store.saved?.password);
    expect(runtimeCredentials.loginId, isNot(loginId));
    expect(runtimeCredentials.password, isNot(password));
  });

  testWidgets('rapid reminder toggles compose while the first save is pending',
      (tester) async {
    var preferences = const GakujoNotificationPreferences();
    final firstSave = Completer<void>();
    final saves = <GakujoNotificationPreferences>[];
    final operations = StorageOperationQueue();
    final pending = <Future<void>>[];
    final keywords = TextEditingController();
    addTearDown(keywords.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NotificationTopicsSection(
            topics: const {},
            messages: const GakujoMessageNotificationSettings(),
            notificationsEnabled: true,
            onChanged: (_, __) {},
            onMessagesChanged: (_) async {},
            keywordController: keywords,
            canAddKeyword: false,
            onKeywordInputChanged: (_) {},
            preferences: preferences,
            onPreferencesChanged: (update) {
              preferences = update(preferences);
              final snapshot = preferences;
              final saved = operations.run(() async {
                saves.add(snapshot);
                if (saves.length == 1) await firstSave.future;
              });
              pending.add(saved);
              return saved;
            },
            knownCourses: const [],
          ),
        ),
      ),
    ));

    // Both callbacks come from the same build, before the first save completes.
    tester
        .widget<FilterChip>(find.widgetWithText(FilterChip, '3日前'))
        .onSelected!(true);
    tester
        .widget<FilterChip>(find.widgetWithText(FilterChip, '3時間前'))
        .onSelected!(true);
    await tester.pump();
    expect(saves, hasLength(1));
    expect(preferences.reminderOffsets, GakujoReminderOffset.values.toSet());
    firstSave.complete();
    await tester.pump();
    await Future.wait(pending);
    expect(saves, hasLength(2));
    expect(saves.first.reminderOffsets,
        isNot(contains(GakujoReminderOffset.threeHours)));
    expect(saves.last.reminderOffsets, GakujoReminderOffset.values.toSet());
  });

  for (final secretOnly in [false, true]) {
    testWidgets(
        '${secretOnly ? '2FA' : 'login'} input survives lazy list disposal',
        (tester) async {
      final loginId = TextEditingController();
      final password = TextEditingController();
      final secret = TextEditingController();
      final scroll = ScrollController();
      addTearDown(() {
        loginId.dispose();
        password.dispose();
        secret.dispose();
        scroll.dispose();
      });
      var loginIdInput = '';
      var passwordInput = '';
      var secretInput = '';
      List<String>? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: scroll,
            // A zero cache makes scrolling dispose off-screen fields, which
            // this test needs; the replacement API is not on stable yet.
            // ignore: deprecated_member_use
            cacheExtent: 0,
            itemCount: 30,
            itemBuilder: (_, index) {
              if (index != 0) return const SizedBox(height: 200);
              if (secretOnly) {
                return TwoFactorSecretSection(
                  controller: secret,
                  canSave: true,
                  onChanged: (value) => secretInput = value,
                  onClear: () async {},
                  onSave: () async {
                    saved = [secretInput];
                  },
                );
              }
              return LoginCredentialsSection(
                loginIdController: loginId,
                passwordController: password,
                isConfigured: false,
                canSave: true,
                onLoginIdChanged: (value) => loginIdInput = value,
                onPasswordChanged: (value) => passwordInput = value,
                onClear: () async {},
                onSave: () async {
                  saved = [loginIdInput, passwordInput];
                },
              );
            },
          ),
        ),
      ));
      final expected =
          secretOnly ? ['JBSWY3DPEHPK3PXP'] : ['student-a', 'secret-a'];
      for (var i = 0; i < expected.length; i += 1) {
        await tester.enterText(find.byType(TextField).at(i), expected[i]);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      scroll.jumpTo(2500);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      for (var i = 0; i < expected.length; i += 1) {
        expect(
          tester
              .widget<TextField>(find.byType(TextField).at(i))
              .controller
              ?.text,
          expected[i],
        );
      }
      await tester.tap(find.widgetWithText(
          FilledButton, secretOnly ? '秘密鍵を保存' : 'ログイン情報を保存'));
      await tester.pump();
      expect(saved, expected);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  group('parseCalendarDate', () {
    test('accepts supported valid date formats', () {
      expect(parseCalendarDate('2026/01/02'), DateTime(2026, 1, 2));
      expect(parseCalendarDate(' 2026-1-2 '), DateTime(2026, 1, 2));
    });

    test('completes two-digit years as 2000s', () {
      expect(parseCalendarDate('26/01/02'), DateTime(2026, 1, 2));
    });

    test('rejects nonexistent and out-of-range dates', () {
      expect(parseCalendarDate('2026/02/31'), isNull);
      expect(parseCalendarDate('2026/13/01'), isNull);
      expect(parseCalendarDate('2026/00/10'), isNull);
      expect(parseCalendarDate('2026/01/00'), isNull);
      expect(parseCalendarDate('2026/01/32'), isNull);
    });

    test('handles leap days', () {
      expect(parseCalendarDate('2024/02/29'), DateTime(2024, 2, 29));
      expect(parseCalendarDate('2023/02/29'), isNull);
    });

    test('rejects unsupported formats', () {
      expect(parseCalendarDate('2026.01.02'), isNull);
      expect(parseCalendarDate('2026/1'), isNull);
      expect(parseCalendarDate('not-a-date'), isNull);
    });
  });

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

  test('isMissingKeychainEntitlementError detects iOS entitlement failures',
      () {
    expect(
      isMissingKeychainEntitlementError(
        PlatformException(
          code: '-34018',
          message: "A required entitlement isn't present.",
        ),
      ),
      isTrue,
    );
    expect(
      isMissingKeychainEntitlementError(
        PlatformException(code: 'timeout', message: 'Keychain timed out'),
      ),
      isFalse,
    );
  });

  test('iOS keychain recovery guidance never references macOS utilities', () {
    final guidance = secureStorageRecoveryGuidance(
      PlatformException(
        code: '-34018',
        message: "A required entitlement isn't present.",
      ),
      platform: TargetPlatform.iOS,
    );

    expect(guidance, contains('アプリを最新版へ更新'));
    expect(guidance, isNot(contains('キーチェーンアクセス.app')));
    expect(guidance, isNot(contains('再試行')));
    expect(guidance, isNot(contains('保存データをリセット')));
  });

  test('macOS keychain recovery guidance retains Keychain Access steps', () {
    final guidance = secureStorageRecoveryGuidance(
      PlatformException(code: 'errSecUserCanceled', message: 'User canceled'),
      platform: TargetPlatform.macOS,
    );

    expect(guidance, contains('キーチェーンアクセス.app'));
    expect(guidance, contains('再試行'));
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

  test('activity bell toolbar button is removed', () {
    expect(activityBellToolbarButtonEnabled, isFalse);
  });

  test('edge swipes map to browser back and forward navigation', () {
    expect(
      gakujoEdgeSwipeNavigation(
        startX: 8,
        viewportWidth: 400,
        delta: const Offset(100, 12),
      ),
      GakujoHistoryNavigation.back,
    );
    expect(
      gakujoEdgeSwipeNavigation(
        startX: 392,
        viewportWidth: 400,
        delta: const Offset(-100, 12),
      ),
      GakujoHistoryNavigation.forward,
    );
    expect(
      gakujoEdgeSwipeNavigation(
        startX: 200,
        viewportWidth: 400,
        delta: const Offset(120, 0),
      ),
      isNull,
    );
    expect(
      gakujoEdgeSwipeNavigation(
        startX: 8,
        viewportWidth: 400,
        delta: const Offset(100, 100),
      ),
      isNull,
    );
  });

  test('transient app messages time out even when they have an action', () {
    final snackBar = buildTransientGakujoSnackBar(
      '保存しました',
      action: SnackBarAction(label: '開く', onPressed: () {}),
    );

    expect(snackBar.duration, const Duration(seconds: 7));
    expect(snackBar.persist, isFalse);
  });

  test('toolbar exposes every documented Gakujo quick jump', () {
    expect(
      GakujoQuickJumpDestination.values.map((destination) => destination.label),
      ['成績', 'レポート', '連絡通知', 'ダウンロード', 'シラバス', 'スケジュール'],
    );
  });

  test('toolbar quick jumps target their fixed desktop portal tabs', () {
    const tabIds = {
      GakujoQuickJumpDestination.grades: 'si',
      GakujoQuickJumpDestination.reports: 'en',
      GakujoQuickJumpDestination.messages: 'kj',
      GakujoQuickJumpDestination.downloads: 'sd',
      GakujoQuickJumpDestination.syllabus: 'sy',
      GakujoQuickJumpDestination.schedule: 'sch',
    };

    expect(GakujoQuickJumpDestination.values, tabIds.keys);
    for (final entry in tabIds.entries) {
      expect(entry.key.portalTabId, entry.value);
      expect(
        entry.key.portalUrl,
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
        'campusportal.do?page=main&tabId=${entry.value}',
      );
    }
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

  testWidgets('toolbar reload button is always visible and compact',
      (tester) async {
    var reloadCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 40,
            actions: [
              GakujoReloadAction(
                enabled: true,
                onReload: () {
                  reloadCount += 1;
                },
              ),
            ],
          ),
        ),
      ),
    );

    final reloadButton = find.widgetWithIcon(IconButton, Icons.refresh);
    expect(tester.getSize(reloadButton), const Size(40, 40));
    expect(find.byTooltip('再読込'), findsOneWidget);
    await tester.tap(reloadButton);
    expect(reloadCount, 1);
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

  testWidgets('message exclude keyword input takes focus when section opens',
      (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsExpansionSection(
            title: '連絡通知フィルタ',
            icon: Icons.filter_alt_outlined,
            focusNodeOnExpand: focusNode,
            child: MessageExcludeKeywordsSection(
              keywords: const [],
              controller: controller,
              focusNode: focusNode,
              canAdd: false,
              onChanged: (_) {},
              onAdd: () async {},
              onRemove: (_) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('連絡通知フィルタ'));
    await tester.pumpAndSettle();

    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.focusNode.hasFocus, isTrue);

    tester.testTextInput.enterText('集中講義');
    await tester.pump();
    expect(controller.text, '集中講義');
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
    var importedFromFile = false;
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
            onImportSettingsFromFile: () async {
              importedFromFile = true;
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
    expect(find.text('ファイルから読み込み'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'アップデートを確認'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'バックアップ作成'));
    await tester.tap(find.widgetWithText(OutlinedButton, '設定をコピー'));
    await tester.tap(find.widgetWithText(OutlinedButton, '設定を読み込み'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'ファイルから読み込み'));
    await tester.tap(find.widgetWithText(OutlinedButton, '保存先を確認'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'エラー報告パッケージ作成'));
    await tester.tap(find.widgetWithText(TextButton, '診断情報をコピー'));
    await tester.pump();

    expect(checkedUpdates, isTrue);
    expect(createdBackup, isTrue);
    expect(createdReport, isTrue);
    expect(exported, isTrue);
    expect(imported, isTrue);
    expect(importedFromFile, isTrue);
    expect(checked, isTrue);
    expect(diagnostics, isTrue);
  });

  testWidgets('update check button reports progress and blocks duplicate taps',
      (tester) async {
    final pendingCheck = Completer<void>();
    var checkCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMaintenanceSection(
            onCheckUpdates: () {
              checkCount += 1;
              return pendingCheck.future;
            },
            onCreateBackup: () async {},
            onCreateErrorReport: () async {},
            onExportSettings: () async {},
            onImportSettings: () async {},
            onImportSettingsFromFile: () async {},
            onCheckDownloadDestination: () async {},
            onCopyDiagnostics: () async {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'アップデートを確認'),
    );
    await tester.pump();
    expect(find.text('確認中...'), findsOneWidget);
    expect(checkCount, 1);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '確認中...'),
          )
          .onPressed,
      isNull,
    );

    pendingCheck.complete();
    await tester.pumpAndSettle();
    expect(find.text('アップデートを確認'), findsOneWidget);
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
            onShowDrafts: () async => calls.add('drafts'),
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
    await tester.tap(find.widgetWithText(OutlinedButton, '下書き'));
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
        'drafts',
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

class _PendingLoginSettingsStore extends GakujoAppSettingsStore {
  final release = Completer<void>();
  GakujoLoginCredentials? saved;

  @override
  Future<void> saveLoginCredentials({
    required String loginId,
    required String password,
  }) async {
    await release.future;
    saved = GakujoLoginCredentials(loginId: loginId, password: password);
  }
}
