import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/history_marker.g.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as win;

const _portal = 'https://gakujo.iess.niigata-u.ac.jp';
const _a =
    '$_portal/campusweb%3BJSESSIONID%3Dfixture/campussquare.do'
    '?_flowId=example-flow&seqNo=12&token=example#fixture';
const _cleanA =
    '$_portal/campusweb/campussquare.do?_flowId=example-flow&seqNo=12';
const _form = 'https://docs.google.com/forms/d/e/public-fixture/viewform';
const _b =
    '$_form?entry.123=blue%20sky&state=fixture&entry.123=green&embedded=true#fixture';
const _cleanB = '$_form?entry.123=blue%20sky&entry.123=green&embedded=true';
const _previous = 'Fictional previous clipboard text';
const _success = 'URLをコピーしました';
const _failure = 'URLをコピーできませんでした';

class _Prefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;
  @override
  Future<void> saveAppSettings(GakujoAppSettings value) async {}
}

class _Pops extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

void main() {
  testWidgets(
    'toolbar copy reports the clipboard reply and retains the selected URL',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1250, 1450));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var viewId = 80;
      Future<void> onPage(Future<void> Function(_Toolbar) exercise) async {
        final page = _Toolbar(tester, ++viewId);
        try {
          await page.mount();
          await exercise(page);
          expect(page.escaped, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await page.close();
        }
      }

      await onPage((page) async {
        await page.copy(_cleanA, hold: true);
        expect(page.notices, isEmpty);
        expect(await page.readClipboard(), _previous);
        await page.reply(accept: false);
        expect(await page.readClipboard(), _previous);
        expect(page.home.isCurrent, isTrue);
        expect(page.notices, [_failure]);

        await page.copy(_cleanA);
        expect(await page.readClipboard(), _cleanA);
        expect(page.notices, [_success]);

        await page.visit(_b);
        expect(page.notices, [_success]);
        await page.copy(_cleanB, hold: true);
        expect(page.notices, [_success]);
        expect(await page.readClipboard(), _cleanA);
        await page.reply(accept: false);
        expect(await page.readClipboard(), _cleanA);
        expect(page.home.isCurrent, isTrue);
        expect(page.notices, [_failure]);

        await page.copy(_cleanB);
        expect(await page.readClipboard(), _cleanB);
        expect(page.notices, [_success]);
      });

      await onPage((page) async {
        await page.copy(_cleanA, hold: true);
        await page.visit(_b);
        expect(page.notices, isEmpty);
        expect(await page.readClipboard(), _previous);
        await page.reply(accept: true);
        expect(await page.readClipboard(), _cleanA);
        expect(page.notices, [_success]);
        expect(page.home.isCurrent, isTrue);
        expect(find.textContaining(_b).hitTestable(), findsOneWidget);
        await page.copy(_cleanB);
        expect(await page.readClipboard(), _cleanB);
      });

      for (final accept in [true, false]) {
        await onPage((page) async {
          await page.copy(_cleanA, hold: true);
          await page.tap(find.byTooltip('設定'));
          final close = find.text('閉じる').hitTestable();
          final settings = ModalRoute.of(tester.element(close))!;
          expect(settings.isCurrent, isTrue);
          expect(page.home.isCurrent, isFalse);
          expect(page.notices, isEmpty);
          await page.reply(accept: accept);
          expect(settings.isCurrent, isTrue);
          final feedback = accept ? _success : _failure;
          expect(page.notices, [feedback]);
          expect(
            ModalRoute.of(tester.element(find.text(feedback).hitTestable())),
            same(settings),
          );
          expect(await page.readClipboard(), accept ? _cleanA : _previous);
          await page.tap(close);
          expect(page.home.isCurrent, isTrue);
          expect(page.notices, [feedback]);
          await page.copy(_cleanA);
          expect(await page.readClipboard(), _cleanA);
          expect(page.notices, [_success]);
        });

        await onPage((page) async {
          await page.copy(_cleanA, hold: true);
          await page.unmount();
          await page.reply(accept: accept);
          expect(await page.readClipboard(), accept ? _cleanA : _previous);
          expect(find.byType(SnackBar), findsNothing);
        });
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}

class _Toolbar {
  _Toolbar(this.tester, this.id);
  final WidgetTester tester;
  final int id;
  final _pops = _Pops();
  final _writes = <String>[];
  final _accepted = <bool>[];
  final escaped = <PlatformException>[];
  final _disposed = Completer<void>();
  Completer<bool>? _pending;
  String _clipboard = _previous;
  late MockStreamHandlerEventSink _sink;
  late ModalRoute<dynamic> home;

  static const _storage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  static const _plugin = MethodChannel('io.jns.webview.win');
  static const _notifications = MethodChannel(
    'net.yoshida.morebettergakujo/notifications',
  );
  static const _downloads = MethodChannel(
    'net.yoshida.morebettergakujo/downloads',
  );
  static const _launcher = MethodChannel('plugins.flutter.io/url_launcher');
  late final _view = MethodChannel('io.jns.webview.win/$id');
  late final _events = EventChannel('io.jns.webview.win/$id/events');
  final _menu = find.byTooltip('メニュー');
  final _pageFinished = Completer<void>();

  Future<void> mount() async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final queue = StorageOperationQueue();
    final data = {
      'more_better_gakujo_setup_completed': 'true',
      'more_better_gakujo_disabled_feature_flags': 'update_notice',
    };
    messenger.setMockMethodCallHandler(
      _storage,
      (call) => queue.run<Object?>(() async {
        final key = call.arguments['key'] as String?;
        switch (call.method) {
          case 'read':
            return data[key];
          case 'write':
            data[key!] = call.arguments['value'] as String;
          case 'delete':
            data.remove(key);
          case 'containsKey':
            return data.containsKey(key);
          case 'readAll':
            return Map.of(data);
          case 'deleteAll':
            data.clear();
          default:
            throw UnsupportedError(call.method);
        }
        return null;
      }),
    );
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          _sink = sink;
        },
      ),
    );
    messenger.setMockMethodCallHandler(_plugin, (call) async {
      if (call.method == 'initialize') return {'textureId': id};
      if (call.method == 'dispose' && call.arguments == id) {
        _disposed.complete();
      }
      return null;
    });
    final loads = <String>[];
    final marker = gakujoHistoryMarkerJs({'action': 'read'});
    messenger.setMockMethodCallHandler(_view, (call) async {
      if (call.method == 'loadUrl') loads.add(call.arguments as String);
      if (call.method == 'addScriptToExecuteOnDocumentCreated') return 'id';
      if (call.method != 'executeScript') return null;
      if (call.arguments == gakujoPortalAuthStateProbeScript) {
        return jsonEncode('{"hasAuthenticatedMarker":true}');
      }
      if (call.arguments == marker && !_pageFinished.isCompleted) {
        _pageFinished.complete();
      }
      return jsonEncode('');
    });
    for (final c in [_notifications, _downloads, _launcher]) {
      messenger.setMockMethodCallHandler(c, (_) async => null);
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': _clipboard};
      if (call.method != 'Clipboard.setData') return null;
      final text = call.arguments['text'] as String;
      _writes.add(text);
      final pending = _pending;
      final accept = pending == null || await pending.future;
      _accepted.add(accept);
      if (!accept) {
        throw PlatformException(
          code: 'Clipboard error',
          message: 'Unable to open clipboard',
          details: 1,
        );
      }
      _clipboard = text;
      return null;
    });
    PackageInfo.setMockInitialValues(
      appName: 'Example',
      packageName: 'example.test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [_pops],
        home: GakujoWebApp(
          localPrefsStore: _Prefs(),
          gakujoReachable: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, hasLength(1));
    await visit(_a);
    home = ModalRoute.of(tester.element(_menu))!;
    expect(home.isCurrent, isTrue);
  }

  Future<void> _waitFor(Completer<void> signal, String reason) async {
    for (var i = 0; i < 150 && !signal.isCompleted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(signal.isCompleted, isTrue, reason: reason);
  }

  Future<void> visit(String url) async {
    Future<void> emit(String type, Object value) async {
      _sink.success({'type': type, 'value': value});
      await tester.idle();
    }

    await emit('navigationStarting', url);
    await emit('urlChanged', url);
    await emit('loadingStateChanged', win.LoadingState.loading.index);
    await emit(
      'loadingStateChanged',
      win.LoadingState.navigationCompleted.index,
    );
    if (url == _a) await _waitFor(_pageFinished, 'portal page finished');
    await tester.pumpAndSettle();
    expect(find.textContaining(url).hitTestable(), findsOneWidget);
  }

  Future<void> tap(Finder target) async {
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target.hitTestable());
    await tester.pumpAndSettle();
  }

  Future<void> copy(String expected, {bool hold = false}) async {
    final before = _writes.length;
    if (hold) _pending = Completer<bool>();
    // Observe only the simulated platform rejection if it escapes the menu's
    // unawaited selection, so the test can still inspect the resulting feedback.
    await runZonedGuarded<Future<void>>(
      () async {
        await tap(_menu);
        final item = find.text('URLをコピー');
        final popup = ModalRoute.of(tester.element(item))!;
        await tap(item);
        expect(
          _pops.routes.where((route) => identical(route, popup)),
          hasLength(1),
        );
      },
      (error, stack) {
        if (error is! PlatformException || error.code != 'Clipboard error') {
          Error.throwWithStackTrace(error, stack);
        }
        escaped.add(error);
      },
    );
    expect(_writes.skip(before), [expected]);
    expect(_accepted.length, before + (hold ? 0 : 1));
  }

  Future<void> reply({required bool accept}) async {
    final pops = _pops.routes.length;
    _pending!.complete(accept);
    _pending = null;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_accepted.length, _writes.length);
    expect(_accepted.last, accept);
    expect(_pops.routes.length, pops);
  }

  Future<String?> readClipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  List<String?> get notices => find
      .descendant(of: find.byType(SnackBar), matching: find.byType(Text))
      .hitTestable()
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .toList();

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _waitFor(_disposed, 'native adapter disposal for view $id');
  }

  Future<void> close() async {
    if (_pending != null) await reply(accept: true);
    if (!_disposed.isCompleted) await unmount();
    await tester.pump(const Duration(minutes: 4));
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockStreamHandler(_events, null);
    for (final c in [
      _storage,
      _plugin,
      _view,
      _notifications,
      _downloads,
      _launcher,
      SystemChannels.platform,
    ]) {
      messenger.setMockMethodCallHandler(c, null);
    }
  }
}
