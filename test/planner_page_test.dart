import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/planner_bridge/planner_page.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

class _Auth extends Fake implements StarSyncGoogleAuth {
  int revision = 0;
  @override
  int get generation => revision;
  @override
  String? get currentEmail => null;
}

class _Controller extends Fake implements GakujoWebViewController {
  late GakujoNavigationDelegate delegate;
  String? url;
  final scripts = <String>[];
  late FutureOr<void> Function(String) receive;
  @override
  Future<void> setJavaScriptModeUnrestricted() async {}
  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required FutureOr<void> Function(String) onMessageReceived,
  }) async {
    receive = onMessageReceived;
  }

  @override
  Future<void> setNavigationDelegate(GakujoNavigationDelegate value) async {
    delegate = value;
  }

  @override
  Future<void> loadUrl(String value) async {
    url = value;
  }

  @override
  Future<String?> currentUrl() async => url;
  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }

  @override
  Future<void> dispose() async {}
}

class _Service extends Fake implements GakujoWebViewService {
  final controller = _Controller();
  @override
  GakujoWebViewController createController() => controller;
  @override
  Widget buildWidget(
    GakujoWebViewController controller, {
    ValueChanged<String>? onError,
  }) => const Text('dedicated webview');
}

void main() {
  testWidgets(
    'hosted screen guards frame, origin and path and keeps one controller',
    (tester) async {
      final service = _Service();
      final auth = _Auth();
      final external = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HostedPlannerPage(
            service: service,
            auth: auth,
            student: () => null,
            signIn: () async {},
            signOut: () async {
              auth.revision++;
            },
            onExternalLink: external.add,
          ),
        ),
      );
      await tester.pump();
      final controller = service.controller;
      expect(controller.url, 'https://gakujo.terudoru.com/syllabus/');
      expect(find.text('履修手帖'), findsOneWidget);
      for (final (url, main, allowed) in [
        ('https://gakujo.terudoru.com/syllabus/', true, true),
        ('https://gakujo.terudoru.com/syllabus/nested', true, true),
        ('https://gakujo.terudoru.com/syllabus/', false, false),
        ('https://gakujo.terudoru.com/planner/', true, false),
        ('https://evil.invalid/syllabus/', true, false),
        ('javascript:alert(1)', true, false),
      ]) {
        expect(
          await controller.delegate.onNavigationRequest!(
            GakujoNavigationRequest(url: url, isMainFrame: main),
          ),
          allowed
              ? GakujoNavigationDecision.navigate
              : GakujoNavigationDecision.prevent,
        );
      }
      expect(external.length, 2);
      await controller.delegate.onPageFinished!(controller.url!);
      expect(controller.scripts, hasLength(2));
      expect(controller.scripts.first, contains('MbgPlannerBridge'));
      expect(controller.scripts.last, contains('"signedIn":false'));
      final capability = RegExp(r'const capability = "([a-f0-9]+)"')
          .firstMatch(controller.scripts.first)!
          .group(1);
      const id = '00000000-0000-4000-8000-000000000001';
      await controller.receive(
        jsonEncode([
          capability,
          jsonEncode({'v': 2, 'id': id, 'op': 'signOut', 'args': {}}),
        ]),
      );
      expect(controller.scripts, hasLength(4));
      expect(controller.scripts[2], contains('"id":"$id"'));
      expect(controller.scripts[3], contains('"event":"session"'));
      controller.delegate.onDocumentStarted!();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
