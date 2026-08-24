import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MacosInputFocusService {
  const MacosInputFocusService({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'net.yoshida.morebettergakujo/input_focus',
  );

  final MethodChannel _channel;

  Future<bool> restoreFlutterFirstResponder() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return true;
    }

    try {
      return await _channel
              .invokeMethod<bool>('restoreFlutterFirstResponder') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
