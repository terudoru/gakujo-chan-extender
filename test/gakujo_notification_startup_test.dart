import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_message_star_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/history_marker.g.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

class _Prefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;
  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const landing =
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';
  const report = '$landing?page=main&tabId=en';
  const schedule = '$landing?page=main&tabId=sch';
  const message =
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
      'campussquare.do?_flowId=KJW0001100-flow&keijitype=1&genrecd=2&seqNo=3';
  final openMessage = GakujoMessageStarScript.buildOpen(
    keijitype: '1',
    genrecd: '2',
    seqNo: '3',
  );
  final readHistory = gakujoHistoryMarkerJs({'action': 'read'});
  const plugin = MethodChannel('io.jns.webview.win');
  const view = MethodChannel('io.jns.webview.win/73');
  const events = EventChannel('io.jns.webview.win/73/events');
  const channel = MethodChannel('net.yoshida.morebettergakujo/notifications');
  const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Script the two wire orders exercised by the native transition tests.
  // The startup receipt and a tagged live call represent separate activations.
  final loads = <String>[];
  final takes = <String>[];
  final finishes = <(String, bool)>[];
  String? pending;
  Completer<void>? prepare;
  Completer<void>? receipt;
  Completer<void>? initialLoad;
  var rejectLoad = false;
  Completer<bool>? nextLoad;
  var historyReads = 0;
  var messageOpens = 0;
  var loginVisible = false;
  late MockStreamHandlerEventSink webView;
  void settings({bool savedLogin = false, String? lastPage}) =>
      FlutterSecureStorage.setMockInitialValues({
        'more_better_gakujo_setup_completed': 'true',
        'more_better_gakujo_disabled_feature_flags': 'update_notice',
        'more_better_gakujo_last_url': ?lastPage,
        if (savedLogin) 'more_better_gakujo_login_id': 'fixture',
        if (savedLogin) 'more_better_gakujo_login_password': 'fixture',
      });

  void resetFixture() {
    loads.clear();
    takes.clear();
    finishes.clear();
    pending = null;
    rejectLoad = false;
    prepare = receipt = initialLoad = null;
    nextLoad = null;
    historyReads = messageOpens = 0;
    loginVisible = false;
    final claims = <String, String?>{};
    settings();
    messenger.setMockMethodCallHandler(plugin, (call) async {
      if (call.method != 'initialize') return null;
      await prepare?.future;
      return {'textureId': 73};
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.arguments is! Map) throw MissingPluginException();
      final args = call.arguments as Map;
      final token = args['consumer'] as String;
      switch (call.method) {
        case 'takePendingNotificationUrl':
          expect(args['version'], 1);
          takes.add(token);
          final url = pending;
          claims[token] = url;
          pending = null;
          await receipt?.future;
          return {'version': 1, 'consumer': token, 'url': url};
        case 'finishPendingNotification':
          final accepted = args['accepted'] as bool;
          finishes.add((token, accepted));
          final claimed = claims.remove(token);
          if (!accepted) pending ??= claimed;
          return null;
        case 'endNotificationConsumer':
          return null;
      }
      throw MissingPluginException();
    });
    messenger.setMockMethodCallHandler(
      downloads,
      (_) async => {'isConfigured': false},
    );
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          webView = sink;
        },
      ),
    );
    messenger.setMockMethodCallHandler(view, (call) async {
      switch (call.method) {
        case 'loadUrl':
          if (rejectLoad) throw PlatformException(code: 'load_rejected');
          final delayed = nextLoad;
          nextLoad = null;
          if (delayed != null && !await delayed.future) {
            throw PlatformException(code: 'load_rejected');
          }
          loads.add(call.arguments as String);
          await initialLoad?.future;
          return null;
        case 'addScriptToExecuteOnDocumentCreated':
          return 'id';
        case 'executeScript':
          if (call.arguments == readHistory) historyReads++;
          if (call.arguments == openMessage) {
            messageOpens++;
            return jsonEncode(jsonEncode({'status': 'missing'}));
          }
          if (call.arguments == gakujoPortalAuthStateProbeScript) {
            return loginVisible
                ? '{"hasLoginFields":true}'
                : '{"hasAuthenticatedMarker":true}';
          }
          return '{}';
      }
      return null;
    });
  }

  tearDown(() {
    for (final c in [plugin, view, channel, downloads]) {
      messenger.setMockMethodCallHandler(c, null);
    }
    messenger.setMockStreamHandler(events, null);
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> mount(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(home: GakujoWebApp(localPrefsStore: _Prefs())),
    );
    await t.pumpAndSettle();
  }

  Future<bool> live(String token, String url) async {
    const codec = StandardMethodCodec();
    final reply = await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        MethodCall('deadlineNotificationTapped', {
          'consumer': token,
          'url': url,
        }),
      ),
      null,
    );
    return reply != null && codec.decodeEnvelope(reply) == true;
  }

  Future<void> finishPage(WidgetTester t, String url) async {
    final previousReads = historyReads;
    final previousLoads = loads.length;
    void event(String type, Object value) =>
        webView.success({'type': type, 'value': value});
    event('navigationStarting', url);
    await t.idle();
    event('urlChanged', url);
    await t.idle();
    event('loadingStateChanged', windows.LoadingState.loading.index);
    await t.idle();
    event(
      'loadingStateChanged',
      windows.LoadingState.navigationCompleted.index,
    );
    await t.pump();
    // The history read follows login restoration and message processing. A
    // restore that starts another navigation can finish the callback earlier.
    bool finished() =>
        historyReads > previousReads || loads.length > previousLoads;
    for (var i = 0; i < 100 && !finished(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await t.pump(const Duration(milliseconds: 10));
    }
    expect(finished(), isTrue, reason: 'page-finished callback for $url');
  }

  // Remount on one test clock: the application's process-wide storage queues
  // and the messenger survive widget disposal in a real UI isolate.
  testWidgets(
    'notification delivery across startup and remount',
    (t) async {
      Future<void> trial(String name, Future<void> Function() body) async {
        resetFixture();
        try {
          await body();
          debugPrint(
            '$name: loads=$loads, receipts=${finishes.map((f) => f.$2).toList()}',
          );
        } finally {
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 10));
        }
      }

      for (final beforeMount in [true, false]) {
        await trial(
          'one activation before take (before mount: $beforeMount)',
          () async {
            prepare = Completer<void>();
            if (beforeMount) pending = report;
            await mount(t);
            expect(takes, isEmpty);
            if (!beforeMount) pending = report;
            prepare!.complete();
            await t.pumpAndSettle();
            expect(loads, [report]);
            expect(finishes, [(takes.single, true)]);
            expect(await live(takes.single, report), isTrue);
            expect(await live(takes.single, schedule), isTrue);
            expect(loads, [report, report, schedule]);
          },
        );
      }

      await trial(
        'take wins before live tap and returns while live waits',
        () async {
          receipt = Completer<void>();
          await mount(t);
          final tap = live(takes.single, report);
          await t.idle();
          expect(loads, isEmpty);
          receipt!.complete();
          await t.pumpAndSettle();
          expect(await tap, isTrue);
          expect(loads, [isNot(report), report]);
          expect(finishes, isEmpty);
          expect(await live(takes.single, 'https://outside.invalid/'), isTrue);
          expect(loads, hasLength(2));
        },
      );

      await trial('dispose releases waiting live tap and blocks late old startup navigation', () async {
        receipt = Completer<void>();
        pending = report;
        await mount(t);
        final old = takes.single;
        final waiting = live(old, schedule);
        await t.idle();
        await t.pumpWidget(const SizedBox());
        expect(await waiting, isFalse);
        expect(finishes, [(old, false)]);
        final oldReceipt = receipt!;
        receipt = null;
        pending = schedule;
        await mount(t);
        expect(takes.last, isNot(old));
        oldReceipt.complete();
        await t.pumpAndSettle();
        expect(loads, [schedule]);
        expect(await live(takes.last, report), isTrue);
        expect(loads, [schedule, report]);
        expect(finishes, [(old, false), (takes.last, true)]);
      });

      await trial(
        'admitted startup retains ownership until its load replies',
        () async {
          initialLoad = Completer<void>();
          pending = report;
          await mount(t);
          final old = takes.single;
          expect(loads, [report]);
          await t.pumpWidget(const SizedBox());
          expect(finishes, isEmpty);
          final inFlight = initialLoad!;
          initialLoad = null;
          await mount(t);
          expect(loads, [report, isNot(report)]);
          inFlight.complete();
          await t.pumpAndSettle();
          expect(finishes, [(old, true)]);
        },
      );

      await trial(
        'rejected startup load releases its receipt and waiting live work',
        () async {
          pending = report;
          rejectLoad = true;
          await mount(t);
          expect(finishes, [(takes.single, false)]);
          expect(await live(takes.single, schedule), isFalse);
          expect(loads, isEmpty);
        },
      );

      await trial(
        'saved login reserves startup notification until authenticated landing',
        () async {
          settings(savedLogin: true);
          pending = report;
          await mount(t);
          expect(loads, [isNot(report)]);
          expect(finishes, [(takes.single, true)]);
          void event(String type, Object value) =>
              webView.success({'type': type, 'value': value});
          event('navigationStarting', landing);
          await t.idle();
          event('urlChanged', landing);
          await t.idle();
          event('loadingStateChanged', windows.LoadingState.loading.index);
          await t.pump();
          event(
            'loadingStateChanged',
            windows.LoadingState.navigationCompleted.index,
          );
          for (var i = 0; i < 100 && loads.length == 1; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await t.pump(const Duration(milliseconds: 10));
          }
          expect(loads, [isNot(report), report]);
        },
      );

      final rejectedLoads = <String, (int, int)>{};
      for (final duringStartup in [true, false]) {
        final kind = duringStartup ? 'startup' : 'live';
        await trial(
          'known $kind rejection releases local navigation',
          () async {
            if (duringStartup) {
              pending = report;
              rejectLoad = true;
            }
            await mount(t);
            if (duringStartup) {
              expect(finishes, [(takes.single, false)]);
            } else {
              expect(loads, [landing]);
              rejectLoad = true;
              await expectLater(
                live(takes.single, report),
                throwsA(isA<PlatformException>()),
              );
              // The producer retains this rejected live delivery.
              pending = report;
            }
            rejectLoad = false;
            final home = find.byTooltip('学務のHOMEへ');
            await t.tap(home);
            await t.pump();
            final homeUrl = loads.last;
            expect(homeUrl, isNot(report));
            await finishPage(t, homeUrl);
            final old = loads.where((url) => url == report).length;
            final beforeRemount = loads.length;
            await t.pumpWidget(const SizedBox());
            await mount(t);
            expect(finishes.last, (takes.last, true));
            rejectedLoads[kind] = (
              old,
              loads.skip(beforeRemount).where((url) => url == report).length,
            );
          },
        );
      }
      for (final newer in [report, schedule]) {
        await trial('late rejection preserves accepted $newer', () async {
          await mount(t);
          final firstLoad = nextLoad = Completer<bool>();
          final rejected = expectLater(
            live(takes.single, report),
            throwsA(isA<PlatformException>()),
          );
          await t.idle();
          expect(await live(takes.single, newer), isTrue);
          firstLoad.complete(false);
          await rejected;
          final beforeLanding = loads.length;
          await finishPage(t, landing);
          expect(loads.skip(beforeLanding), [newer]);
        });
      }
      expect(rejectedLoads, {'startup': (0, 1), 'live': (0, 1)});
      for (final acceptedReplacement in [false, true]) {
        await trial(
          'message open after rejection, newer accepted: $acceptedReplacement',
          () async {
            await mount(t);
            final firstLoad = nextLoad = Completer<bool>();
            final rejected = expectLater(
              live(takes.single, message),
              throwsA(isA<PlatformException>()),
            );
            await t.idle();
            if (acceptedReplacement) {
              expect(await live(takes.single, message), isTrue);
            }
            firstLoad.complete(false);
            await rejected;
            await finishPage(t, message);
            expect(messageOpens, acceptedReplacement ? 1 : 0);
          },
        );
      }
      await trial(
        'a login challenge cannot rearm the rejected recovery target',
        () async {
          await mount(t);
          rejectLoad = true;
          await expectLater(
            live(takes.single, report),
            throwsA(isA<PlatformException>()),
          );
          rejectLoad = false;
          loginVisible = true;
          await finishPage(
            t,
            Uri.parse(landing).resolve('login.do').toString(),
          );
          loginVisible = false;
          await finishPage(t, landing);
          expect(loads, [landing]);
        },
      );
      await trial(
        'ordinary startup keeps its saved-page restore on command failure',
        () async {
          settings(lastPage: report);
          rejectLoad = true;
          await mount(t);
          expect(finishes, isEmpty);
          rejectLoad = false;
          await t.tap(find.byTooltip('学務のHOMEへ'));
          await t.pump();
          await finishPage(t, loads.single);
          expect(loads, [isNot(report), report]);
        },
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
