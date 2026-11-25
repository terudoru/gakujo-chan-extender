import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_report_draft_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/widgets/report_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _history = 'more_better_gakujo_download_history';
const _failures = 'more_better_gakujo_failed_downloads';
const _favorites = 'more_better_gakujo_favorites';
const _reports = 'more_better_gakujo_cached_report_lists';
const _portal = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';

// Serialized output of the generated list script for one fictional local draft.
const _draftReply =
    '[{"key":"mbg-report-draft:v2:https://example.test/sample#fictional",'
    '"version":2,"savedAt":1799999990000,"heading":"Fixture draft",'
    '"preview":"Fictional paragraph","text":"Fictional paragraph"}]';

class _Prefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

class _GoogleAuth extends Fake implements StarSyncGoogleAuth {
  @override
  String? currentEmail;

  @override
  int get generation => 0;

  @override
  Future<String?> restore({String? expectedEmail}) async => currentEmail;

  @override
  void cancelPendingSignIn() {}
}

class _Observer extends NavigatorObserver {
  final pushes = <Route<dynamic>>[];
  final pops = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops.add(route);
  }
}

class _PendingRead {
  _PendingRead(this.storageKey);
  // Drafts wait for the WebView script reply, after the journal read.
  final String? storageKey;
  final started = Completer<void>();
  final release = Completer<void>();

  Future<void> pause() async {
    started.complete();
    await release.future;
  }
}

