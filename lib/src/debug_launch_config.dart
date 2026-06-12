import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DebugLaunchConfig {
  const DebugLaunchConfig({
    this.startUrl,
    this.twoFactorSecret,
  });

  final String? startUrl;
  final String? twoFactorSecret;

  static const _channel = MethodChannel(
    'net.yoshida.morebettergakujo/debug_launch',
  );

  static Future<DebugLaunchConfig> load() async {
    if (!kDebugMode) {
      return const DebugLaunchConfig();
    }

    try {
      final raw = await _channel.invokeMapMethod<String, String>(
        'getDebugLaunchConfig',
      );
      return DebugLaunchConfig(
        startUrl: raw?['startUrl'],
        twoFactorSecret: raw?['twoFactorSecret'],
      );
    } on MissingPluginException {
      return const DebugLaunchConfig();
    }
  }
}
