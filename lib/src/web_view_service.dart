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
    if (!kDebugMode) {
      return;
    }

    developer.log(
      'Using ${controller.platform.runtimeType} via webview_flutter',
      name: 'MoreBetterGakujo',
    );
  }
}
