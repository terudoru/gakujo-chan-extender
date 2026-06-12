import 'package:flutter/material.dart';

import 'src/debug_launch_config.dart';
import 'src/gakujo_web_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final debugLaunchConfig = await DebugLaunchConfig.load();
  runApp(MoreBetterGakujoApp(debugLaunchConfig: debugLaunchConfig));
}

class MoreBetterGakujoApp extends StatelessWidget {
  const MoreBetterGakujoApp({
    required this.debugLaunchConfig,
    super.key,
  });

  final DebugLaunchConfig debugLaunchConfig;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'More Better Gakujo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff276749)),
        useMaterial3: true,
      ),
      home: GakujoWebApp(
        startUrl: debugLaunchConfig.startUrl,
        initialTwoFactorSecret: debugLaunchConfig.twoFactorSecret,
      ),
    );
  }
}
