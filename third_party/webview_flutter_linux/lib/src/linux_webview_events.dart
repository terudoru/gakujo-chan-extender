part of 'linux_webview_controller.dart';

extension LinuxWebViewControllerEventHandling on LinuxWebViewController {
  void _handleEvent(dynamic event) {
    if (_disposed || event is! Map) {
      return;
    }

    final String? type = event['type'] as String?;
    switch (type) {
      // More Better Gakujo patch: only the outcome of downloads WebKit saved
      // on its own is exposed; delegated download events are not.
      case 'downloadSaved':
        final url = event['url'];
        final path = event['path'];
        if (url is String && path is String && path.isNotEmpty) {
          _dispatchEventHandler('download saved', () async {
            _onDownloadSaved?.call(url, path);
          });
        }
        break;
      case 'downloadFailed':
        final url = event['url'];
        if (url is String) {
          final description = event['description'];
          _dispatchEventHandler('download failed', () async {
            _onDownloadFailed?.call(
              url,
              description is String ? description : '',
            );
          });
        }
        break;
      case 'urlChanged':
        final String url = '${event['url'] ?? ''}';
        _currentUrl = url;
        _navigationDelegate?.handleUrlChange(url);
        break;
      case 'pageStarted':
        final String url = '${event['url'] ?? ''}';
        _currentUrl = url;
        _navigationDelegate?.handlePageStarted(url);
        break;
      case 'pageFinished':
        final String url = '${event['url'] ?? ''}';
        _currentUrl = url;
        _navigationDelegate?.handlePageFinished(url);
        break;
      case 'progress':
        _navigationDelegate?.handleProgress(
          (event['progress'] as num?)?.round() ?? 0,
        );
        break;
      case 'historyChanged':
        _canGoBack = event['canGoBack'] == true;
        _canGoForward = event['canGoForward'] == true;
        break;
      // More Better Gakujo patch: app history understands flow-key pages.
      case 'mouseHistoryNavigation':
        _dispatchEventHandler(
          'history navigation request',
          () => _handleHistoryNavigationRequestEvent(event),
        );
        break;
      case 'wheelZoom':
        final zoomDy = event['dy'];
        final x = event['x'];
        final y = event['y'];
        if (zoomDy is num &&
            x is num &&
            y is num &&
            zoomDy.isFinite &&
            x.isFinite &&
            y.isFinite) {
          _dispatchEventHandler('wheel zoom', () async {
            _onWheelZoom?.call(
              zoomDy.toDouble(),
              Offset(x.toDouble(), y.toDouble()),
            );
          });
        }
        break;
      case 'keyZoom':
        final action = switch (event['action']) {
          'in' => LinuxKeyZoomAction.zoomIn,
          'out' => LinuxKeyZoomAction.zoomOut,
          'reset' => LinuxKeyZoomAction.reset,
          _ => null,
        };
        if (action != null) {
          _dispatchEventHandler('key zoom', () async {
            _onKeyZoom?.call(action);
          });
        }
        break;
      case 'pinchZoom':
        final phase = event['phase'];
        final scale = event['scale'];
        final x = event['x'];
        final y = event['y'];
        if (phase is String &&
            (phase == 'begin' || phase == 'update' || phase == 'end') &&
            scale is num &&
            x is num &&
            y is num &&
            scale.isFinite &&
            x.isFinite &&
            y.isFinite) {
          _dispatchEventHandler('pinch zoom', () async {
            _onPinchZoom?.call(
              phase,
              scale.toDouble(),
              Offset(x.toDouble(), y.toDouble()),
            );
          });
        }
        break;
      case 'wheelScroll':
        final dx = event['dx'];
        final dy = event['dy'];
        if (dx is num && dy is num && dx.isFinite && dy.isFinite) {
          _dispatchEventHandler('wheel scroll', () async {
            _onWheelScroll?.call(dx.toDouble(), dy.toDouble());
          });
        }
        break;
      // More Better Gakujo patch: search UI is outside the native WebView.
      case 'findRequested':
        _dispatchEventHandler('find request', () async {
          _onFindRequest?.call();
        });
        break;
      case 'findAgain':
        final forward = event['forward'];
        if (forward is bool) {
          _dispatchEventHandler('find again', () async {
            _onFindAgain?.call(forward);
          });
        }
        break;
      case 'findResult':
        final matches = event['matches'];
        final found = event['found'];
        if (matches is int && found is bool) {
          _dispatchEventHandler('find result', () async {
            _onFindResult?.call(matches, found);
          });
        }
        break;
      case 'titleChanged':
        _title = event['title'] as String?;
        // More Better Gakujo patch: retain the title for getTitle only.
        break;
      case 'webResourceError':
        _navigationDelegate?.handleWebResourceError(
          LinuxWebResourceError.fromMap(event),
        );
        break;
      case 'httpError':
        if (_navigationDelegate != null) {
          final Uri? uri = Uri.tryParse('${event['url'] ?? ''}');
          final Map<String, String> requestHeaders = _stringMapFromEvent(
            event['requestHeaders'],
          );
          final Map<String, String> responseHeaders = _stringMapFromEvent(
            event['headers'],
          );
          _navigationDelegate!.handleHttpError(
            HttpResponseError(
              request: uri == null
                  ? null
                  : LinuxWebResourceRequest(
                      uri: uri,
                      method: event['method'] as String?,
                      headers: requestHeaders,
                      isForMainFrame: event['isForMainFrame'] as bool? ?? true,
                    ),
              response: LinuxWebResourceResponse(
                uri: uri,
                statusCode: (event['statusCode'] as num?)?.toInt() ?? 0,
                headers: responseHeaders,
                mimeType: event['mimeType'] as String?,
              ),
            ),
          );
        }
        break;
      case 'javaScriptChannelMessage':
        final String name = '${event['channelName'] ?? ''}';
        final JavaScriptChannelParams? params = _javaScriptChannels[name];
        if (params != null) {
          params.onMessageReceived(
            // More Better Gakujo patch: the standard message has no source fields.
            JavaScriptMessage(
              message: '${event['message'] ?? ''}',
            ),
          );
        }
        break;
      case 'consoleMessage':
        final callback = _onConsoleMessage;
        if (callback != null) {
          callback(
            JavaScriptConsoleMessage(
              level: _parseJavaScriptLogLevel(event['level'] as String?),
              message: '${event['message'] ?? ''}',
            ),
          );
        }
        break;
      case 'scrollPositionChange':
        final callback = _onScrollPositionChange;
        if (callback != null) {
          callback(
            ScrollPositionChange(
              (event['x'] as num?)?.toDouble() ?? 0,
              (event['y'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
        break;
      case 'navigationRequest':
        _dispatchEventHandler(
          'navigation request',
          () => _handleNavigationRequestEvent(event),
        );
        break;
      case 'httpAuthRequest':
        _dispatchEventHandler(
          'HTTP authentication request',
          () => _handleHttpAuthRequestEvent(event),
        );
        break;
      case 'sslAuthError':
        _dispatchEventHandler(
          'TLS authentication request',
          () => _handleSslAuthErrorEvent(event),
        );
        break;
      case 'permissionRequest':
        _dispatchEventHandler(
          'permission request',
          () => _handlePermissionRequestEvent(event),
        );
        break;
      case 'javaScriptDialog':
        _dispatchEventHandler(
          'JavaScript dialog',
          () => _handleJavaScriptDialogEvent(event),
        );
        break;
    }
  }

  Future<void> _handleHistoryNavigationRequestEvent(
    Map<dynamic, dynamic> event,
  ) async {
    final direction = event['direction'];
    if (direction != 'back' && direction != 'forward') {
      return;
    }
    final bool back = direction == 'back';
    final callback = _onHistoryNavigationRequest;
    if (callback != null) {
      await callback(back);
    } else if (back) {
      if (await canGoBack()) {
        await goBack();
      }
    } else if (await canGoForward()) {
      await goForward();
    }
  }

  Future<void> _handleNavigationRequestEvent(
    Map<dynamic, dynamic> event,
  ) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    bool allow = true;
    if (_navigationDelegate?.hasNavigationRequestHandler ?? false) {
      try {
        final NavigationDecision? decision = await _navigationDelegate!
            .decideNavigation(
              NavigationRequest(
                url: '${event['url'] ?? ''}',
                isMainFrame: event['isMainFrame'] != false,
              ),
            );
        allow = decision == NavigationDecision.navigate;
      } catch (error, stackTrace) {
        allow = false;
        _reportEventError('application navigation callback', error, stackTrace);
      }
    }

    await _invoke<void>('completeNavigationRequest', <String, Object?>{
      'requestId': requestId,
      'allow': allow,
    });
  }

  Future<void> _handleHttpAuthRequestEvent(Map<dynamic, dynamic> event) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    if (!(_navigationDelegate?.hasHttpAuthRequestHandler ?? false)) {
      await _invoke<void>('completeHttpAuthRequest', <String, Object?>{
        'requestId': requestId,
        'action': 'cancel',
      });
      return;
    }

    var completed = false;
    Future<void> complete(Map<String, Object?> arguments) {
      if (completed) {
        return Future<void>.value();
      }
      completed = true;
      return _invoke<void>('completeHttpAuthRequest', arguments);
    }

    try {
      _navigationDelegate!.handleHttpAuthRequest(
        HttpAuthRequest(
          host: '${event['host'] ?? ''}',
          realm: event['realm'] as String?,
          onProceed: (WebViewCredential credential) {
            _dispatchEventHandler(
              'HTTP authentication completion',
              () => complete(<String, Object?>{
                'requestId': requestId,
                'action': 'proceed',
                'user': credential.user,
                'password': credential.password,
              }),
            );
          },
          onCancel: () {
            _dispatchEventHandler(
              'HTTP authentication completion',
              () => complete(<String, Object?>{
                'requestId': requestId,
                'action': 'cancel',
              }),
            );
          },
        ),
      );
    } catch (error, stackTrace) {
      _reportEventError(
        'application HTTP authentication callback',
        error,
        stackTrace,
      );
      await complete(<String, Object?>{
        'requestId': requestId,
        'action': 'cancel',
      });
    }
  }

  Future<void> _handleSslAuthErrorEvent(Map<dynamic, dynamic> event) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    if (!(_navigationDelegate?.hasSslAuthErrorHandler ?? false)) {
      await _invoke<void>('completeSslAuthError', <String, Object?>{
        'requestId': requestId,
        'proceed': false,
      });
      return;
    }

    final LinuxPlatformSslAuthError request = LinuxPlatformSslAuthError(
      description: '${event['description'] ?? 'TLS certificate error'}',
      onProceed: () {
        return _invoke<void>('completeSslAuthError', <String, Object?>{
          'requestId': requestId,
          'proceed': true,
        });
      },
      onCancel: () {
        return _invoke<void>('completeSslAuthError', <String, Object?>{
          'requestId': requestId,
          'proceed': false,
        });
      },
    );
    try {
      _navigationDelegate!.handleSslAuthError(request);
    } catch (error, stackTrace) {
      _reportEventError(
        'application TLS authentication callback',
        error,
        stackTrace,
      );
      await request.cancel();
    }
  }

  Future<void> _handlePermissionRequestEvent(
    Map<dynamic, dynamic> event,
  ) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    final rawTypes = (event['types'] as List<Object?>?) ?? const <Object?>[];
    const supported = {'camera', 'microphone', 'geolocation', 'notifications'};
    if (rawTypes.isEmpty ||
        rawTypes.any((type) => !supported.contains(type))) {
      await _invoke<void>('completePermissionRequest', <String, Object?>{
        'requestId': requestId,
        'grant': false,
      });
      return;
    }
    final callback = _onPermissionRequest;
    if (callback == null) {
      await _invoke<void>('showPermissionRequest', <String, Object?>{
        'requestId': requestId,
      });
      return;
    }

    final Set<WebViewPermissionResourceType> types = rawTypes
        .map((Object? type) => _parsePermissionType(type as String?))
        .whereType<WebViewPermissionResourceType>()
        .toSet();
    if (types.isEmpty) {
      await _invoke<void>('completePermissionRequest', <String, Object?>{
        'requestId': requestId,
        'grant': false,
      });
      return;
    }

    final LinuxPlatformWebViewPermissionRequest request =
        LinuxPlatformWebViewPermissionRequest(
          types: types,
          onGrant: () {
            return _invoke<void>('completePermissionRequest', <String, Object?>{
              'requestId': requestId,
              'grant': true,
            });
          },
          onDeny: () {
            return _invoke<void>('completePermissionRequest', <String, Object?>{
              'requestId': requestId,
              'grant': false,
            });
          },
        );
    try {
      callback(request);
    } catch (error, stackTrace) {
      _reportEventError('application permission callback', error, stackTrace);
      await request.deny();
    }
  }

  Future<void> _handleJavaScriptDialogEvent(Map<dynamic, dynamic> event) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    final String dialogType = '${event['dialogType'] ?? ''}';
    final String message = '${event['message'] ?? ''}';
    final String url = '${event['url'] ?? ''}';
    try {
      switch (dialogType) {
        case 'alert':
          final callback = _onJavaScriptAlertDialog;
          if (callback == null) {
            await _completeJavaScriptDialog(requestId, action: 'confirm');
            return;
          }
          await callback(
            JavaScriptAlertDialogRequest(message: message, url: url),
          );
          await _completeJavaScriptDialog(requestId, action: 'confirm');
          return;
        case 'confirm':
        case 'beforeUnloadConfirm':
          final callback = _onJavaScriptConfirmDialog;
          if (callback == null) {
            await _completeJavaScriptDialog(requestId, action: 'confirm');
            return;
          }
          final bool confirmed = await callback(
            JavaScriptConfirmDialogRequest(message: message, url: url),
          );
          await _completeJavaScriptDialog(
            requestId,
            action: confirmed ? 'confirm' : 'cancel',
          );
          return;
        case 'prompt':
          final callback = _onJavaScriptTextInputDialog;
          if (callback == null) {
            await _completeJavaScriptDialog(
              requestId,
              action: 'confirm',
              text: (event['defaultText'] as String?) ?? '',
            );
            return;
          }
          final String text = await callback(
            JavaScriptTextInputDialogRequest(
              message: message,
              url: url,
              defaultText: event['defaultText'] as String?,
            ),
          );
          await _completeJavaScriptDialog(
            requestId,
            action: 'confirm',
            text: text,
          );
          return;
      }
    } catch (error, stackTrace) {
      _reportEventError(
        'application JavaScript dialog callback',
        error,
        stackTrace,
      );
      await _completeJavaScriptDialog(requestId, action: 'cancel');
      return;
    }

    await _completeJavaScriptDialog(requestId, action: 'cancel');
  }

