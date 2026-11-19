import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _reports = 'more_better_gakujo_cached_report_lists';
const _assignments = 'more_better_gakujo_assignments';
const _wholeList = 'more_better_gakujo_whole_assignment_list';
const _keys = [_reports, _assignments, _wholeList];
const _favorites = 'more_better_gakujo_favorites';
const _stars = 'more_better_gakujo_starred_messages';
const _empty = 'レポート・小テスト画面を開くと、課題一覧を保存します。';

class _Prefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;
  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

class _Pops extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

class _Gate {
  _Gate(this.method, this.key);
  final String method;
  final String key;
  bool entered = false;
  final release = Completer<void>();
}

class _Storage {
  final values = {
    'more_better_gakujo_setup_completed': 'true',
    'more_better_gakujo_disabled_feature_flags': 'update_notice',
  };
  final deletes = <String>[];
  final gates = <_Gate>[];
  final queue = StorageOperationQueue();

  _Gate hold(String method, String key) {
    final gate = _Gate(method, key);
    gates.add(gate);
    return gate;
  }

  // The Windows backend serializes every storage operation, including reads
  // and operations on unrelated keys while one of the deletes is suspended.
  Future<Object?> handle(MethodCall call) => queue.run(() async {
    final key = call.arguments['key'] as String?;
    if (call.method == 'delete' && _keys.contains(key)) deletes.add(key!);
    for (final gate in gates) {
      if (!gate.entered && gate.method == call.method && gate.key == key) {
        gate.entered = true;
        await gate.release.future;
        break;
      }
    }
    switch (call.method) {
      case 'read':
        return values[key];
      case 'containsKey':
        return values.containsKey(key);
      case 'write':
        values[key!] = call.arguments['value'] as String;
      case 'delete':
        values.remove(key);
      case 'deleteAll':
        values.clear();
      case 'readAll':
        return Map.of(values);
      default:
        throw UnsupportedError(call.method);
    }
    return null;
  });
}

