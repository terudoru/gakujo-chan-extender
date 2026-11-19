import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/document_title.g.dart';
import 'package:morebettergakujo_flutter/src/generated/favorite_page_identity.g.dart';
import 'package:morebettergakujo_flutter/src/generated/history_marker.g.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as win;

const _origin = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
const _atlas = '${_origin}example-atlas';
const _botany = '${_origin}example-botany';
const _sibling = '${_origin}example-archive';
const _atlasTitle = 'Example Atlas';
const _botanyTitle = '植物学 · Botany';
const _favorites = 'more_better_gakujo_favorites';

enum _Case {
  executesAfterCommit,
  cachedPreviousTitle,
  replyAfterCommit,
  cachedBeforeCommit,
  canceled,
  laterSelection,
  retitled,
  blank,
  malformed,
  nullReply,
  wrongTitle,
  wrongUrl,
  scriptError,
  quotedReply,
  writeRetry,
  disposeDuringWrite,
}

class _Prefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;
  @override
  Future<void> saveAppSettings(GakujoAppSettings value) async {}
}

const _pages = [
  (url: _atlas, title: _atlasTitle),
  (url: _botany, title: _botanyTitle),
  (url: _atlas, title: _botanyTitle),
  (url: _atlas, title: '  '),
];

// WebView2 JSON-encodes the result before handing it to the Windows plugin.
List<String> _rendererReplies() {
  final process = Process.runSync('node', [
    '-e',
    r'''
const vm = require('node:vm');
const [script, pages] = process.argv.slice(1);
const replies = JSON.parse(pages).map(({ url, title }) => {
  const location = new URL(url);
  const document = { location, title };
  return JSON.stringify(vm.runInNewContext(script, { document, location }));
});
process.stdout.write(JSON.stringify(replies));
''',
    gakujoFavoritePageIdentityJs,
    jsonEncode([
      for (final page in _pages) {'url': page.url, 'title': page.title},
    ]),
  ], stdoutEncoding: utf8);
  expect(process.exitCode, 0, reason: process.stderr.toString());
  return (jsonDecode(process.stdout as String) as List).cast<String>();
}

