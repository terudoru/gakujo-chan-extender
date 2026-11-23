import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/planner_bridge/planner_page.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

class _Auth extends Fake implements StarSyncGoogleAuth {
  @override
  int get generation => 0;
  @override
  String? get currentEmail => null;
}

class _Controller extends Fake implements GakujoWebViewController {
  late GakujoNavigationDelegate delegate;
  String? url;
  final scripts = <String>[];
  @override
  Future<void> setJavaScriptModeUnrestricted() async {}
  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required FutureOr<void> Function(String) onMessageReceived,
  }) async {}
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
      final external = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HostedPlannerPage(
            service: service,
            auth: _Auth(),
            student: () => null,
            signIn: () async {},
            signOut: () async {},
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
      expect(controller.scripts.single, contains('MbgPlannerBridge'));
      controller.delegate.onDocumentStarted!();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
