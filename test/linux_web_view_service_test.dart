import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const instance = MethodChannel('com.abandoft.webview_all_linux/73');
  const events = EventChannel('com.abandoft.webview_all_linux/73/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LinuxWebViewController native;
  late List<MethodCall> calls;
  late MockStreamHandlerEventSink? eventSink;
  var canGoBack = false;
  var canGoForward = false;

  setUp(() async {
    calls = [];
    eventSink = null;
    canGoBack = false;
    canGoForward = false;
    messenger.setMockMethodCallHandler(LinuxWebViewController.rootChannel, (
      call,
    ) async {
      if (call.method == 'createWebView') return 73;
      return null;
    });
    messenger.setMockMethodCallHandler(instance, (call) async {
      calls.add(call);
      if (call.method == 'canGoBack') return canGoBack;
      if (call.method == 'canGoForward') return canGoForward;
      return null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          eventSink = sink;
        },
      ),
    );
    native = LinuxWebViewController(
      const LinuxWebViewControllerCreationParams(),
    );
    addTearDown(native.dispose);
    // Wait for construction and the event subscription without a real WebView.
    await native.currentUrl();
    expect(eventSink, isNotNull);
    calls.clear();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      LinuxWebViewController.rootChannel,
      null,
    );
    messenger.setMockMethodCallHandler(instance, null);
    messenger.setMockStreamHandler(events, null);
  });

  Future<void> emit(Object? direction) async {
    eventSink!.success({
      'type': 'mouseHistoryNavigation',
      'direction': direction,
    });
    for (var turn = 0; turn < 3; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'Linux plugin forwards both directions without native navigation',
    () async {
      final requested = <bool>[];
      native.setOnHistoryNavigationRequest((back) async {
        requested.add(back);
      });
      await emit('back');
      await emit('forward');
      expect(requested, [true, false]);
      expect(calls, isEmpty);
    },
  );

  for (final back in [true, false]) {
    for (final allowed in [true, false]) {
      final direction = back ? 'back' : 'forward';
      final query = back ? 'canGoBack' : 'canGoForward';
      final navigate = back ? 'goBack' : 'goForward';
      test(
        'Linux plugin falls back $direction only when allowed: $allowed',
        () async {
          canGoBack = back ? allowed : !allowed;
          canGoForward = back ? !allowed : allowed;
          await emit(direction);
          expect(calls.map((call) => call.method), [
            query,
            if (allowed) navigate,
          ]);
        },
      );
    }
  }

  test('Linux plugin ignores invalid history directions', () async {
    final requested = <bool>[];
    native.setOnHistoryNavigationRequest((back) async => requested.add(back));
    for (final direction in [null, '', 'up', true]) {
      await emit(direction);
    }
    expect(requested, isEmpty);
    expect(calls, isEmpty);
    native.setOnHistoryNavigationRequest(null);
    await emit('invalid');
    expect(calls, isEmpty);
  });

  for (final asynchronous in [false, true]) {
    test(
      'Linux plugin logs history callback errors (async: $asynchronous)',
      () async {
        final messages = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) messages.add(message);
        };
        addTearDown(() => debugPrint = previousDebugPrint);
        native.setOnHistoryNavigationRequest((back) {
          final error = StateError('history callback failed');
          if (asynchronous) return Future<void>.error(error);
          throw error;
        });
        await emit('back');
        expect(messages, [contains('history navigation request failed:')]);
        expect(calls, isEmpty);

        final requested = <bool>[];
        native.setOnHistoryNavigationRequest(
          (back) async => requested.add(back),
        );
        await emit('forward');
        expect(requested, [false]);
      },
    );
  }

  test(
    'app adapter maps Linux requests and clearing it restores fallback',
    () async {
      final controller = WebViewFlutterGakujoWebViewController(
        WebViewController.fromPlatform(native),
      );
      final requested = <MouseHistoryNavigation>[];
      controller.onMouseHistoryNavigation = (direction) async {
        requested.add(direction);
      };
      await emit('back');
      await emit('forward');
      expect(requested, [
        MouseHistoryNavigation.back,
        MouseHistoryNavigation.forward,
      ]);
      expect(calls, isEmpty);

      controller.onMouseHistoryNavigation = null;
      canGoBack = true;
      await emit('back');
      expect(calls.map((call) => call.method), ['canGoBack', 'goBack']);
      expect(requested, hasLength(2));
    },
  );
}
