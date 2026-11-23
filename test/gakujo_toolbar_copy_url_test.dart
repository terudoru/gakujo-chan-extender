import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/course_planner_fetch.g.dart';
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
const _academicPacket = {
  'v': 1,
  'kind': 'grades',
  'tables': [
    {
      'heading': '単位修得状況照会',
      'rows': [
        ['科目名', '単位数', '評価'],
        ['合成科目', '1', '認定'],
      ],
    },
  ],
};
const _multiFetchPayload = {
  'v': 1,
  'packets': {
    // Deliberately out of order to verify canonical profile/grades/balances/registration order.
    'registration': {
      'v': 1,
      'kind': 'registration',
      'tables': [
        {
          'heading': '履修登録・登録状況照会',
          'rows': [
            ['開講番号', '登録状況'],
            ['269G9001', '申請中'],
            ['269G9002', '許可'],
          ],
        },
      ],
      'year': '2026',
    },
    'balances': {
      'v': 1,
      'kind': 'balances',
      'tables': [
        {
          'heading': '履修科目確認表',
          'rows': [
            ['科目区分', '既修得単位数'],
            ['教養教育に関する科目', '10.5'],
          ],
        },
      ],
    },
    'grades': {
      'v': 1,
      'kind': 'grades',
      'tables': [
        {
          'heading': '単位修得状況照会',
          'rows': [
            ['開講番号', '科目名', '単位数', '評価', '年度'],
            ['269G9001', '合成力学', '2', '優', '2026'],
          ],
        },
      ],
    },
    'profile': {
      'v': 1,
      'kind': 'profile',
      'tables': [
        {
          'heading': '学生所属',
          'rows': [
            ['所属', '学年'],
            ['理学部物理学科', '2'],
          ],
        },
      ],
    },
  },
};

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
      for (final result in ['success', 'false', 'throw']) {
        final page = _Toolbar(tester, ++viewId);
        try {
          await page.mount();
          final launches = <MethodCall>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            _Toolbar._launcher,
            (call) async {
              launches.add(call);
              if (result == 'throw') {
                throw PlatformException(code: 'shell_failed');
              }
              return result == 'success';
            },
          );
          await page.tap(find.byTooltip('メニュー'));
          expect(find.byIcon(Icons.more_vert), findsOneWidget);
          expect(find.text('履修プランナー'), findsNothing);
          await page.tap(find.text('履修手帖を開く'));
          expect(launches, hasLength(1));
          expect(launches.single.method, 'launch');
          expect(
            launches.single.arguments,
            containsPair('url', 'https://gakujo.terudoru.com/syllabus/'),
          );
          // url_launcher maps externalApplication to both embedded modes false.
          expect(launches.single.arguments, containsPair('useSafariVC', false));
          expect(launches.single.arguments, containsPair('useWebView', false));
          expect(page.home.isCurrent, isTrue);
          expect(
            page.notices,
            result == 'success' ? isEmpty : ['外部ブラウザで開けませんでした'],
          );
          expect(tester.takeException(), isNull);
        } finally {
          await page.close();
        }
      }
      final importer = _Toolbar(tester, ++viewId, academicFixture: true);
      const copyLabel = '学務の照会結果を履修手帖用にコピー';
      try {
        await importer.mount();
        final launches = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _Toolbar._launcher,
          (call) async {
            launches.add(call);
            return true;
          },
        );
        await importer.tap(find.byTooltip('メニュー'));
        expect(find.text('学務の照会結果をプランナーに取り込む'), findsNothing);
        expect(find.text(copyLabel), findsOneWidget);
        await importer.tap(find.text(copyLabel));
        await importer.tap(find.text('成績をコピー'));
        expect(find.textContaining('個人情報を含みます'), findsOneWidget);
        expect(await importer.readClipboard(), _previous);
        await importer.tap(find.text('キャンセル'));
        expect(await importer.readClipboard(), _previous);
        await importer.tap(find.byTooltip('メニュー'));
        await importer.tap(find.text(copyLabel));
        await importer.tap(find.text('成績をコピー'));
        await importer.tap(find.text('コピー'));
        final token = (await importer.readClipboard())!;
        expect(token, startsWith('MBGPLAN1.'));
        expect(
          jsonDecode(
            utf8.decode(
              base64Url.decode(base64Url.normalize(token.substring(9))),
            ),
          ),
          _academicPacket,
        );
        expect(
          find.textContaining('More Better Gakujo から貼り付け'),
          findsOneWidget,
        );
        expect(importer.home.isCurrent, isTrue);
        await importer.tap(find.text('履修手帖を開く'));
        expect(
          launches.last.arguments,
          containsPair('url', 'https://gakujo.terudoru.com/syllabus/'),
        );
        expect(launches.last.arguments, containsPair('useWebView', false));
        importer._clipboard = _previous;
        expect(launches, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await importer.close();
      }

      // Multi-kind background fetch: one confirmation dialog, ordered multi-token copy,
      // and identity-change abort while the confirmation dialog is open.
      final autoFetch = _Toolbar(
        tester,
        ++viewId,
        academicFixture: true,
        fetchHandler: () async => jsonEncode(jsonEncode(_multiFetchPayload)),
      );
      try {
        await autoFetch.mount();
        final launches = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _Toolbar._launcher,
          (call) async {
            launches.add(call);
            return true;
          },
        );
        await autoFetch.tap(find.byTooltip('メニュー'));
        await autoFetch.tap(find.text(copyLabel));
        expect(find.text('履修手帖に渡す内容'), findsNothing);
        expect(
          find.text(
            '所属・学年（候補）、成績、区分別の既修得単位数、履修登録状況を履修手帖用にコピー',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('個人情報を含みます'), findsOneWidget);
        expect(await autoFetch.readClipboard(), _previous);
        await autoFetch.tap(find.text('キャンセル'));
        expect(await autoFetch.readClipboard(), _previous);

        await autoFetch.tap(find.byTooltip('メニュー'));
        await autoFetch.tap(find.text(copyLabel));
        await autoFetch.tap(find.text('コピー'));
        final copied = (await autoFetch.readClipboard())!;
        expect(
          copied,
          File('test/support/planner_handoff_multi.txt').readAsStringSync().trim(),
        );
        expect(copied.split('\n'), hasLength(4));
        expect(find.textContaining('4件をコピーしました'), findsOneWidget);
        await autoFetch.tap(find.text('履修手帖を開く'));
        expect(launches, hasLength(1));
        expect(
          launches.single.arguments,
          containsPair('url', 'https://gakujo.terudoru.com/syllabus/'),
        );

        // Identity/navigation change while confirmation dialog is open aborts copy.
        autoFetch._clipboard = _previous;
        await autoFetch.tap(find.byTooltip('メニュー'));
        await autoFetch.tap(find.text(copyLabel));
        expect(find.text('コピー'), findsOneWidget);
        await autoFetch.emit('navigationStarting', _portal);
        await autoFetch.tap(find.text('コピー'));
        expect(await autoFetch.readClipboard(), _previous);
        expect(
          find.textContaining('学務の表示またはログイン状態が変わりました'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await autoFetch.close();
      }

      // Background fetch throws -> falls back to displayed-page chooser unchanged.
      final fallbackOnError = _Toolbar(
        tester,
        ++viewId,
        academicFixture: true,
        fetchHandler: () async =>
            throw PlatformException(code: 'js_error', message: 'boom'),
      );
      try {
        await fallbackOnError.mount();
        await fallbackOnError.tap(find.byTooltip('メニュー'));
        await fallbackOnError.tap(find.text(copyLabel));
        expect(find.text('履修手帖に渡す内容'), findsOneWidget);
        await fallbackOnError.tap(find.text('成績をコピー'));
        await fallbackOnError.tap(find.text('コピー'));
        expect(await fallbackOnError.readClipboard(), startsWith('MBGPLAN1.'));
        expect(tester.takeException(), isNull);
      } finally {
        await fallbackOnError.close();
      }

      // Identity/navigation change while background fetch is in flight aborts cleanly.
      final inflight = Completer<Object?>();
      final abortDuringFetch = _Toolbar(
        tester,
        ++viewId,
        academicFixture: true,
        fetchHandler: () => inflight.future,
      );
      try {
        await abortDuringFetch.mount();
        await abortDuringFetch.tap(find.byTooltip('メニュー'));
        await tester.tap(find.text(copyLabel).hitTestable());
        await tester.pump();
        await abortDuringFetch.emit('navigationStarting', _portal);
        inflight.complete(jsonEncode(jsonEncode(_multiFetchPayload)));
        await tester.pumpAndSettle();
        expect(find.text('コピー'), findsNothing);
        expect(await abortDuringFetch.readClipboard(), _previous);
        expect(
          find.textContaining('学務の表示またはログイン状態が変わりました'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await abortDuringFetch.close();
      }

      // Not logged in -> updated prompt without telling the student to open inquiry page first.
      final loggedOut = _Toolbar(tester, ++viewId);
      try {
        await loggedOut.mount();
        await loggedOut.tap(find.byTooltip('メニュー'));
        await loggedOut.tap(find.text(copyLabel));
        expect(
          loggedOut.notices,
          ['学務にログインしてから、もう一度お試しください。'],
        );
        expect(tester.takeException(), isNull);
      } finally {
        await loggedOut.close();
      }

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
  _Toolbar(
    this.tester,
    this.id, {
    this.academicFixture = false,
    this.fetchHandler,
  });
  final bool academicFixture;
  final Future<Object?> Function()? fetchHandler;
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
      if (academicFixture)
        'more_better_gakujo_active_login_account': 'synthetic-account',
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
      if (fetchHandler != null && call.arguments == coursePlannerFetchJs) {
        return await fetchHandler!();
      }
      if (academicFixture &&
          (call.arguments as String).contains(
            'web_scripts/src/course_planner/capture.ts',
          )) {
        return jsonEncode(
          jsonEncode(
            (call.arguments as String).contains('"kind":"grades"')
                ? _academicPacket
                : ['grades'],
          ),
        );
      }
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

  Future<void> emit(String type, Object value) async {
    _sink.success({'type': type, 'value': value});
    await tester.idle();
  }

  Future<void> visit(String url) async {
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