void main() {
  testWidgets(
    'cached report deletion belongs to the list that started it',
    (tester) async {
      final storage = _Storage();
      final pops = _Pops();
      final loads = <String>[];
      final reminders = <List<Object?>>[];
      final store = GakujoActivityStore();
      final messenger = tester.binding.defaultBinaryMessenger;
      const plugin = MethodChannel('io.jns.webview.win');
      const view = MethodChannel('io.jns.webview.win/73');
      const events = EventChannel('io.jns.webview.win/73/events');
      const secureStorage = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const notifications = MethodChannel(
        'net.yoshida.morebettergakujo/notifications',
      );
      const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      messenger.setMockMethodCallHandler(secureStorage, storage.handle);
      messenger.setMockMethodCallHandler(
        plugin,
        (call) async => call.method == 'initialize' ? {'textureId': 73} : null,
      );
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      messenger.setMockMethodCallHandler(view, (call) async {
        if (call.method == 'loadUrl') loads.add(call.arguments as String);
        if (call.method == 'addScriptToExecuteOnDocumentCreated') {
          return 'script';
        }
        return null;
      });
      messenger.setMockMethodCallHandler(notifications, (call) async {
        if (call.method == 'scheduleReminders') {
          reminders.add(List.of(call.arguments['reminders'] as List));
          return true;
        }
        if (call.method == 'checkPermission' ||
            call.method == 'requestPermission') {
          return true;
        }
        return null;
      });
      for (final channel in [downloads, launcher, SystemChannels.platform]) {
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      PackageInfo.setMockInitialValues(
        appName: 'Example',
        packageName: 'example.test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await tester.binding.setSurfaceSize(const Size(1400, 1800));
      addTearDown(() async {
        for (final channel in [
          secureStorage,
          plugin,
          view,
          notifications,
          downloads,
          launcher,
          SystemChannels.platform,
        ]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        messenger.setMockStreamHandler(events, null);
        await tester.binding.setSurfaceSize(null);
      });

      final shortcut = find.widgetWithText(OutlinedButton, '保存済み課題一覧');
      final close = find.widgetWithText(TextButton, '閉じる').hitTestable();
      final delete = find.widgetWithText(TextButton, '削除').hitTestable();
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      final date = DateTime.now();
      Future<void> seedReports() async {
        await store.replaceReportLists([
          GakujoCachedReportList(
            title: 'Example reports',
            url: 'https://example.org/reports',
            capturedAt: date,
            items: const ['Example assignment'],
          ),
        ]);
        await store.mergeAssignments([
          GakujoAssignment(
            kind: 'レポート',
            title: 'Example assignment',
            course: 'Example course',
            status: '未提出',
            capturedAt: date,
            dueAt: date.add(const Duration(days: 4)),
          ),
        ], isWholeList: true);
        expect(_keys.every(storage.values.containsKey), isTrue);
      }

      await store.replaceStarredMessages([
        GakujoStarredMessage(
          keijitype: '1',
          genrecd: '40',
          seqNo: '2',
          title: 'Example announcement',
          starredAt: date,
        ),
      ]);
      await store.replaceFavorites([
        GakujoFavoritePage(
          title: 'Example favorite',
          url: 'https://example.org/timetable',
          addedAt: date,
        ),
      ]);
      final favorite = storage.values[_favorites]!;
      final star = storage.values[_stars]!;
      void expectUnrelatedData() {
        expect(storage.values[_favorites], favorite);
        expect(storage.values[_stars], star);
        expect(loads, hasLength(1));
        expect(tester.takeException(), isNull);
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [pops],
            home: GakujoWebApp(
              localPrefsStore: _Prefs(),
              gakujoReachable: () async => false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(find.byTooltip('設定'));
        await tap(find.text('保存データ'));
        final settings = ModalRoute.of(tester.element(shortcut))!;
        Future<void> expectClearedInSettings() async {
          expect(settings.isCurrent, isTrue);
          expect(shortcut.hitTestable(), findsOneWidget);
          expect(_keys.where(storage.values.containsKey), isEmpty);
          expect(await store.loadReportLists(), isEmpty);
          expect(await store.loadAssignments(), isEmpty);
          expect(await store.assignmentsAreWholeList(), isFalse);
          expectUnrelatedData();
          await tap(shortcut);
          expect(find.text(_empty).hitTestable(), findsOneWidget);
          await tap(close);
        }

        for (final action in ['close', 'back', 'repeat', 'stay', 'disposed']) {
          await seedReports();
          await tap(shortcut);
          final element = tester.element(find.text('Example reports'));
          final list = ModalRoute.of(element)!;
          pops.routes.clear();
          storage.deletes.clear();
          reminders.clear();
          final gate = storage.hold('delete', _reports);
          await tap(delete);
          expect(gate.entered, isTrue);
          if (action == 'repeat') {
            await tester.binding.setSurfaceSize(const Size(1350, 1800));
            await tester.pumpAndSettle();
            await tap(delete);
          }
          expect(storage.deletes, [_reports]);
          if (action == 'close' || action == 'back' || action == 'disposed') {
            if (action == 'back') {
              expect(await tester.binding.handlePopRoute(), isTrue);
            } else {
              await tester.tap(close);
            }
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 30));
            expect(pops.routes, [same(list)]);
            expect(list.isActive, isFalse);
            expect(settings.isCurrent, isTrue);
            expect(element.mounted, isTrue);
            if (action == 'disposed') {
              await tester.pumpAndSettle();
              expect(element.mounted, isFalse);
            }
          }
          gate.release.complete();
          await tester.pumpAndSettle();
          expect(pops.routes, [same(list)], reason: action);
          expect(storage.deletes, _keys, reason: action);
          expect(reminders, [isEmpty], reason: action);
          await expectClearedInSettings();
        }

        for (final failedKey in [_reports, _assignments]) {
          await seedReports();
          await tap(shortcut);
          final list = ModalRoute.of(tester.element(delete))!;
          pops.routes.clear();
          storage.deletes.clear();
          reminders.clear();
          final gate = storage.hold('delete', failedKey);
          await tap(delete);
          expect(gate.entered, isTrue);
          gate.release.completeError(
            PlatformException(code: 'example-delete-failure'),
          );
          await tester.pumpAndSettle();
          final attempted = _keys.take(_keys.indexOf(failedKey) + 1).toList();
          expect(storage.deletes, attempted);
          expect(
            _keys.where(storage.values.containsKey),
            _keys.skip(attempted.length - 1),
          );
          expect(reminders, isEmpty);
          expect(pops.routes, isEmpty);
          expect(list.isCurrent, isTrue);
          expect(
            find
                .text('削除できませんでした')
                .evaluate()
                .where((e) => ModalRoute.of(e) == settings),
            hasLength(1),
          );
          expectUnrelatedData();
          await tap(delete);
          expect(storage.deletes, [...attempted, ..._keys]);
          expect(reminders, [isEmpty]);
          expect(pops.routes, [same(list)]);
          await expectClearedInSettings();
        }

        // Two taps on Settings can start two list reads before either dialog
        // opens. Let the second read finish over the first dialog's pending Delete.
        await seedReports();
        final firstRead = storage.hold('read', _reports);
        final secondRead = storage.hold('read', _reports);
        await tap(shortcut);
        expect(firstRead.entered, isTrue);
        await tap(shortcut);
        firstRead.release.complete();
        await tester.pumpAndSettle();
        expect(secondRead.entered, isTrue);
        final older = ModalRoute.of(tester.element(delete))!;
        final firstDelete = storage.hold('delete', _reports);
        final secondDelete = storage.hold('delete', _reports);
        storage.deletes.clear();
        reminders.clear();
        pops.routes.clear();
        await tap(delete);
        secondRead.release.complete();
        await tester.pumpAndSettle();
        final newer = ModalRoute.of(tester.element(delete))!;
        expect(newer, isNot(same(older)));
        expect(older.isActive, isTrue);
        expect(newer.isCurrent, isTrue);
        expect(firstDelete.entered, isTrue);
        await tap(delete);
        firstDelete.release.complete();
        await tester.pumpAndSettle();
        expect(secondDelete.entered, isTrue);
        expect(storage.deletes, [..._keys, _reports]);
        expect(pops.routes, isEmpty);
        expect(newer.isCurrent, isTrue);
        secondDelete.release.complete();
        await tester.pumpAndSettle();
        expect(pops.routes, [same(newer)]);
        expect(older.isCurrent, isTrue);
        expect(storage.deletes, [..._keys, ..._keys]);
        expect(reminders, [isEmpty, isEmpty]);
        await tap(close);
        expect(pops.routes, [same(newer), same(older)]);
        await expectClearedInSettings();
      } finally {
        for (final gate in storage.gates) {
          if (!gate.release.isCompleted) gate.release.complete();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 4));
        await tester.pumpAndSettle();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
