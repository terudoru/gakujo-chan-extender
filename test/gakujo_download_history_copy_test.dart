import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _success = '保存場所をコピーしました';
const _failure = '保存場所をコピーできませんでした';
const _openError = 'Unable to open clipboard';
const _setError = 'Unable to set clipboard data';
const _previous = 'Previous clipboard text';
const _course = 'Example course';
const _plainPath = r'Q:\Example course\第 2 回 %20.pdf';
const _files = {
  'file.pdf': (
    location: 'file:///Example%20Folder/%E8%B3%87%E6%96%99%20A%2BB.pdf',
    label: '/Example Folder/資料 A+B.pdf',
  ),
  'content.pdf': (
    location:
        'content://com.android.externalstorage.documents/'
        'tree/primary%3ADownload/document/primary%3ADownload%2F'
        '%E8%B3%87%E6%96%99%20A.pdf',
    label: '内部ストレージ/Download/資料 A.pdf',
  ),
  'plain.pdf': (location: _plainPath, label: _plainPath),
};

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'saved location feedback follows the clipboard reply in both lists',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      const plugin = MethodChannel('io.jns.webview.win');
      const view = MethodChannel('io.jns.webview.win/84');
      const events = EventChannel('io.jns.webview.win/84/events');
      const notifications = MethodChannel(
        'net.yoshida.morebettergakujo/notifications',
      );
      const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      var viewDisposed = false;
      messenger.setMockMethodCallHandler(plugin, (call) async {
        if (call.method == 'initialize') return {'textureId': 84};
        if (call.method == 'dispose' && call.arguments == 84) {
          viewDisposed = true;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        view,
        (call) async => call.method == 'addScriptToExecuteOnDocumentCreated'
            ? 'script'
            : null,
      );
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      for (final channel in [notifications, downloads, launcher]) {
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      final writes = <String>[];
      var clipboard = _previous;
      Completer<void>? gate;
      String? rejection;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method != 'Clipboard.setData') return null;
        final text = call.arguments['text'] as String;
        writes.add(text);
        if (gate != null) await gate!.future;
        if (rejection != null) {
          // A write can fail after Windows has emptied the clipboard.
          if (rejection == _setError) clipboard = '';
          throw PlatformException(
            code: 'Clipboard error',
            message: rejection,
            details: 1,
          );
        }
        clipboard = text;
        return null;
      });

      final storage = {
        'more_better_gakujo_setup_completed': 'true',
        'more_better_gakujo_disabled_feature_flags': 'update_notice',
      };
      FlutterSecureStorage.setMockInitialValues(storage);
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
        FlutterSecureStorage.setMockInitialValues({});
        await tester.binding.setSurfaceSize(null);
      });

      final store = GakujoDownloadHistoryStore();
      final now = DateTime.now();
      await store.replaceHistory([
        for (final file in _files.entries)
          GakujoDownloadHistoryEntry(
            fileName: file.key,
            courseName: _course,
            savedAt: now,
            location: file.value.location,
          ),
        GakujoDownloadHistoryEntry(
          fileName: 'missing.pdf',
          courseName: _course,
          savedAt: now,
        ),
      ]);
      await GakujoActivityStore().replaceFavorites([
        GakujoFavoritePage(
          title: 'Example favorite',
          url: 'https://example.org/course',
          addedAt: now,
        ),
      ]);
      const historyKey = 'more_better_gakujo_download_history';
      const favoritesKey = 'more_better_gakujo_favorites';
      final history = storage[historyKey]!;
      final favorites = storage[favoritesKey]!;
      expect(await store.load(), hasLength(4));
      expect(favorites, contains('Example favorite'));

      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> reply() async {
        gate!.complete();
        await tester.pump();
        await tester.pumpAndSettle();
        gate = null;
      }

      Future<void> unmount() async {
        final app = tester.element(find.byType(GakujoWebApp));
        await tester.pumpWidget(const SizedBox());
        expect(app.mounted, isFalse);
        await tester.pump(const Duration(minutes: 4));
        // WebView initialization may still be waiting on a real asset read.
        for (var i = 0; !viewDisposed && i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(viewDisposed, isTrue);
      }

      try {
        // The app's shared storage queues need one widget-test clock across mounts.
        for (final shortcut in ['ダウンロード履歴', '授業ごとの資料']) {
          final button = find.widgetWithText(OutlinedButton, 'ダウンロード記録');
          final pops = _Pops();
          late ModalRoute<dynamic> settings;
          Future<void> openSettings() async {
            await tap(find.byTooltip('設定'));
            await tap(find.text('保存データ'));
            settings = ModalRoute.of(tester.element(button))!;
          }

          Future<void> mount() async {
            viewDisposed = false;
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
            await openSettings();
          }

          Future<void> copy(String name) async {
            await tap(button);
            final option = find.widgetWithText(ListTile, shortcut);
            final chooser = ModalRoute.of(tester.element(option))!;
            final previousPops = List.of(pops.routes);
            final previousWrites = List.of(writes);
            await tap(option);
            if (shortcut == '授業ごとの資料') await tap(find.text(_course));
            Finder row(String name) => find.ancestor(
              of: find.text(name),
              matching: find.byType(ListTile),
            );
            Finder icon(String name) => find.descendant(
              of: row(name),
              matching: find.byTooltip('保存場所をコピー'),
            );
            final label = _files[name]!.label;
            expect(row('missing.pdf'), findsOneWidget);
            expect(icon('missing.pdf'), findsNothing);
            expect(
              find.descendant(
                of: row(name),
                matching: find.textContaining(label),
              ),
              findsOneWidget,
            );
            final dialog = ModalRoute.of(tester.element(icon(name)))!;
            await tap(icon(name));
            expect(writes, [...previousWrites, label]);
            expect(pops.routes, [...previousPops, same(chooser), same(dialog)]);
            expect(settings.isCurrent, isTrue);
            expect(button.hitTestable(), findsOneWidget);
          }

          final success = find.text(_success).hitTestable();
          final failure = find.text(_failure).hitTestable();
          const file = 'file.pdf';
          final label = _files[file]!.label;
          clipboard = _previous;
          await mount();
          gate = Completer<void>();
          await copy(file);
          expect(clipboard, _previous);
          expect(success, findsNothing);
          expect(failure, findsNothing);
          await reply();
          expect(clipboard, label);
          expect(success, findsOneWidget);
          expect(pops.routes, hasLength(2));

          for (final file in _files.entries) {
            await copy(file.key);
            expect(clipboard, file.value.label);
            expect(success, findsOneWidget);
          }
          for (final message in [_openError, _setError]) {
            clipboard = _previous;
            rejection = message;
            gate = Completer<void>();
            await copy(file);
            final beforeReply = List.of(pops.routes);
            await reply();
            expect(clipboard, message == _openError ? _previous : '');
            expect(success, findsNothing);
            expect(failure, findsOneWidget);
            expect(pops.routes, beforeReply);
            expect(tester.takeException(), isNull);
            rejection = null;
            await copy(file);
            expect(clipboard, label);
            expect(success, findsOneWidget);
            expect(failure, findsNothing);
          }

          for (final dispose in [false, true]) {
            for (final reject in [false, true]) {
              clipboard = _previous;
              rejection = reject ? _openError : null;
              gate = Completer<void>();
              await copy(file);
              final previousPops = List.of(pops.routes);
              if (dispose) {
                await unmount();
              } else {
                expect(await tester.binding.handlePopRoute(), isTrue);
                await tester.pumpAndSettle();
              }
              expect(settings.isActive, isFalse);
              await reply();
              expect(clipboard, reject ? _previous : label);
              expect(pops.routes, [
                ...previousPops,
                if (!dispose) same(settings),
              ]);
              expect(tester.takeException(), isNull);
              if (dispose) {
                expect(success, findsNothing);
                expect(failure, findsNothing);
                if (!reject) await mount();
              } else {
                await openSettings();
              }
            }
          }
          rejection = null;
          expect(storage[historyKey], history);
          expect(storage[favoritesKey], favorites);
          expect(tester.takeException(), isNull);
        }
      } finally {
        if (gate?.isCompleted == false) gate!.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 4));
        await tester.pumpAndSettle();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
