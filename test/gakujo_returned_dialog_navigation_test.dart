import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_message_list_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_message_star_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/history_marker.g.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

const _portal = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
const _home = '${_portal}campusportal.do?page=main&tabId=home';
const _detail =
    '${_portal}campussquare.do?_flowExecutionKey=public'
    '&_eventId=confirm&keijitype=1&genrecd=40&seqNo=2';
const _favorite = '${_portal}campusportal.do?page=main&tabId=sch';
const _report = '${_portal}campusportal.do?page=main&tabId=en';
const _listKeys = {
  'starred': 'more_better_gakujo_starred_messages',
  'favorites': 'more_better_gakujo_favorites',
  'cachedReports': 'more_better_gakujo_cached_report_lists',
};
final _back = find.byTooltip('前のページ');
final _forward = find.byTooltip('次のページ');
final _return = find.byTooltip('ページに戻る');
final _homeButton = find.byTooltip('学務のHOMEへ');
final _stars = find.byTooltip('スター付き連絡通知');

class _Prefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;
  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

class _HeldRead {
  _HeldRead(this.key);
  final String key;
  final started = Completer<void>();
  final released = Completer<void>();
}

// The widget host uses the secure-storage method channel. Serialize all six
// operations as Windows does, including the entire wait inside a held read.
class _Storage {
  final data = {
    'more_better_gakujo_setup_completed': 'true',
    'more_better_gakujo_disabled_feature_flags': 'update_notice',
  };
  final queue = StorageOperationQueue();
  final holds = <_HeldRead>[];

  _HeldRead hold(String kind) {
    final read = _HeldRead(_listKeys[kind]!);
    holds.add(read);
    return read;
  }

  Future<Object?> handle(MethodCall call) => queue.run(() async {
    final key = call.arguments['key'] as String?;
    switch (call.method) {
      case 'read':
        for (final hold in holds) {
          if (hold.key == key && !hold.started.isCompleted) {
            hold.started.complete();
            await hold.released.future;
            break;
          }
        }
        return data[key];
      case 'write':
        data[key!] = call.arguments['value'] as String;
      case 'containsKey':
        return data.containsKey(key);
      case 'delete':
        data.remove(key);
      case 'deleteAll':
        data.clear();
      case 'readAll':
        return Map.of(data);
      default:
        throw UnsupportedError(call.method);
    }
    return null;
  });
}

class _Page {
  _Page(this.tester);
  final WidgetTester tester;
  final storage = _Storage();
  final loads = <String>[];
  final history = <String>[];
  final markerByUrl = <String, String>{};
  final reads = <String>[];
  final probes = <String>[];
  final deliveredNotifications = <MethodCall>[];
  List<Map<String, String>>? messageItems;
  bool messageListComplete = false;
  int assignmentFetches = 0;
  int messageFetches = 0;
  var reloads = 0;
  var disposed = false;
  var document = '';
  late MockStreamHandlerEventSink events;

