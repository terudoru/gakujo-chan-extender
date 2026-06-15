import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

abstract class GakujoWebViewService {
  const GakujoWebViewService();

  WebViewController createController();

  Widget buildWidget(WebViewController controller);

  Future<void> configureController(
    WebViewController controller, {
    required bool debugAllowed,
  });
}

class WebViewFlutterGakujoWebViewService extends GakujoWebViewService {
  const WebViewFlutterGakujoWebViewService();

  @override
  WebViewController createController() => WebViewController();

  @override
  Widget buildWidget(WebViewController controller) {
    return WebViewWidget(controller: controller);
  }

  @override
  Future<void> configureController(
    WebViewController controller, {
    required bool debugAllowed,
  }) async {
    await _configureAndroidController(
      controller,
      debugAllowed: debugAllowed,
    );

    if (kDebugMode) {
      developer.log(
        'Using ${controller.platform.runtimeType} via webview_flutter',
        name: 'MoreBetterGakujo',
      );
    }
  }

  Future<void> _configureAndroidController(
    WebViewController controller, {
    required bool debugAllowed,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final platformController = controller.platform;
    try {
      await (platformController as dynamic).setAllowFileAccess(debugAllowed);
      await (platformController as dynamic).setAllowContentAccess(false);
      await (platformController as dynamic).enableZoom(true);
      await (platformController as dynamic).setUseWideViewPort(true);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to configure Android WebView platform controller',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
