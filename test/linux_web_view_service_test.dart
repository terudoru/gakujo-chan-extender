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

  Future<void> emitEvent(Map<String, Object?> event) async {
    eventSink!.success(event);
    for (var turn = 0; turn < 3; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> emit(Object? direction) =>
      emitEvent({'type': 'mouseHistoryNavigation', 'direction': direction});

  test('Linux plugin dispatches pinch phases, scales and positions', () async {
    final pinches = <(String, double, Offset)>[];
    native.setOnPinchZoom(
      (phase, scale, position) => pinches.add((phase, scale, position)),
    );
    await emitEvent({
      'type': 'pinchZoom',
      'phase': 'begin',
      'scale': 1,
      'x': 120,
      'y': 45.5,
    });
    await emitEvent({
      'type': 'pinchZoom',
      'phase': 'update',
      'scale': 1.25,
      'x': 121.5,
      'y': 46,
    });
    await emitEvent({
      'type': 'pinchZoom',
      'phase': 'end',
      'scale': 1.25,
      'x': 121.5,
      'y': 46,
    });
    expect(pinches, [
      ('begin', 1.0, const Offset(120, 45.5)),
      ('update', 1.25, const Offset(121.5, 46)),
      ('end', 1.25, const Offset(121.5, 46)),
    ]);
    expect(calls, isEmpty);

    native.setOnPinchZoom(null);
    await emitEvent({
      'type': 'pinchZoom',
      'phase': 'begin',
      'scale': 1,
      'x': 0,
      'y': 0,
    });
    expect(pinches, hasLength(3));
    expect(calls, isEmpty);
  });

  test('Linux plugin ignores malformed pinch payloads', () async {
    var dispatched = 0;
    native.setOnPinchZoom((_, _, _) => dispatched++);
    final payload = <String, Object?>{
      'type': 'pinchZoom',
      'phase': 'update',
      'scale': 1.25,
      'x': 12,
      'y': 34,
    };
    for (final field in ['phase', 'scale', 'x', 'y']) {
      await emitEvent(Map<String, Object?>.of(payload)..remove(field));
      for (final invalid in [null, '1', true, double.nan, double.infinity]) {
        await emitEvent({...payload, field: invalid});
      }
    }
    for (final phase in ['', 'cancel', 'UPDATE', 1]) {
      await emitEvent({...payload, 'phase': phase});
    }
    expect(dispatched, 0);
    expect(calls, isEmpty);
  });

  test('Linux pinch events without a handler do nothing', () async {
    for (final phase in ['begin', 'update', 'end']) {
      await emitEvent({
        'type': 'pinchZoom',
        'phase': phase,
        'scale': 1.25,
        'x': 12,
        'y': 34,
      });
    }
    expect(calls, isEmpty);
  });

  test('app adapter forwards and clears Linux pinch callbacks', () async {
    final controller = WebViewFlutterGakujoWebViewController(
      WebViewController.fromPlatform(native),
    );
    final pinches = <(String, double, Offset)>[];
    controller.onPinchZoom = (phase, scale, position) =>
        pinches.add((phase, scale, position));
    for (final phase in ['begin', 'update', 'end']) {
      await emitEvent({
        'type': 'pinchZoom',
        'phase': phase,
        'scale': 0.75,
        'x': 50.5,
        'y': 70,
      });
    }
    expect(pinches, [
      ('begin', 0.75, const Offset(50.5, 70)),
      ('update', 0.75, const Offset(50.5, 70)),
      ('end', 0.75, const Offset(50.5, 70)),
    ]);
    expect(calls, isEmpty);

    controller.onPinchZoom = null;
    await emitEvent({
      'type': 'pinchZoom',
      'phase': 'update',
      'scale': 1.25,
      'x': 0,
      'y': 0,
    });
    expect(pinches, hasLength(3));
    expect(calls, isEmpty);
  });

  test('Linux plugin stops dispatching pinch events after disposal', () async {
    var dispatched = 0;
    native.setOnPinchZoom((_, _, _) => dispatched++);
    await native.dispose();
    calls.clear();
    for (final phase in ['begin', 'update', 'end']) {
      await emitEvent({
        'type': 'pinchZoom',
        'phase': phase,
        'scale': 1.25,
        'x': 12,
        'y': 34,
      });
    }
    expect(dispatched, 0);
    expect(calls, isEmpty);
  });

  test('Linux plugin dispatches wheel notches and positions', () async {
    final zooms = <(double, Offset)>[];
    final scrolls = <(double, double)>[];
    native.setOnWheelZoom((dy, position) => zooms.add((dy, position)));
    native.setOnWheelScroll((dx, dy) => scrolls.add((dx, dy)));
    await emitEvent({'type': 'wheelZoom', 'dy': -1, 'x': 120, 'y': 45.5});
    await emitEvent({'type': 'wheelZoom', 'dy': 0.25, 'x': 10.5, 'y': 20});
    await emitEvent({'type': 'wheelScroll', 'dx': -0.75, 'dy': 0.125});
    await emitEvent({'type': 'wheelScroll', 'dx': 1, 'dy': 0});
    expect(zooms, [
      (-1.0, const Offset(120, 45.5)),
      (0.25, const Offset(10.5, 20)),
    ]);
    expect(scrolls, [(-0.75, 0.125), (1.0, 0.0)]);
    expect(calls, isEmpty);

    native.setOnWheelZoom(null);
    native.setOnWheelScroll(null);
    await emitEvent({'type': 'wheelZoom', 'dy': -1, 'x': 0, 'y': 0});
    await emitEvent({'type': 'wheelScroll', 'dx': 1, 'dy': 0});
    expect(zooms, hasLength(2));
    expect(scrolls, hasLength(2));
    expect(calls, isEmpty);
  });

  test('Linux plugin ignores malformed wheel payloads', () async {
    var dispatched = 0;
    native.setOnWheelZoom((_, _) => dispatched++);
    native.setOnWheelScroll((_, _) => dispatched++);
    final zoom = <String, Object?>{
      'type': 'wheelZoom',
      'dy': -1,
      'x': 12,
      'y': 34,
    };
    final scroll = <String, Object?>{
      'type': 'wheelScroll',
      'dx': 0.5,
      'dy': 0.25,
    };
    for (final payload in [zoom, scroll]) {
      for (final field in payload.keys.where((key) => key != 'type')) {
        final missing = Map<String, Object?>.of(payload)..remove(field);
        await emitEvent(missing);
        for (final invalid in [null, '1', true, double.nan, double.infinity]) {
          await emitEvent({...payload, field: invalid});
        }
      }
    }
    expect(dispatched, 0);
    expect(calls, isEmpty);
  });

  test('Linux wheel events without handlers do nothing', () async {
    await emitEvent({'type': 'wheelZoom', 'dy': -1, 'x': 12, 'y': 34});
    await emitEvent({'type': 'wheelScroll', 'dx': 1, 'dy': 0});
    expect(calls, isEmpty);
  });

  test('app adapter forwards and clears Linux wheel callbacks', () async {
    final controller = WebViewFlutterGakujoWebViewController(
      WebViewController.fromPlatform(native),
    );
    final zooms = <(double, Offset)>[];
    final scrolls = <(double, double)>[];
    controller.onWheelZoom = (dy, position) => zooms.add((dy, position));
    controller.onWheelScroll = (dx, dy) => scrolls.add((dx, dy));
    await emitEvent({'type': 'wheelZoom', 'dy': -0.5, 'x': 50.5, 'y': 70});
    await emitEvent({'type': 'wheelScroll', 'dx': 0.75, 'dy': -0.25});
    expect(zooms, [(-0.5, const Offset(50.5, 70))]);
    expect(scrolls, [(0.75, -0.25)]);
    expect(calls, isEmpty);

    controller.onWheelZoom = null;
    controller.onWheelScroll = null;
    await emitEvent({'type': 'wheelZoom', 'dy': 1, 'x': 0, 'y': 0});
    await emitEvent({'type': 'wheelScroll', 'dx': -1, 'dy': 0});
    expect(zooms, hasLength(1));
    expect(scrolls, hasLength(1));
    expect(calls, isEmpty);
  });

  test('Linux plugin stops dispatching wheel events after disposal', () async {
    var dispatched = 0;
    native.setOnWheelZoom((_, _) => dispatched++);
    native.setOnWheelScroll((_, _) => dispatched++);
    await native.dispose();
    calls.clear();
    await emitEvent({'type': 'wheelZoom', 'dy': -1, 'x': 12, 'y': 34});
    await emitEvent({'type': 'wheelScroll', 'dx': 1, 'dy': 0});
    expect(dispatched, 0);
    expect(calls, isEmpty);
  });

  test(
    'Linux plugin dispatches find requests, directions and results',
    () async {
      var requested = 0;
      final directions = <bool>[];
      final results = <(int, bool)>[];
      native.setOnFindRequest(() => requested++);
      native.setOnFindAgain(directions.add);
      native.setOnFindResult((matches, found) => results.add((matches, found)));

      await emitEvent({'type': 'findRequested'});
      await emitEvent({'type': 'findAgain', 'forward': true});
      await emitEvent({'type': 'findAgain', 'forward': false});
      await emitEvent({'type': 'findResult', 'matches': 4, 'found': true});
      await emitEvent({'type': 'findResult', 'matches': 0, 'found': false});
      expect(requested, 1);
      expect(directions, [true, false]);
      expect(results, [(4, true), (0, false)]);
      expect(calls, isEmpty);

      native.setOnFindRequest(null);
      native.setOnFindAgain(null);
      native.setOnFindResult(null);
      await emitEvent({'type': 'findRequested'});
      await emitEvent({'type': 'findAgain', 'forward': true});
      await emitEvent({'type': 'findResult', 'matches': 2, 'found': true});
      expect(requested, 1);
      expect(directions, [true, false]);
      expect(results, [(4, true), (0, false)]);
    },
  );

  test('Linux plugin ignores malformed find event payloads', () async {
    final directions = <bool>[];
    final results = <(int, bool)>[];
    native.setOnFindAgain(directions.add);
    native.setOnFindResult((matches, found) => results.add((matches, found)));
    for (final forward in [null, 'true', 1]) {
      await emitEvent({'type': 'findAgain', 'forward': forward});
    }
    await emitEvent({'type': 'findResult', 'matches': '4', 'found': true});
    await emitEvent({'type': 'findResult', 'matches': 4, 'found': null});
    await emitEvent({'type': 'findResult'});
    expect(directions, isEmpty);
    expect(results, isEmpty);
    expect(calls, isEmpty);
  });

  test('Linux plugin sends findText and findFinish to its instance', () async {
    await native.findText('ページ');
    await native.findText('ページ', forward: false);
    await native.findText('');
    await native.finishFind();
    expect(calls.map((call) => call.method), [
      'findText',
      'findText',
      'findText',
      'findFinish',
    ]);
    expect(calls.map((call) => call.arguments), [
      {'text': 'ページ', 'forward': true},
      {'text': 'ページ', 'forward': false},
      {'text': '', 'forward': true},
      {'focusPage': false},
    ]);
  });

  test(
    'app adapter forwards and clears Linux find callbacks and methods',
    () async {
      final controller = WebViewFlutterGakujoWebViewController(
        WebViewController.fromPlatform(native),
      );
      var requested = 0;
      final directions = <bool>[];
      final results = <(int, bool)>[];
      controller.onFindRequest = () => requested++;
      controller.onFindAgain = directions.add;
      controller.onFindResult = (matches, found) =>
          results.add((matches, found));
      await emitEvent({'type': 'findRequested'});
      await emitEvent({'type': 'findAgain', 'forward': false});
      await emitEvent({'type': 'findResult', 'matches': 7, 'found': true});
      expect(requested, 1);
      expect(directions, [false]);
      expect(results, [(7, true)]);

      await controller.findText('term');
      await controller.findText('term', forward: false);
      await controller.finishFind();
      expect(calls.map((call) => call.method), [
        'findText',
        'findText',
        'findFinish',
      ]);
      expect(calls.map((call) => call.arguments), [
        {'text': 'term', 'forward': true},
        {'text': 'term', 'forward': false},
        {'focusPage': false},
      ]);

      controller.onFindRequest = null;
      controller.onFindAgain = null;
      controller.onFindResult = null;
      await emitEvent({'type': 'findRequested'});
      await emitEvent({'type': 'findAgain', 'forward': true});
      await emitEvent({'type': 'findResult', 'matches': 0, 'found': false});
      expect(requested, 1);
      expect(directions, [false]);
      expect(results, [(7, true)]);
    },
  );

  test('Linux plugin stops dispatching find events after disposal', () async {
    var dispatched = 0;
    native.setOnFindRequest(() => dispatched++);
    native.setOnFindAgain((_) => dispatched++);
    native.setOnFindResult((_, _) => dispatched++);
    await native.dispose();
    calls.clear();
    await emitEvent({'type': 'findRequested'});
    await emitEvent({'type': 'findAgain', 'forward': true});
    await emitEvent({'type': 'findResult', 'matches': 1, 'found': true});
    expect(dispatched, 0);
    expect(calls, isEmpty);
  });

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
