import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  test('favorite read failure throws without writing and a retry succeeds',
      () async {
    final storage = _FailingSecureStorage();
    final store = GakujoActivityStore(secureStorage: storage);
    final original = GakujoFavoritePage(
      title: 'Existing page',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/existing',
      addedAt: DateTime.now(),
    );
    final added = GakujoFavoritePage(
      title: 'New page',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/new-page',
      addedAt: DateTime.now(),
    );
    await store.addFavorite(original);
    final saved = Map<String, String>.from(storage.values);
    final writes = storage.writeAttempts;
    storage.failReads = true;

    await expectLater(store.addFavorite(added), throwsA(isA<StateError>()));

    expect(storage.values, saved);
    expect(storage.writeAttempts, writes);
    storage.failReads = false;
    await store.addFavorite(added);
    expect((await store.loadFavorites()).map((page) => page.url),
        unorderedEquals([original.url, added.url]));
  });

  test(
      'dialog read failure is distinct from successfully reading empty history',
      () async {
    final storage = _FailingSecureStorage()..failReads = true;
    final store = GakujoDownloadHistoryStore(secureStorage: storage);
    final messages = <String>[];

    final failed = await readGakujoSavedData(
      store.load,
      showSnackBar: messages.add,
    );

    expect(failed, isNull);
    expect(messages, [
      '保存データを読み込めませんでした。しばらくしてからもう一度お試しください',
    ]);
    expect(storage.writeAttempts, 0);
    storage.failReads = false;
    final empty = await readGakujoSavedData(
      store.load,
      showSnackBar: messages.add,
    );
    expect(empty, isEmpty);
    expect(messages, hasLength(1));
    expect(storage.writeAttempts, 0);
  });

  test('failed settings save preserves memory and mirror and skips its action',
      () async {
    final storage = _FailingSecureStorage()..failWrites = true;
    final store = GakujoAppSettingsStore(secureStorage: storage);
    const original = GakujoAppSettings();
    var settings = original;
    final mirrored = <GakujoAppSettings>[];
    final messages = <String>[];
    var actions = 0;

    Future<void> saveAndAct() async {
      final saved = await saveGakujoSettingsSafely(
        () => saveGakujoSettingsChange(
          save: () => store.savePageMode(GakujoPageMode.mobile),
          currentSettings: () => settings,
          update: (latest) => latest.copyWith(pageMode: GakujoPageMode.mobile),
          apply: (latest) => settings = latest,
          mirror: (latest) async => mirrored.add(latest),
        ),
        showSnackBar: messages.add,
      );
      if (saved) actions++;
    }

    await saveAndAct();
    expect(settings, same(original));
    expect(mirrored, isEmpty);
    expect(storage.values, isEmpty);
    expect(actions, 0);
    expect(messages, [
      '設定を保存できませんでした。しばらくしてからもう一度お試しください',
    ]);

    storage.failWrites = false;
    await saveAndAct();
    expect(settings.pageMode, GakujoPageMode.mobile);
    expect(mirrored.single, same(settings));
    expect(actions, 1);
    expect(messages, hasLength(1));
  });

  testWidgets('failed notification keyword save keeps the draft for retry',
      (tester) async {
    final storage = _FailingSecureStorage()..failWrites = true;
    final store = GakujoAppSettingsStore(secureStorage: storage);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    const original = GakujoMessageNotificationSettings(
      mode: GakujoMessageNotificationMode.keywords,
      keywords: ['既存'],
    );
    var messages = original;
    var input = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SingleChildScrollView(
            child: NotificationTopicsSection(
              topics: const {},
              messages: messages,
              notificationsEnabled: true,
              onChanged: (_, _) {},
              onMessagesChanged: (next) async {
                final saved = await saveGakujoSettingsSafely(
                  () => store.saveMessageNotification(next),
                  showSnackBar: (message) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  },
                );
                if (saved) setState(() => messages = next);
                return saved;
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
    final addButton = find.widgetWithText(FilledButton, '追加');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(messages, same(original));
    expect(controller.text, '集中講義');
    expect(input, '集中講義');
    expect(storage.values, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('設定を保存できませんでした。しばらくしてからもう一度お試しください'), findsOneWidget);
    expect(tester.takeException(), isNull);

    storage.failWrites = false;
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(messages.keywords, ['既存', '集中講義']);
    expect(controller.text, isEmpty);
    expect(input, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _FailingSecureStorage extends FlutterSecureStorage {
  bool failReads = false;
  bool failWrites = false;
  int writeAttempts = 0;
  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failReads) throw PlatformException(code: 'read_failed');
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writeAttempts++;
    // A Windows write first reads the existing store and can fail there.
    if (failWrites) throw PlatformException(code: 'read_failed');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
