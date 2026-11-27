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
import 'package:morebettergakujo_flutter/src/planner_bridge/planner_broker.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_factory.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

class _TestPrefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

void main() {
  testWidgets('history restores only after the same account reauthenticates', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const plugin = MethodChannel('io.jns.webview.win');
    const view = MethodChannel('io.jns.webview.win/73');
    const events = EventChannel('io.jns.webview.win/73/events');
    const notifications = MethodChannel(
      'net.yoshida.morebettergakujo/notifications',
    );
    const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
    const portal =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';
    const report = '$portal?page=main&tabId=en';
    const accountA = 'notification-history-test-a';
    const accountB = 'notification-history-test-b';
    final hash = starSyncAccountHash(accountA)!;
    final storage = SecureStorageFactory.create();
    Future<Object?> readPlannerIdentity() async => jsonDecode(
      await storage.read(key: 'more_better_gakujo_planner_login_scope') ?? 'null',
    );
    final loads = <String>[];
    final readHistory = gakujoHistoryMarkerJs({'action': 'read'});
    var historyReads = 0;
    var loginVisible = false;
    late MockStreamHandlerEventSink webView;
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      for (final channel in [plugin, view, notifications, downloads]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      messenger.setMockStreamHandler(events, null);
      FlutterSecureStorage.setMockInitialValues({});
    });
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_setup_completed': 'true',
      'more_better_gakujo_disabled_feature_flags': 'update_notice',
      'more_better_gakujo_active_login_account': hash,
      'more_better_gakujo_planner_login_scope': jsonEncode({
        'account': starSyncAccountHash(accountB),
        'student': plannerStudentScope(accountB),
      }),
      'more_better_gakujo_notification_history': jsonEncode([
        {
          'account': hash,
          'title': '確認用通知',
          'body': '確認用本文',
          'postedAtMillis': 1795089600000,
          'url': report,
        },
      ]),
    });
    messenger.setMockMethodCallHandler(
      plugin,
      (call) async => call.method == 'initialize' ? {'textureId': 73} : null,
    );
    messenger.setMockMethodCallHandler(notifications, (_) async => null);
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
          loads.add(call.arguments as String);
        case 'addScriptToExecuteOnDocumentCreated':
          return 'id';
        case 'executeScript':
          if (call.arguments == readHistory) historyReads++;
          if (call.arguments == gakujoPortalAuthStateProbeScript) {
            return loginVisible
                ? '{"hasLoginFields":true}'
                : '{"hasAuthenticatedMarker":true}';
          }
          return '{}';
      }
      return null;
    });

    void event(String type, Object value) =>
        webView.success({'type': type, 'value': value});
    Future<void> openPage(String url, {bool expectRestore = false}) async {
      final readsBefore = historyReads;
      final loadsBefore = loads.length;
      event('navigationStarting', url);
      await tester.idle();
      event('urlChanged', url);
      await tester.idle();
      event('loadingStateChanged', windows.LoadingState.loading.index);
      await tester.pump();
      event(
        'loadingStateChanged',
        windows.LoadingState.navigationCompleted.index,
      );
      await tester.idle();
      await tester.pumpAndSettle();
      if (loginVisible) return;
      for (
        var i = 0;
        i < 100 && historyReads == readsBefore && loads.length == loadsBefore;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      if (expectRestore && loads.length > loadsBefore) return;
      expect(historyReads, greaterThan(readsBefore));
    }

    Future<void> chooseHistoryTarget() async {
      await tester.tap(find.byTooltip('メニュー'));
      await tester.pumpAndSettle();
      for (final text in ['通知履歴', '確認用通知', '元のページを開く']) {
        final target = find.text(text);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      expect(loads, [report]);
    }

    Future<void> submit(String loginId) async {
      event(
        'webMessageReceived',
        jsonEncode({
          'channel': GakujoMessageStarScript.channelName,
          'message': jsonEncode({
            'type': 'gakujoLoginSubmitted',
            'loginId': loginId,
          }),
        }),
      );
      await tester.pumpAndSettle();
      loginVisible = false;
    }

    Future<void> mount() async {
      await tester.pumpWidget(
        MaterialApp(
          home: GakujoWebApp(
            localPrefsStore: _TestPrefs(),
            gakujoReachable: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount();
    try {
      await openPage(portal);
      // A scope left by another account cannot attach to the legacy session.
      expect(await readPlannerIdentity(), isNull);
      for (final (authPage, loginId, shouldRestore) in [
        ('login.do', accountA, true),
        ('campussquare.do?_eventId=logout', accountA, false),
        ('login.do', accountB, false),
      ]) {
        loads.clear();
        await chooseHistoryTarget();
        loginVisible = true;
        await openPage(Uri.parse(portal).resolve(authPage).toString());
        if (shouldRestore) {
          // Seeing an authenticated page without identifying its account does
          // not authorize a history link to reopen.
          loginVisible = false;
          await openPage(portal);
          expect(loads, [report]);
        }
        await submit(loginId);
        expect(await readPlannerIdentity(), isNull);
        await openPage(portal, expectRestore: shouldRestore);
        expect(loads, shouldRestore ? [report, report] : [report]);
        expect(await readPlannerIdentity(), {
          'account': starSyncAccountHash(loginId),
          'student': plannerStudentScope(loginId),
        });
        if (shouldRestore) {
          await openPage(report);
          await openPage(portal);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mount();
      await openPage(portal);
      expect(await readPlannerIdentity(), {
        'account': starSyncAccountHash(accountB),
        'student': plannerStudentScope(accountB),
      });
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
    }
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}), skip: !Platform.isWindows);
}
