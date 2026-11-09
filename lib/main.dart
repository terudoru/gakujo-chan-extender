import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app_licenses.dart';
import 'src/debug_launch_config.dart';
import 'src/gakujo_web_app.dart';
import 'src/linux_overlay_guard.dart';
import 'src/web_view_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    await configureWindowsWebViewEnvironment();
  }
  final debugLaunchConfig = await DebugLaunchConfig.load();
  runApp(MoreBetterGakujoApp(debugLaunchConfig: debugLaunchConfig));
}

class MoreBetterGakujoApp extends StatefulWidget {
  const MoreBetterGakujoApp({
    required this.debugLaunchConfig,
    super.key,
  });

  final DebugLaunchConfig debugLaunchConfig;

  @override
  State<MoreBetterGakujoApp> createState() => _MoreBetterGakujoAppState();
}

class _MoreBetterGakujoAppState extends State<MoreBetterGakujoApp> {
  final _linuxOverlayObserver = LinuxOverlayObserver();

  @override
  void dispose() {
    _linuxOverlayObserver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [_linuxOverlayObserver],
      title: 'More Better Gakujo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff276749)),
        useMaterial3: true,
      ),
      home: GakujoWebApp(
        startUrl: widget.debugLaunchConfig.startUrl,
        initialTwoFactorSecret: widget.debugLaunchConfig.twoFactorSecret,
        linuxOverlayObscured: _linuxOverlayObserver.obscured,
      ),
    );
  }
}