void main() {
  testWidgets(
    'each saved-data shortcut opens a list only for its active Settings route',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      const storage = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const plugin = MethodChannel('io.jns.webview.win');
      const view = MethodChannel('io.jns.webview.win/85');
      const events = EventChannel('io.jns.webview.win/85/events');
      const notifications = MethodChannel(
        'net.yoshida.morebettergakujo/notifications',
      );
      const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      final data = {
        'more_better_gakujo_setup_completed': 'true',
        'more_better_gakujo_disabled_feature_flags': 'update_notice',
      };
      final operations = <String>[];
      final fifo = StorageOperationQueue();
      _PendingRead? pending;
      messenger.setMockMethodCallHandler(
        storage,
        (call) => fifo.run(() async {
          final key = call.arguments['key'] as String?;
          operations.add('${call.method}:$key');
          switch (call.method) {
            case 'read':
              final read = pending;
              if (read != null &&
                  read.storageKey == key &&
                  !read.started.isCompleted) {
                await read.pause();
              }
              return data[key];
            case 'containsKey':
              return data.containsKey(key);
            case 'readAll':
              return Map.of(data);
            case 'write':
              data[key!] = call.arguments['value'] as String;
            case 'delete':
              data.remove(key);
            case 'deleteAll':
              data.clear();
            default:
              throw UnsupportedError(call.method);
          }
          return null;
        }),
      );
      final loads = <String>[];
      final disposed = Completer<void>();
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, value) {
            sink = value;
          },
        ),
      );
      messenger.setMockMethodCallHandler(plugin, (call) async {
        if (call.method == 'initialize') return {'textureId': 85};
        if (call.method == 'dispose' && call.arguments == 85) {
          disposed.complete();
        }
        return null;
      });
      messenger.setMockMethodCallHandler(view, (call) async {
        if (call.method == 'loadUrl') loads.add(call.arguments as String);
        if (call.method == 'addScriptToExecuteOnDocumentCreated') {
          return 'script';
        }
        if (call.method != 'executeScript') return null;
        if (call.arguments != GakujoReportDraftScript.buildList()) {
          return jsonEncode('');
        }
        expect(
          operations,
          contains('read:more_better_gakujo_pending_draft_clear'),
        );
        final read = pending;
        if (read != null &&
            read.storageKey == null &&
            !read.started.isCompleted) {
          await read.pause();
        }
        return jsonEncode(_draftReply);
      });
      for (final channel in [
        notifications,
        downloads,
        launcher,
        SystemChannels.platform,
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      PackageInfo.setMockInitialValues(
        appName: 'Example',
        packageName: 'example.test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final observer = _Observer();
      final googleAuth = _GoogleAuth();
      final home = find.byTooltip('学務のHOMEへ').hitTestable();
      final close = find.widgetWithText(TextButton, '閉じる').hitTestable();
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder.hitTestable());
        await tester.pumpAndSettle();
      }

      Future<ModalRoute<dynamic>> settings(Finder shortcut) async {
        await tap(find.byTooltip('設定'));
        await tap(find.text('保存データ'));
        return ModalRoute.of(tester.element(shortcut))!;
      }

      final downloadsShortcut = find.widgetWithText(OutlinedButton, 'ダウンロード記録');
      Future<Finder> savedDataAction(String title, Finder shortcut) async {
        if (shortcut != downloadsShortcut) return shortcut;
        await tap(shortcut);
        return find.widgetWithText(ListTile, title);
      }

      try {
        final now = DateTime.now();
        final history = GakujoDownloadHistoryStore();
        await history.replaceHistory([
          GakujoDownloadHistoryEntry(
            fileName: 'Sample saved.pdf',
            courseName: 'Sample course',
            savedAt: now,
          ),
        ]);
        await history.replaceFailedDownloads([
          GakujoFailedDownloadEntry(
            id: 'sample',
            request: const GakujoDownloadRequest(
              url: 'https://example.test/002',
              method: 'GET',
              courseName: 'Sample course',
              fileName: 'Sample failed.pdf',
              formFields: {},
            ),
            canRetry: false,
            failedAt: now,
            errorMessage: 'Synthetic failure',
          ),
        ]);
        final activity = GakujoActivityStore();
        await activity.replaceFavorites([
          GakujoFavoritePage(
            title: 'Fixture timetable',
            url: '$_portal?page=main&tabId=sch',
            addedAt: now,
          ),
        ]);
        await activity.replaceReportLists([
          GakujoCachedReportList(
            title: 'Fixture reports',
            url: '$_portal?page=main&tabId=en',
            capturedAt: now,
            items: const ['Example assignment'],
          ),
        ]);
        final original = {
          for (final k in [_history, _failures, _favorites, _reports])
            k: data[k]!,
        };
        await tester.binding.setSurfaceSize(const Size(1400, 2300));
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: GakujoWebApp(
              localPrefsStore: _Prefs(),
              googleAuth: googleAuth,
              gakujoReachable: () async => false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        sink.success({'type': 'navigationStarting', 'value': _portal});
        await tester.idle();
        sink.success({'type': 'urlChanged', 'value': _portal});
        await tester.pumpAndSettle();

        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpAndSettle();
        await tap(find.byTooltip('設定'));
        final google = find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('Google ログイン・連携'),
        );
        if (const StarSyncGoogleAuthConfig().isAvailable) {
          // The Drive preference's file read completes outside fake time.
          for (var i = 0; i < 150 && google.evaluate().isEmpty; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(google.hitTestable(), findsOneWidget);
          await tap(google);
          await tap(find.text('キャンセル'));
          expect(google.hitTestable(), findsOneWidget);
          for (final (option, control) in [
            (
              '端末間の同期',
              find.widgetWithText(FilledButton, 'Google ドライブで同期'),
            ),
            (
              'ダウンロードの Google ドライブ保存',
              find.widgetWithText(
                SwitchListTile,
                'ダウンロードしたファイルを Google ドライブにも保存する',
              ),
            ),
          ]) {
            await tap(google);
            await tap(find.widgetWithText(ListTile, option));
            expect(control.hitTestable(), findsOneWidget);
            await tap(close);
            await tap(find.byTooltip('設定'));
          }
          await tap(close);
          googleAuth.currentEmail = 'fixture@example.test';
          await tap(find.byTooltip('設定'));
          expect(google, findsNothing);
          googleAuth.currentEmail = null;
        } else {
          expect(google, findsNothing);
        }
        await tap(close);
        await tester.binding.setSurfaceSize(const Size(1400, 2300));
        await tester.pumpAndSettle();

        for (final (title, key, marker) in [
          ('ダウンロード履歴', _history, 'Sample saved.pdf'),
          ('失敗したダウンロード', _failures, 'Sample failed.pdf'),
          ('授業ごとの資料', _history, 'Sample course'),
          ('保存済み課題一覧', _reports, 'Fixture reports'),
          ('下書き', null, 'Fixture draft'),
          ('お気に入り', _favorites, 'Fixture timetable'),
          ('データ管理', _reports, '新着情報・期限・予定'),
        ]) {
          final shortcut = switch (title) {
            'ダウンロード履歴' || '失敗したダウンロード' || '授業ごとの資料' => downloadsShortcut,
            _ => find.widgetWithText(OutlinedButton, title),
          };
          final owner = await settings(shortcut);
          final read = pending = _PendingRead(key);
          final action = await savedDataAction(title, shortcut);
          final before = observer.pushes.length;
          await tap(action);
          expect(read.started.isCompleted, isTrue, reason: title);
          expect(observer.pushes.length, before);
          final atHold = operations.length;
          if (title == '失敗したダウンロード' || title == 'データ管理') {
            expect(await tester.binding.handlePopRoute(), isTrue);
            await tester.pumpAndSettle();
          } else {
            await tester.tap(close);
            await tester.pump();
          }
          expect(observer.pops.last, same(owner));
          expect(owner.isActive, isFalse);
          if (key == null) {
            // A popped route is already inactive during its reverse animation.
            expect(owner.subtreeContext?.mounted, isTrue);
          } else {
            await tester.pumpAndSettle();
            final previousLoads = loads.length;
            await tap(home);
            expect(loads.skip(previousLoads), [gakujoHomePortalUrl]);
          }
          final newOwner = key == _favorites ? await settings(shortcut) : null;
          if (newOwner != null) await tap(shortcut);
          if (key != null) expect(operations.length, atHold, reason: title);
          final pushes = observer.pushes.length;
          read.release.complete();
          await tester.pumpAndSettle();
          expect(
            observer.pushes.length - pushes,
            newOwner == null ? 0 : 1,
            reason: title,
          );
          if (newOwner == null) {
            expect(home, findsOneWidget);
          } else {
            expect(find.text(marker).hitTestable(), findsOneWidget);
            await tap(close);
            expect(newOwner.isCurrent, isTrue);
            await tap(close);
          }

          final current = await settings(shortcut);
          final fresh = pending = _PendingRead(key);
          await tap(await savedDataAction(title, shortcut));
          expect(fresh.started.isCompleted, isTrue);
          ModalRoute<dynamic>? cover;
          if (key == _favorites) {
            await tap(find.text('このアプリについて'));
            await tap(find.text('不具合・要望を報告'));
            await tap(find.text('アプリから報告する'));
            cover = ModalRoute.of(tester.element(find.byType(ReportDialog)))!;
            expect(current.isCurrent, isFalse);
            expect(current.isActive, isTrue);
          }
          fresh.release.complete();
          await tester.pumpAndSettle();
          expect(
            find.text(marker).hitTestable(),
            findsOneWidget,
            reason: title,
          );
          if (title == 'データ管理') {
            final beforeConfirmation = List<String>.of(operations);
            await tap(find.text('この端末の保存データを削除'));
            expect(find.text('この端末の保存データを削除しますか？'), findsOneWidget);
            expect(operations, beforeConfirmation);
            await tap(find.text('キャンセル'));
            expect(operations, beforeConfirmation);
          }
          await tap(close);
          if (cover != null) {
            expect(cover.isCurrent, isTrue);
            await tap(close);
          }
          expect(current.isCurrent, isTrue);
          await tap(close);
          expect({for (final k in original.keys) k: data[k]}, original);
        }
      } finally {
        final release = pending?.release;
        if (release != null && !release.isCompleted) release.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 4));
        await tester.pumpAndSettle();
        for (var i = 0; !disposed.isCompleted && i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(disposed.isCompleted, isTrue);
        for (final channel in [
          storage,
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
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
