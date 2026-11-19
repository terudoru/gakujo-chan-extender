import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_message_star_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/history_marker.g.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

const _portal = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
const _home = '${_portal}campusportal.do?page=main&tabId=home';
const _favorite = '${_portal}campusportal.do?page=main&tabId=sch';
const _starsKey = 'more_better_gakujo_starred_messages';
const _titles = {'1': 'Alpha', '2': 'Beta'};
const _plugin = MethodChannel('io.jns.webview.win');
const _notifications = MethodChannel(
  'net.yoshida.morebettergakujo/notifications',
);
const _downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');

String _detail(String seqNo) =>
    '${_portal}campussquare.do?_flowExecutionKey=public&_eventId=confirm'
    '&keijitype=1&genrecd=40&seqNo=$seqNo';

class _Prefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

class _Journey {
  _Journey(this.tester, this.textureId);

  final int textureId;
  late final view = MethodChannel('io.jns.webview.win/$textureId');
  late final eventChannel = EventChannel(
    'io.jns.webview.win/$textureId/events',
  );

  final WidgetTester tester;
  final firstReply = Completer<String>();
  final lookups = <String>[];
  final loads = <String>[];
  final stamps = <(String, String)>[];
  final dialogByPage = <String, String>{};
  final storage = {
    'more_better_gakujo_setup_completed': 'true',
    'more_better_gakujo_disabled_feature_flags': 'update_notice',
  };
  late final String savedRows;
  late MockStreamHandlerEventSink events;
  var document = _home;
  var historyReads = 0;
  var webViewBacks = 0;
  var viewDisposed = false;