  Future<void> mount() async {
    const plugin = MethodChannel('io.jns.webview.win');
    const view = MethodChannel('io.jns.webview.win/73');
    const stream = EventChannel('io.jns.webview.win/73/events');
    const notifications = MethodChannel(
      'net.yoshida.morebettergakujo/notifications',
    );
    const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
    final messenger = tester.binding.defaultBinaryMessenger;
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    messenger.setMockMethodCallHandler(secureStorage, storage.handle);
    messenger.setMockMethodCallHandler(plugin, (call) async {
      if (call.method == 'initialize') return {'textureId': 73};
      if (call.method == 'dispose') disposed = true;
      return null;
    });
    messenger.setMockMethodCallHandler(view, handle);
    messenger.setMockStreamHandler(
      stream,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          events = sink;
        },
      ),
    );
    for (final channel in [
      notifications,
      downloads,
      SystemChannels.platform,
      launcher,
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
    if (messageItems != null) {
      messenger.setMockMethodCallHandler(notifications, (call) async {
        if (call.method == 'requestPermission' ||
            call.method == 'checkPermission') {
          return true;
        }
        if (call.method == 'notifyDeadline') {
          deliveredNotifications.add(call);
          return true;
        }
        return null;
      });
    }
    addTearDown(() async {
      for (final channel in [
        plugin,
        view,
        notifications,
        downloads,
        secureStorage,
        SystemChannels.platform,
        launcher,
      ]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      messenger.setMockStreamHandler(stream, null);
      await tester.binding.setSurfaceSize(null);
    });
    final store = GakujoActivityStore();
    final date = DateTime.now();
    await store.replaceStarredMessages([
      GakujoStarredMessage(
        keijitype: '1',
        genrecd: '40',
        seqNo: '2',
        title: 'Beta',
        starredAt: date,
      ),
    ]);
    await store.replaceFavorites([
      GakujoFavoritePage(
        title: 'Fixture timetable',
        url: _favorite,
        addedAt: date,
      ),
    ]);
    await store.replaceReportLists([
      GakujoCachedReportList(
        title: 'Fixture reports',
        url: _report,
        capturedAt: date,
        items: const ['Example assignment'],
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(1400, 1800));
    await tester.pumpWidget(
      MaterialApp(
        home: GakujoWebApp(
          localPrefsStore: _Prefs(),
          gakujoReachable: () async => false,
        ),
      ),
    );
    await waitFor('startup load', () => loads.isNotEmpty);
    await finish(loads.single);
  }

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'loadUrl':
        loads.add(call.arguments as String);
      case 'goBack':
      case 'goForward':
        history.add(call.method);
      case 'reload':
        reloads++;
      case 'addScriptToExecuteOnDocumentCreated':
        return 'script';
      case 'executeScript':
        final script = call.arguments as String;
        if (messageItems != null && script == gakujoAssignmentListFetchScript) {
          assignmentFetches++;
          if (assignmentFetches > 1) {
            throw PlatformException(code: 'fixture-assignment-fetch');
          }
          return jsonEncode(jsonEncode({'status': 'missing'}));
        }
        if (messageItems != null &&
            script == gakujoKeywordMessageListFetchScript) {
          messageFetches++;
          return jsonEncode(
            jsonEncode(
              messageItems!.isEmpty
                  ? {'status': 'error'}
                  : {
                      'status': 'ok',
                      'items': messageItems,
                      'complete': messageListComplete,
                    },
            ),
          );
        }
        if (script ==
            GakujoMessageStarScript.buildOpen(
              keijitype: '1',
              genrecd: '40',
              seqNo: '2',
            )) {
          return jsonEncode(jsonEncode({'status': 'ok', 'url': _detail}));
        }
        for (final kind in _listKeys.keys) {
          if (script ==
              gakujoHistoryMarkerJs({'action': 'stamp-dialog', 'kind': kind})) {
            markerByUrl[document] = kind;
            return jsonEncode('ok');
          }
        }
        if (script == gakujoHistoryMarkerJs({'action': 'read'})) {
          reads.add(document);
          return jsonEncode(
            jsonEncode({
              'dialog': markerByUrl[document],
              'preview': null,
              'active': 'none',
              'activeToken': null,
            }),
          );
        }
        if (script == gakujoPortalAuthStateProbeScript) {
          probes.add(document);
          return jsonEncode({'hasAuthenticatedMarker': true});
        }
        return jsonEncode('');
    }
    return null;
  }

  Future<void> waitFor(String what, bool Function() condition) async {
    for (var i = 0; i < 150; i++) {
      if (condition()) return;
      // Page-finish asset reads also need real event-loop turns.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for $what');
  }

  Future<void> finish(String url, {bool storageHeld = false}) async {
    Future<void> emit(String type, Object value) async {
      events.success({'type': type, 'value': value});
      await tester.idle();
    }

    final initialProbes = probes.length;
    final initialReads = reads.length;
    document = url;
    await emit('navigationStarting', url);
    await emit('urlChanged', url);
    await emit('historyChanged', {'canGoBack': true, 'canGoForward': true});
    await emit('loadingStateChanged', windows.LoadingState.loading.index);
    await emit(
      'loadingStateChanged',
      windows.LoadingState.navigationCompleted.index,
    );
    await waitFor(
      'accepted completion of $url',
      () => probes.skip(initialProbes).contains(url),
    );
    if (!storageHeld) {
      await waitFor(
        'page-finish marker read for $url',
        () => reads.skip(initialReads).contains(url),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder target) async {
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> select(String kind) async {
    final before = loads.length;
    if (kind == 'starred') {
      await tap(_stars);
      expect(_return, findsNothing);
      await tap(find.text('Beta'));
    } else {
      await tap(find.byTooltip('設定'));
      await tap(find.text('保存データ'));
      final favorite = kind == 'favorites';
      await tap(
        find.widgetWithText(OutlinedButton, favorite ? 'お気に入り' : '保存済み課題一覧'),
      );
      expect(_return, findsNothing);
      await tap(find.text(favorite ? 'Fixture timetable' : 'Fixture reports'));
      if (!favorite) await tap(find.text('開く'));
      await tap(find.text('閉じる'));
    }
    final url = {
      'starred': _detail,
      'favorites': _favorite,
      'cachedReports': _report,
    }[kind]!;
    expect(loads.skip(before), [url]);
    await finish(url);
    expect(markerByUrl[url], kind);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  Future<_HeldRead> startReturn(String kind) async {
    final read = storage.hold(kind);
    await tap(_back);
    await waitFor('queued $kind read', () => read.started.isCompleted);
    expect(find.byType(AlertDialog), findsNothing);
    return read;
  }

  Future<void> homeWhileReading() async {
    final before = loads.length;
    await tap(_homeButton);
    expect(loads.skip(before), [_home]);
    await finish(_home, storageHeld: true);
  }
}

Future<void> _verifyBackgroundMessageScan(WidgetTester tester) async {
  final app = _Page(tester)..messageItems = [];
  final now = DateTime.now();
  app.storage.data['more_better_gakujo_message_notification'] = jsonEncode(
    GakujoMessageNotificationSettings(
      mode: GakujoMessageNotificationMode.keywords,
      keywords: const ['教材'],
      since: now.subtract(const Duration(minutes: 2)),
    ).toJson(),
  );
  final posted = now
      .toUtc()
      .add(const Duration(hours: 9))
      .subtract(const Duration(seconds: 30))
      .toIso8601String()
      .substring(0, 19)
      .replaceAll('-', '/')
      .replaceFirst('T', ' ');
  try {
    await app.mount();
    await app.waitFor('first message list error', () => app.messageFetches > 0);
    expect(app.assignmentFetches, greaterThan(0));
    expect(app.deliveredNotifications, isEmpty);
    final beforeRetry = app.messageFetches;

    app.messageItems = [
      {
        'title': '資料を公開しました',
        'url': _detail,
        'text': '$posted 資料を公開しました - 授業連絡 教材担当',
      },
    ];
    await app.finish(_home);
    await app.waitFor(
      'keyword notification',
      () => app.deliveredNotifications.isNotEmpty,
    );
    expect(app.assignmentFetches, greaterThan(1));
    expect(app.messageFetches, greaterThan(beforeRetry));
    expect(app.deliveredNotifications.single.arguments['title'], '資料を公開しました');
    final assignmentAttempts = app.assignmentFetches;
    final messageAttempts = app.messageFetches;
    await app.finish(_favorite);
    await app.waitFor(
      'assignment retry',
      () => app.assignmentFetches > assignmentAttempts,
    );
    expect(app.messageFetches, messageAttempts);
    expect(app.deliveredNotifications, hasLength(1));
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }
}

Future<void> _verifyKeywordReadReconciliation(
  WidgetTester tester, {
  required bool complete,
}) async {
  const historyKey = 'more_better_gakujo_notified_deadline_keys';
  final now = DateTime.now();
  final posted = now
      .toUtc()
      .add(const Duration(hours: 9))
      .subtract(const Duration(seconds: 30))
      .toIso8601String()
      .substring(0, 19)
      .replaceAll('-', '/')
      .replaceFirst('T', ' ');
  final cached = GakujoDeadlineEntry(
    title: '教材の公開',
    url: _detail.replaceFirst('seqNo=2', 'seqNo=3'),
    dueText: '$posted 教材の公開',
    detectedAt: now,
    kind: 'notice',
    source: '連絡通知',
  );
  final app = _Page(tester)
    ..messageListComplete = complete
    ..messageItems = [
      {
        'title': '別の連絡',
        'url': _detail,
        'text': '$posted 別の連絡',
      },
    ];
  app.storage.data['more_better_gakujo_deadlines'] = jsonEncode([
    cached.toJson(),
  ]);
  app.storage.data['more_better_gakujo_message_notification'] = jsonEncode(
    GakujoMessageNotificationSettings(
      mode: GakujoMessageNotificationMode.keywords,
      keywords: const ['教材'],
      since: now.subtract(const Duration(minutes: 2)),
    ).toJson(),
  );
  try {
    await app.mount();
    await app.waitFor(
      'notification history after keyword scan (complete: $complete)',
      () => app.storage.data.containsKey(historyKey),
    );
    await tester.pumpAndSettle();
    expect(
      jsonDecode(app.storage.data[historyKey]!),
      contains(gakujoMessageNotificationKey(cached.url)),
    );
    if (complete) {
      expect(app.deliveredNotifications, isEmpty);
    } else {
      expect(app.deliveredNotifications.single.arguments['title'], cached.title);
    }
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'returned lists belong to the initiating navigation',
    (tester) async {
      // Shared app futures must stay on one widget-test clock across mounts.
      Future<void> journey(Future<void> Function(_Page) exercise) async {
        final app = _Page(tester);
        try {
          await app.mount();
          await exercise(app);
          expect(tester.takeException(), isNull);
        } finally {
          for (final hold in app.storage.holds) {
            if (!hold.released.isCompleted) hold.released.complete();
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(minutes: 4));
          await tester.pumpAndSettle();
        }
      }

      for (final kind in _listKeys.keys) {
        // HOME remains usable after each kind of delayed list read.
        await journey((app) async {
          await app.select(kind);
          final saved = app.storage.data[_listKeys[kind]];
          final read = await app.startReturn(kind);
          await app.tap(_back);
          await app.homeWhileReading();
          final before = app.reads.length;
          read.released.complete();
          // No history button or delayed browser traversal runs on HOME here.
          await app.waitFor(
            'final HOME marker',
            () => app.reads.skip(before).contains(_home),
          );
          await app.tester.pumpAndSettle();
          expect(_return, findsNothing);
          expect(_homeButton.hitTestable(), findsOneWidget);
          expect(app.storage.data[_listKeys[kind]], saved);
          expect(app.history, isEmpty);
        });
      }

      // A same-URL reload abandons the old returned list.
      await journey((app) async {
        await app.select('starred');
        final read = await app.startReturn('starred');
        await app.tap(find.byTooltip('再読み込み'));
        expect(app.reloads, 1);
        await app.finish(_detail, storageHeld: true);
        final before = app.reads.length;
        read.released.complete();
        await app.waitFor(
          'reloaded page marker',
          () => app.reads.length > before,
        );
        await app.tester.pumpAndSettle();
        expect(_return, findsNothing);
        await app.tap(_back);
        expect(_return.hitTestable(), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);
      });

      // Old cleanup preserves the pending return on the new revision.
      await journey((app) async {
        await app.select('favorites');
        final old = await app.startReturn('favorites');
        await app.tap(find.byTooltip('再読み込み'));
        expect(app.reloads, 1);
        await app.finish(_favorite, storageHeld: true);
        final current = app.storage.hold('favorites');
        await app.tap(_back);
        old.released.complete();
        await app.waitFor(
          'new favorites read',
          () => current.started.isCompleted,
        );
        expect(_return, findsNothing);
        await app.tap(_forward);
        expect(app.history, isEmpty);
        await app.tap(_back);
        current.released.complete();
        await app.tester.pumpAndSettle();
        expect(_return.hitTestable(), findsOneWidget);
        expect(find.text('Fixture timetable'), findsOneWidget);
        await app.tap(_return);
        expect(find.byType(AlertDialog), findsNothing);
      });

      // The current page coalesces Back and Forward until the route opens.
      await journey((app) async {
        await app.select('starred');
        final read = await app.startReturn('starred');
        await app.tap(_back);
        await app.tap(_forward);
        read.released.complete();
        await app.tester.pumpAndSettle();
        expect(_return.hitTestable(), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);
        final mouse = await app.tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kForwardMouseButton,
        );
        await mouse.down(app.tester.getCenter(find.byType(AlertDialog)));
        await mouse.up();
        await app.tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(app.history, isEmpty);
      });

      // Disposal during the read leaves no returned route.
      await journey((app) async {
        await app.select('starred');
        final read = await app.startReturn('starred');
        await app.tester.pumpWidget(const SizedBox());
        await app.waitFor('WebView disposal', () => app.disposed);
        read.released.complete();
        await app.tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(app.history, isEmpty);
      });

      // Ordinary toolbar opening survives navigation during its read.
      await journey((app) async {
        final read = app.storage.hold('starred');
        await app.tap(_stars);
        await app.waitFor(
          'ordinary starred read',
          () => read.started.isCompleted,
        );
        await app.homeWhileReading();
        read.released.complete();
        await app.tester.pumpAndSettle();
        expect(find.text('Beta'), findsOneWidget);
        expect(_return, findsNothing);
        await app.tap(find.text('閉じる'));
        expect(_homeButton.hitTestable(), findsOneWidget);
      });

      for (final direction in ['goBack', 'goForward']) {
        // Both ordinary browser history actions work while the old read is held.
        await journey((app) async {
          await app.select('starred');
          final read = await app.startReturn('starred');
          await app.homeWhileReading();
          await app.tap(direction == 'goBack' ? _back : _forward);
          expect(app.history, [direction]);
          read.released.complete();
          await app.tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        });
      }

      // Exercise the message scan on the same fake clock as the other mounts.
      await _verifyBackgroundMessageScan(tester);
      await _verifyKeywordReadReconciliation(tester, complete: true);
      await _verifyKeywordReadReconciliation(tester, complete: false);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
