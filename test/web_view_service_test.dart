import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  for (final isMainFrame in [false, true]) {
    test('preserves navigation frame flag $isMainFrame from WKWebView', () {
      final mapped = GakujoNavigationRequest.fromWebViewFlutter(
        NavigationRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
          isMainFrame: isMainFrame,
        ),
      );
      expect(mapped.isMainFrame, isMainFrame);
      expect(mapped.url, endsWith('/campusportal.do'));
    });
  }

  group('mobile resource errors', () {
    const connectivityTypes = {
      WebResourceErrorType.hostLookup,
      WebResourceErrorType.connect,
      WebResourceErrorType.timeout,
      WebResourceErrorType.io,
    };

    for (final type in WebResourceErrorType.values) {
      test('maps ${type.name} without treating other failures as offline', () {
        final mapped = GakujoWebResourceError.fromWebViewFlutter(
          WebResourceError(
            errorCode: -1,
            description: 'load failed',
            errorType: type,
          ),
        );
        expect(mapped.description, 'load failed');
        expect(mapped.isConnectivityError, connectivityTypes.contains(type));
        expect(mapped.isForMainFrame, isTrue);
      });
    }

    for (final type in [WebResourceErrorType.unknown, null]) {
      for (final description in [
        'net::ERR_INTERNET_DISCONNECTED',
        'net::err_name_not_resolved',
        'Failed: ERR_NETWORK_CHANGED',
        'net::ERR_CONNECTION_REFUSED',
        'net::err_connection_reset',
        'net::ERR_CONNECTION_ABORTED',
        'net::ERR_CONNECTION_CLOSED',
        'net::ERR_CONNECTION_TIMED_OUT',
        'net::ERR_ADDRESS_UNREACHABLE',
      ]) {
        test('recognizes $description when the type is $type', () {
          final mapped = GakujoWebResourceError.fromWebViewFlutter(
            WebResourceError(
              errorCode: -1,
              description: description,
              errorType: type,
            ),
          );
          expect(mapped.description, description);
          expect(mapped.isConnectivityError, isTrue);
        });
      }
    }

    for (final isForMainFrame in [true, false, null]) {
      test('preserves main-frame flag $isForMainFrame', () {
        final mapped = GakujoWebResourceError.fromWebViewFlutter(
          WebResourceError(
            errorCode: -1,
            description: 'net::ERR_INTERNET_DISCONNECTED',
            errorType: WebResourceErrorType.unknown,
            isForMainFrame: isForMainFrame,
          ),
        );
        expect(mapped.isForMainFrame, isForMainFrame ?? true);
        expect(mapped.isConnectivityError, isTrue);
      });
    }

    for (final type in [WebResourceErrorType.unknown, null]) {
      test('recognizes Apple connectivity codes when the type is $type', () {
        for (final code in [-1009, -1004, -1003, -1001, -1005, -1020, -1018]) {
          final mapped = GakujoWebResourceError.fromWebViewFlutter(
            WebResourceError(
              errorCode: code,
              description: 'Localized WKWebView error',
              errorType: type,
              isForMainFrame: false,
            ),
          );
          expect(mapped.isConnectivityError, isTrue, reason: '$code');
          expect(mapped.isForMainFrame, isFalse);
        }
      });

      test('does not classify unrelated codes as offline with type $type', () {
        for (final code in [
          -999,
          -1002,
          -1011,
          -1200,
          -1202,
          for (var androidCode = -1; androidCode >= -16; androidCode--)
            androidCode,
        ]) {
          final mapped = GakujoWebResourceError.fromWebViewFlutter(
            WebResourceError(
              errorCode: code,
              description: 'Localized non-connectivity error',
              errorType: type,
            ),
          );
          expect(mapped.isConnectivityError, isFalse, reason: '$code');
        }
      });
    }

    test('does not infer offline from certificate or cancelled errors', () {
      for (final description in [
        'net::ERR_CERT_AUTHORITY_INVALID',
        'net::ERR_ABORTED',
        'unknown failure',
      ]) {
        final mapped = GakujoWebResourceError.fromWebViewFlutter(
          WebResourceError(
            errorCode: -1,
            description: description,
            errorType: WebResourceErrorType.unknown,
          ),
        );
        expect(mapped.isConnectivityError, isFalse, reason: description);
      }
      expect(
        GakujoWebResourceError.fromWebViewFlutter(const WebResourceError(
          errorCode: -1,
          description: 'ERR_CONNECTION_RESET',
          errorType: WebResourceErrorType.failedSslHandshake,
        )).isConnectivityError,
        isFalse,
      );
    });

    test('legacy resource errors default to main-frame and non-connectivity',
        () {
      const error = GakujoWebResourceError(description: 'load failed');
      expect(error.isForMainFrame, isTrue);
      expect(error.isConnectivityError, isFalse);
    });
  });

  test('cookiePathMatches follows RFC6265 path boundaries', () {
    expect(cookiePathMatches('/foo', '/foo'), isTrue);
    expect(cookiePathMatches('/foo/bar', '/foo'), isTrue);
    expect(cookiePathMatches('/foobar', '/foo'), isFalse);
    expect(cookiePathMatches('/foo', '/foo/'), isFalse);
    expect(cookiePathMatches('/foo/bar', '/foo/'), isTrue);
    expect(cookiePathMatches('/anything', '/'), isTrue);
  });

  test('native browser history gestures are enabled on Apple WebViews', () {
    expect(supportsNativeGakujoHistoryGestures(TargetPlatform.iOS), isTrue);
    expect(supportsNativeGakujoHistoryGestures(TargetPlatform.macOS), isTrue);
    expect(
        supportsNativeGakujoHistoryGestures(TargetPlatform.android), isFalse);
    expect(
        supportsNativeGakujoHistoryGestures(TargetPlatform.windows), isFalse);
  });

  test('Android upload filters map HTML accept values to type groups', () {
    final groups = androidUploadTypeGroups(['.PDF, image/*', '.docx']);
    expect(groups, hasLength(1));
    expect(groups.single.extensions, unorderedEquals(['pdf', 'docx']));
    expect(groups.single.mimeTypes, ['image/*']);
  });

  test('Android upload filters allow any file without a usable filter', () {
    expect(androidUploadTypeGroups(const []), isEmpty);
    expect(androidUploadTypeGroups(['']), isEmpty);
    expect(androidUploadTypeGroups(['.pdf', '*/*']), isEmpty);
    expect(androidUploadTypeGroups(['audio']), isEmpty);
  });

  test('Flutter handles JavaScript dialogs only for WKWebView platforms', () {
    expect(needsFlutterJavaScriptDialogs(TargetPlatform.iOS), isTrue);
    expect(needsFlutterJavaScriptDialogs(TargetPlatform.macOS), isTrue);
    expect(needsFlutterJavaScriptDialogs(TargetPlatform.android), isFalse);
    expect(needsFlutterJavaScriptDialogs(TargetPlatform.windows), isFalse);
  });

  test('mouse side buttons map to WebView history navigation', () {
    expect(
      mouseHistoryNavigation(const PointerDownEvent(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      )),
      MouseHistoryNavigation.back,
    );
    expect(
      mouseHistoryNavigation(const PointerDownEvent(
        kind: PointerDeviceKind.mouse,
        buttons: kForwardMouseButton,
      )),
      MouseHistoryNavigation.forward,
    );
    expect(
      mouseHistoryNavigation(const PointerDownEvent(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton | kBackMouseButton,
      )),
      isNull,
    );
    expect(
      mouseHistoryNavigation(const PointerDownEvent(
        kind: PointerDeviceKind.touch,
        buttons: kBackMouseButton,
      )),
      isNull,
    );
  });

  test('Android offers the camera only when the input accepts photos', () {
    expect(androidUploadAcceptsPhotos(const []), isTrue);
    expect(androidUploadAcceptsPhotos(['image/*']), isTrue);
    expect(androidUploadAcceptsPhotos(['.pdf,.jpg']), isTrue);
    expect(androidUploadAcceptsPhotos(['.pdf']), isFalse);
    expect(androidUploadAcceptsPhotos(['.png']), isFalse);
    expect(androidUploadAcceptsPhotos(['application/pdf']), isFalse);
  });

  test('content process recovery allows only three attempts per rolling minute',
      () {
    final recoveries = <Duration>[];
    for (final seconds in [0, 10, 20]) {
      expect(
        consumeContentProcessRecoveryAttempt(
            recoveries, Duration(seconds: seconds)),
        isTrue,
      );
    }
    for (final milliseconds in [30000, 59999]) {
      expect(
        consumeContentProcessRecoveryAttempt(
            recoveries, Duration(milliseconds: milliseconds)),
        isFalse,
      );
    }
    expect(recoveries, hasLength(3));
    for (final milliseconds in [60000, 60001, 70000, 80000]) {
      expect(
        consumeContentProcessRecoveryAttempt(
            recoveries, Duration(milliseconds: milliseconds)),
        milliseconds != 60001,
      );
    }
    expect(recoveries, const [
      Duration(seconds: 60),
      Duration(seconds: 70),
      Duration(seconds: 80),
    ]);
  });

  test('reloads the current allowed page after a content process ends', () {
    const report =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?_flowExecutionKey=e1s2';
    expect(contentProcessRecoveryUrl(report), report);
    expect(
      contentProcessRecoveryUrl(null),
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    );
    expect(
      contentProcessRecoveryUrl('about:blank'),
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    );
    expect(
      contentProcessRecoveryUrl('https://example.com/'),
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    );
  });
}
