// Run with flutter run -d windows -t test/support/planner_bridge_windows_smoke.dart.
// MBG_PLANNER_PROFILE must point to a fresh scratch directory. Never signs in.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:morebettergakujo_flutter/src/planner_bridge/planner_page.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profile = Platform.environment['MBG_PLANNER_PROFILE'];
  if (profile == null || Directory(profile).existsSync()) {
    throw StateError('Set MBG_PLANNER_PROFILE to a fresh scratch directory');
  }
  await windows.WebviewController.initializeEnvironment(userDataPath: profile);
  runApp(
    MaterialApp(
      home: HostedPlannerPage(
        service: const WindowsGakujoWebViewService(),
        auth: createStarSyncGoogleAuth(),
        student: () => null,
        signIn: () async => throw StateError('Sign-in disabled in smoke test'),
        signOut: () async {},
        onExternalLink: (_) {},
      ),
    ),
  );
}