  Future<void> mount() async {
    FlutterSecureStorage.setMockInitialValues(storage);
    final store = GakujoActivityStore();
    await store.replaceStarredMessages([
      for (final entry in _titles.entries)
        GakujoStarredMessage(
          keijitype: '1',
          genrecd: '40',
          seqNo: entry.key,
          title: entry.value,
          body: 'Saved ${entry.value}',
          starredAt: DateTime.utc(2026, 11, int.parse(entry.key)),
        ),
    ]);
    savedRows = storage[_starsKey]!;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_plugin, (call) async {
      if (call.method == 'initialize') return {'textureId': textureId};
      if (call.method == 'dispose' && call.arguments == textureId) {
        viewDisposed = true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(view, _handleWebView);
    messenger.setMockMethodCallHandler(_notifications, (_) async => null);
    messenger.setMockMethodCallHandler(_downloads, (_) async => null);
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          events = sink;
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GakujoWebApp(
          localPrefsStore: _Prefs(),
          gakujoReachable: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await waitFor('initial portal load', () => loads.isNotEmpty);
    await finishPage(_home, canGoBack: false);
    loads.clear();
  }

  Future<Object?> _handleWebView(MethodCall call) async {
    switch (call.method) {
      case 'loadUrl':
        loads.add(call.arguments as String);
        return null;
      case 'goBack':
        webViewBacks++;
        return null;
      case 'addScriptToExecuteOnDocumentCreated':
        return 'script';
      case 'executeScript':
        break;
      default:
        return null;
    }
    final script = call.arguments as String;
    for (final id in _titles.keys) {
      if (script !=
          GakujoMessageStarScript.buildOpen(
            keijitype: '1',
            genrecd: '40',
            seqNo: id,
          )) {
        continue;
      }
      lookups.add(id);
      final status = lookups.length == 1 ? await firstReply.future : 'ok';
      return jsonEncode(
        jsonEncode({'status': status, if (status == 'ok') 'url': _detail(id)}),
      );
    }
    for (final kind in ['starred', 'favorites']) {
      if (script ==
          gakujoHistoryMarkerJs({'action': 'stamp-dialog', 'kind': kind})) {
        stamps.add((document, kind));
        dialogByPage[document] = kind;
        return jsonEncode('ok');
      }
    }
    if (script == gakujoHistoryMarkerJs({'action': 'read'})) {
      historyReads++;
      return jsonEncode(
        jsonEncode({
          'dialog': dialogByPage[document],
          'preview': null,
          'active': 'none',
          'activeToken': null,
        }),
      );
    }
    if (script == gakujoPortalAuthStateProbeScript) {
      return jsonEncode({'hasAuthenticatedMarker': true});
    }
    return jsonEncode('');
  }

  Future<void> waitFor(String description, bool Function() condition) async {
    for (var i = 0; i < 150; i++) {
      if (condition()) return;
      // Page-finished asset reads run outside the widget tester's fake clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for $description');
  }

  Future<void> finishPage(String url, {bool canGoBack = true}) async {
    Future<void> emit(String type, Object value) async {
      events.success({'type': type, 'value': value});
      await tester.idle();
    }

    document = url;
    await emit('navigationStarting', url);
    await emit('urlChanged', url);
    await emit('historyChanged', {
      'canGoBack': canGoBack,
      'canGoForward': false,
    });
    await emit('loadingStateChanged', windows.LoadingState.loading.index);
    final previousReads = historyReads;
    await emit(
      'loadingStateChanged',
      windows.LoadingState.navigationCompleted.index,
    );
    await waitFor(
      'page-finished history read',
      () => historyReads > previousReads,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder target) async {
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> showStars() async {
    await tap(find.byTooltip('スター付き連絡通知'));
    expect(find.text('2 / 2 件'), findsOneWidget);
  }

  Future<void> select(String title, {bool fromMenu = false}) async {
    await showStars();
    final row = find.text(title);
    if (fromMenu) {
      final tile = find.ancestor(of: row, matching: find.byType(ListTile));
      await tap(find.descendant(of: tile, matching: find.byTooltip('連絡通知の操作')));
      await tap(find.text('学務で開く'));
    } else {
      await tap(row);
    }
    expect(find.byType(AlertDialog), findsNothing);
  }

  Future<void> completeWithDetail(
    String id,
    List<String> expectedLookups,
  ) async {
    expect(lookups, ['1']);
    expect(loads, isEmpty);
    firstReply.complete('ok');
    await waitFor('detail load', () => loads.isNotEmpty);
    expect(lookups, expectedLookups);
    expect(loads, [_detail(id)]);
    await finishPage(_detail(id));
  }

  Future<void> expectReturnToStars(String id) async {
    await tap(find.byTooltip('前のページ'));
    expect(find.text('2 / 2 件'), findsOneWidget);
    expect(find.byTooltip('ページに戻る'), findsOneWidget);
    expect(webViewBacks, 0);
    expect(stamps, [(_detail(id), 'starred')]);
  }

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox());
    if (!firstReply.isCompleted) firstReply.complete('ok');
    await tester.pump(const Duration(minutes: 4));
    await waitFor('WebView disposal', () => viewDisposed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Back follows the latest saved-list selection',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      addTearDown(() async {
        for (final channel in [_plugin, _notifications, _downloads]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        FlutterSecureStorage.setMockInitialValues({});
        await tester.binding.setSurfaceSize(null);
      });
      await tester.binding.setSurfaceSize(const Size(1400, 1800));

      // Mount each scenario with fresh history and storage. The app's shared
      // storage queues must run on the same widget-test clock across mounts.
      var nextTextureId = 73;
      Future<void> duringLookup(
        Future<void> Function(_Journey) exercise,
      ) async {
        final app = _Journey(tester, nextTextureId++);
        try {
          await app.mount();
          await app.select('Alpha');
          await app.waitFor('first lookup', () => app.lookups.isNotEmpty);
          await exercise(app);
          expect(app.storage[_starsKey], app.savedRows);
        } finally {
          await app.unmount();
          messenger.setMockMethodCallHandler(app.view, null);
          messenger.setMockStreamHandler(app.eventChannel, null);
        }
      }

      // The toolbar remains available both for another message and for reselection.
      for (final id in ['2', '1']) {
        await duringLookup((app) async {
          await app.select(_titles[id]!, fromMenu: true);
          await app.completeWithDetail(id, ['1', id]);
          await app.expectReturnToStars(id);
        });
      }

      // Beta is superseded while still waiting for the first Alpha lookup.
      await duringLookup((app) async {
        await app.select('Beta', fromMenu: true);
        await app.select('Alpha');
        await app.completeWithDetail('1', ['1', '1']);
        await app.expectReturnToStars('1');
      });

      await duringLookup((app) async {
        await app.showStars();
        await app.tap(find.text('閉じる'));
        await app.completeWithDetail('1', ['1']);
        await app.expectReturnToStars('1');
      });

      await duringLookup((app) async {
        app.firstReply.complete('missing');
        await tester.pumpAndSettle();
        expect(find.text('学務へのログインが必要です'), findsOneWidget);
        expect(app.loads, isEmpty);
        // An ordinary in-page link after a failure should have no dialog marker.
        await app.finishPage(_favorite);
        await app.tap(find.byTooltip('前のページ'));
        expect(app.stamps, isEmpty);
        expect(app.webViewBacks, 1);
      });

      await duringLookup((app) async {
        await app.select('Beta', fromMenu: true);
        await tester.pump(const Duration(minutes: 3));
        await app.completeWithDetail('2', ['1', '2']);
        await app.tap(find.byTooltip('前のページ'));
        expect(app.stamps, isEmpty);
        expect(app.webViewBacks, 1);
      });

      await duringLookup((app) async {
        await GakujoActivityStore().replaceFavorites([
          GakujoFavoritePage(
            title: 'Saved timetable',
            url: _favorite,
            addedAt: DateTime.utc(2026, 11),
          ),
        ]);
        await app.tap(find.byTooltip('設定'));
        await app.tap(find.text('保存データ'));
        await app.tap(find.widgetWithText(OutlinedButton, 'お気に入り'));
        await app.tap(find.text('Saved timetable'));
        await app.tap(find.text('閉じる'));
        expect(app.loads, [_favorite]);
        app.firstReply.complete('ok');
        await app.finishPage(_favorite);
        await app.tap(find.byTooltip('前のページ'));
        expect(find.text('Saved timetable'), findsOneWidget);
        expect(find.byTooltip('ページに戻る'), findsOneWidget);
        expect(app.stamps, [(_favorite, 'favorites')]);
        expect(app.loads, [_favorite]);
        expect(app.lookups, ['1']);
        expect(app.webViewBacks, 0);
      });

      await duringLookup((app) async {
        await app.select('Beta', fromMenu: true);
        await app.unmount();
        expect(app.lookups, ['1']);
        expect(app.loads, isEmpty);
        expect(app.stamps, isEmpty);
        expect(tester.takeException(), isNull);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