  Future<void> _completeJavaScriptDialog(
    int requestId, {
    required String action,
    String? text,
  }) {
    return _invoke<void>('completeJavaScriptDialog', <String, Object?>{
      'requestId': requestId,
      'action': action,
      'text': text,
    });
  }

  JavaScriptLogLevel _parseJavaScriptLogLevel(String? level) {
    switch (level) {
      case 'debug':
        return JavaScriptLogLevel.debug;
      case 'error':
        return JavaScriptLogLevel.error;
      case 'info':
        return JavaScriptLogLevel.info;
      case 'warning':
        return JavaScriptLogLevel.warning;
      default:
        return JavaScriptLogLevel.log;
    }
  }

  WebViewPermissionResourceType? _parsePermissionType(String? type) {
    switch (type) {
      case 'camera':
        return WebViewPermissionResourceType.camera;
      case 'microphone':
        return WebViewPermissionResourceType.microphone;
    }
    return null;
  }
}

Map<String, String> _stringMapFromEvent(Object? value) {
  final Map<String, String> result = <String, String>{};
  if (value case final Map<dynamic, dynamic> rawHeaders) {
    for (final MapEntry<dynamic, dynamic> header in rawHeaders.entries) {
      result['${header.key}'] = '${header.value}';
    }
  }
  return result;
}