void main() {
  late List<String> replies;
  setUpAll(() => replies = _rendererReplies());

  test('renderer captures each URL and title in one JSON string', () {
    for (final (index, page) in _pages.indexed) {
      final snapshot = jsonDecode(replies[index]) as String;
      expect(jsonDecode(snapshot), {'url': page.url, 'title': page.title});
    }
  });

  testWidgets(
    'toolbar favorites keep the selected URL and its own title',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final scenario in _Case.values) {
        await _selectFavorite(tester, scenario, replies);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}

Future<void> _selectFavorite(
  WidgetTester tester,
  _Case scenario,
  List<String> replies,
) async {
  final id = 100 + scenario.index;
  const plugin = MethodChannel('io.jns.webview.win');
  final view = MethodChannel('io.jns.webview.win/$id');
  final events = EventChannel('io.jns.webview.win/$id/events');
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const notifications = MethodChannel(
    'net.yoshida.morebettergakujo/notifications',
  );
  const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
  final messenger = tester.binding.defaultBinaryMessenger;
  final fifo = StorageOperationQueue();
  final data = {
    'more_better_gakujo_setup_completed': 'true',
    'more_better_gakujo_disabled_feature_flags': 'update_notice',
    'more_better_gakujo_last_url': _atlas,
  };
  final releaseWrite = Completer<void>();
  final writing = Completer<void>();
  final disposed = Completer<void>();
  final issued = Completer<void>();
  final releaseScript = Completer<void>();
  final loads = <String>[];
  final markers = <String>[];
  final marker = gakujoHistoryMarkerJs({'action': 'read'});
  var page = 0;
  var action = false;
  var writes = 0;
  var lookups = 0;
  var reject = scenario == _Case.writeRetry;
  final delayed =
      scenario == _Case.executesAfterCommit ||
      scenario == _Case.replyAfterCommit ||
      scenario == _Case.retitled;
  late MockStreamHandlerEventSink sink;
  messenger.setMockMethodCallHandler(
    storage,
    (call) => fifo.run(() async {
      final key = call.arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          return data[key];
        case 'readAll':
          return Map.of(data);
        case 'containsKey':
          return data.containsKey(key);
        case 'write':
          if (key == _favorites && action) {
            writes++;
            if (reject) {
              reject = false;
              throw PlatformException(code: 'write-rejected');
            }
            if (scenario == _Case.disposeDuringWrite) {
              writing.complete();
              await releaseWrite.future;
            }
          }
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
  messenger.setMockStreamHandler(
    events,
    MockStreamHandler.inline(
      onListen: (_, value) {
        sink = value;
      },
    ),
  );
  messenger.setMockMethodCallHandler(plugin, (call) async {
    if (call.method == 'initialize') return {'textureId': id};
    if (call.method == 'dispose' && call.arguments == id) disposed.complete();
    return null;
  });
  for (final channel in [notifications, downloads, SystemChannels.platform]) {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  }
  PackageInfo.setMockInitialValues(
    appName: 'Example',
    packageName: 'example.fixture',
    version: '1.0',
    buildNumber: '1',
    buildSignature: '',
  );
  messenger.setMockMethodCallHandler(view, (call) async {
    if (call.method == 'loadUrl') loads.add(call.arguments as String);
    if (call.method == 'addScriptToExecuteOnDocumentCreated') return 'fixture';
    if (call.method != 'executeScript') return null;
    if (call.arguments == gakujoFavoritePageIdentityJs && action) {
      lookups++;
      final evaluated = scenario == _Case.replyAfterCommit
          ? replies[page]
          : null;
      if (delayed) {
        issued.complete();
        await releaseScript.future;
      }
      return switch (scenario) {
        _Case.malformed => jsonEncode('{'),
        _Case.nullReply => 'null',
        _Case.wrongTitle => jsonEncode(jsonEncode({'url': _atlas, 'title': 7})),
        _Case.wrongUrl => jsonEncode(
          jsonEncode({'url': 7, 'title': _botanyTitle}),
        ),
        _Case.scriptError => throw PlatformException(code: 'script-error'),
        _Case.quotedReply => jsonEncode(replies[page]),
        _ => evaluated ?? replies[page],
      };
    }
    if (call.arguments == gakujoDocumentTitleJs) {
      return jsonEncode(_pages[page].title);
    }
    if (call.arguments == marker) markers.add(_pages[page].url);
    if (call.arguments == gakujoPortalAuthStateProbeScript) {
      return jsonEncode('{"hasAuthenticatedMarker":true}');
    }
    return jsonEncode('');
  });

  Future<void> emit(String name, Object value) async {
    sink.success({'type': name, 'value': value});
    await tester.idle();
  }

  Future<void> commit(int next) async {
    await emit('urlChanged', _pages[next].url);
    page = next;
    await emit('loadingStateChanged', win.LoadingState.loading.index);
  }

  Future<void> waitFor(String label, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 15));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(ready(), isTrue, reason: '$scenario $label');
  }

  Future<void> finish() async {
    final previous = markers.length;
    await emit(
      'loadingStateChanged',
      win.LoadingState.navigationCompleted.index,
    );
    await waitFor(
      'page-finish marker',
      () => markers.skip(previous).contains(_pages[page].url),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder target) async {
    await tester.ensureVisible(target);
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 4));
    await tester.pumpAndSettle();
    await waitFor(
      'native disposal callback for $id',
      () => disposed.isCompleted,
    );
  }

  final sibling = GakujoFavoritePage(
    title: 'Archive',
    url: _sibling,
    addedAt: DateTime.utc(2026),
  );
  final menu = find.byTooltip('メニュー');
  final add = find.text('お気に入りに追加');
  try {
    await GakujoActivityStore().addFavorite(sibling);
    await tester.pumpWidget(
      MaterialApp(
        home: GakujoWebApp(
          localPrefsStore: _Prefs(),
          gakujoReachable: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, [_atlas]);
    await emit('navigationStarting', _atlas);
    await commit(scenario == _Case.blank ? 3 : 0);
    if (scenario == _Case.cachedPreviousTitle ||
        scenario == _Case.cachedBeforeCommit) {
      await emit('titleChanged', _atlasTitle);
    }
    await finish();
    if (scenario == _Case.cachedPreviousTitle ||
        scenario == _Case.laterSelection) {
      await emit('navigationStarting', _botany);
      await commit(1);
      if (scenario == _Case.laterSelection) {
        await emit('titleChanged', _botanyTitle);
        await finish();
      }
    }
    await tap(menu);
    if (scenario == _Case.executesAfterCommit ||
        scenario == _Case.cachedBeforeCommit ||
        scenario == _Case.canceled) {
      await emit('navigationStarting', _botany);
    }
    if (scenario == _Case.canceled) {
      await emit('onLoadError', win.WebErrorStatus.operationCanceled.index);
      await emit(
        'loadingStateChanged',
        win.LoadingState.navigationCompleted.index,
      );
    }
    final before = data[_favorites];
    action = true;
    await tap(add);
    if (delayed) {
      expect(issued.isCompleted, isTrue);
      expect(data[_favorites], before);
      if (scenario == _Case.retitled) {
        page = 2;
      } else {
        if (scenario == _Case.replyAfterCommit) {
          await emit('navigationStarting', _botany);
        }
        await commit(1);
      }
      releaseScript.complete();
      await tester.pumpAndSettle();
    }
    if (scenario == _Case.writeRetry) {
      expect(data[_favorites], before);
      expect(find.text('お気に入りに追加できませんでした').hitTestable(), findsOneWidget);
      await tap(menu);
      await tap(add);
    }
    if (scenario == _Case.disposeDuringWrite) {
      expect(writing.isCompleted, isTrue);
      await unmount();
      releaseWrite.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    } else {
      expect(find.text('お気に入りに追加しました').hitTestable(), findsOneWidget);
    }
    action = false;
    final raw = jsonDecode(data[_favorites]!) as List;
    expect(raw, hasLength(2));
    expect(raw.last, sibling.toJson());
    final favorites = await GakujoActivityStore().loadFavorites();
    expect(favorites.map((row) => row.toJson()), raw);
    final row = favorites.first;
    if (scenario != _Case.disposeDuringWrite) {
      await tap(find.byTooltip('設定'));
      await tap(find.text('保存データ'));
      await tap(find.widgetWithText(OutlinedButton, 'お気に入り'));
      final tile = find.widgetWithText(ListTile, row.title);
      expect(tile.hitTestable(), findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text(row.url)),
        findsOneWidget,
      );
      final previous = loads.length;
      await tap(find.descendant(of: tile, matching: find.text(row.title)));
      expect(loads.skip(previous), [row.url]);
    }
    final expected = switch (scenario) {
      _Case.cachedPreviousTitle ||
      _Case.laterSelection => [_botanyTitle, _botany],
      _Case.retitled => [_botanyTitle, _atlas],
      _Case.executesAfterCommit ||
      _Case.blank ||
      _Case.malformed ||
      _Case.nullReply ||
      _Case.wrongTitle ||
      _Case.wrongUrl ||
      _Case.scriptError => ['example-atlas', _atlas],
      _ => [_atlasTitle, _atlas],
    };
    expect(
      [row.title, row.url],
      expected,
      reason: '$scenario persisted and rendered favorite',
    );
    expect(writes, scenario == _Case.writeRetry ? 2 : 1);
    expect(lookups, writes);
    expect(tester.takeException(), isNull);
  } finally {
    if (!releaseScript.isCompleted) releaseScript.complete();
    if (!releaseWrite.isCompleted) releaseWrite.complete();
    if (!disposed.isCompleted) await unmount();
    for (final channel in [
      plugin,
      view,
      storage,
      notifications,
      downloads,
      SystemChannels.platform,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockStreamHandler(events, null);
  }
}
