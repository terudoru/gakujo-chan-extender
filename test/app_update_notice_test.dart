import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/app_update_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/widgets/app_update_banner.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  const release = AppUpdateInfo(
    currentVersion: '1.0.0',
    latestVersion: 'v2.0.0',
    releaseUrl: 'https://example.com',
    hasUpdate: true,
    assetNames: ['app.APK', 'app.dmg', 'app.exe', 'app.tar.gz'],
  );

  test('matches installers for each platform', () {
    expect(release.hasInstallerFor(TargetPlatform.android), isTrue);
    expect(release.hasInstallerFor(TargetPlatform.iOS), isFalse);
    expect(release.hasInstallerFor(TargetPlatform.macOS), isTrue);
    expect(release.hasInstallerFor(TargetPlatform.windows), isTrue);
    expect(release.hasInstallerFor(TargetPlatform.linux), isTrue);
    expect(release.hasInstallerFor(TargetPlatform.fuchsia), isFalse);
    const alternatives = AppUpdateInfo(
      currentVersion: '1',
      latestVersion: '2',
      releaseUrl: '',
      hasUpdate: true,
      assetNames: ['app.IPA', 'app.ZIP', 'app.DEB'],
    );
    expect(alternatives.hasInstallerFor(TargetPlatform.iOS), isTrue);
    expect(alternatives.hasInstallerFor(TargetPlatform.windows), isTrue);
    expect(alternatives.hasInstallerFor(TargetPlatform.linux), isTrue);
  });

  test('checks after 24 hours or when the clock moves back', () {
    final now = DateTime(2026, 1, 2);
    expect(isUpdateCheckDue(null, now), isTrue);
    expect(
      isUpdateCheckDue(
        now
            .subtract(const Duration(hours: 24))
            .add(const Duration(milliseconds: 1)),
        now,
      ),
      isFalse,
    );
    expect(
      isUpdateCheckDue(now.subtract(const Duration(hours: 24)), now),
      isTrue,
    );
    expect(isUpdateCheckDue(now.add(const Duration(seconds: 1)), now), isTrue);
  });

  test('notifies only for a newer, installable, undismissed release', () {
    const noUpdate = AppUpdateInfo(
      currentVersion: '2',
      latestVersion: '2',
      releaseUrl: '',
      hasUpdate: false,
      assetNames: ['app.apk'],
    );
    expect(
      shouldNotifyAboutUpdate(noUpdate, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      shouldNotifyAboutUpdate(release, platform: TargetPlatform.iOS),
      isFalse,
    );
    expect(
      shouldNotifyAboutUpdate(
        release,
        platform: TargetPlatform.android,
        dismissedVersion: 'v2.0.0',
      ),
      isFalse,
    );
    expect(
      shouldNotifyAboutUpdate(
        release,
        platform: TargetPlatform.android,
        dismissedVersion: 'v1.0.0',
      ),
      isTrue,
    );
  });

  testWidgets('banner displays release and calls each action', (tester) async {
    var opened = false;
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateBanner(
            latestVersion: 'v2.0.0',
            currentVersion: '1.0.0',
            onOpen: () => opened = true,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    expect(find.text('新しいバージョン v2.0.0 があります（現在 1.0.0）'), findsOneWidget);
    expect(find.text('リリースページを開く'), findsOneWidget);
    expect(find.text('閉じる'), findsOneWidget);
    await tester.tap(find.text('リリースページを開く'));
    await tester.tap(find.text('閉じる'));
    expect(opened, isTrue);
    expect(dismissed, isTrue);
  });

  group('automatic update notice', () {
    final baseline = DateTime(2026, 1, 10, 10);
    late DateTime now;
    late Directory directory;
    late _WidgetPrefsStore prefs;
    late _ReleaseFeed feed;
    const plugin = MethodChannel('io.jns.webview.win');
    const view = MethodChannel('io.jns.webview.win/73');
    const events = EventChannel('io.jns.webview.win/73/events');
    const notifications = MethodChannel(
      'net.yoshida.morebettergakujo/notifications',
    );
    const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
    const window = MethodChannel('net.yoshida.morebettergakujo/window');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() async {
      now = baseline;
      directory = await Directory.systemTemp.createTemp('update-notice-');
      prefs = _WidgetPrefsStore(directory);
      feed = _ReleaseFeed();
      FlutterSecureStorage.setMockInitialValues({
        'more_better_gakujo_setup_completed': 'true',
      });
      PackageInfo.setMockInitialValues(
        appName: 'Test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      messenger.setMockMethodCallHandler(
        plugin,
        (call) async => call.method == 'initialize' ? {'textureId': 73} : null,
      );
      messenger.setMockMethodCallHandler(notifications, (_) async => null);
      messenger.setMockMethodCallHandler(
        downloads,
        (_) async => {'isConfigured': false},
      );
      messenger.setMockMethodCallHandler(window, (_) async => null);
      messenger.setMockMethodCallHandler(
        paths,
        (_) async => throw MissingPluginException(),
      );
      messenger.setMockMethodCallHandler(view, (call) async {
        if (call.method == 'addScriptToExecuteOnDocumentCreated') return 'id';
        return call.method == 'executeScript' ? '{}' : null;
      });
    });
    tearDown(() async {
      for (final channel in [
        plugin,
        view,
        notifications,
        downloads,
        window,
        paths,
      ]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      messenger.setMockStreamHandler(events, null);
      FlutterSecureStorage.setMockInitialValues({});
      await directory.delete(recursive: true);
    });

    Future<void> start(WidgetTester tester) async {
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GakujoWebApp(
            localPrefsStore: prefs,
            updateService: AppUpdateService(httpClientFactory: () => feed),
            updateNow: () => now,
          ),
        ),
      );
      await prefs.settle(tester);
      expect(find.byType(Texture), findsOneWidget);
    }

    Future<void> tick(WidgetTester tester) async {
      await tester.pump(const Duration(minutes: 5));
      await prefs.settle(tester);
    }

    Finder banner(String tag) => find.text('新しいバージョン $tag があります（現在 1.0.0）');

    for (final fromDisk in [false, true]) {
      testWidgets(
        'clock rollback after ${fromDisk ? "cached preferences" : "a successful check"}',
        (tester) async {
          if (fromDisk) {
            await tester.runAsync(() => prefs.saveUpdateCheck(checkedAt: now));
            now = baseline.add(const Duration(hours: 1));
          }
          await start(tester);
          final initialRequests = fromDisk ? 0 : 1;
          expect(feed.requests, initialRequests);
          expect(
            (await tester.runAsync(prefs.load))!.lastUpdateCheckAt,
            baseline,
          );
          // Jitter that stays on or after the original persisted anchor is not due.
          now = baseline;
          await tick(tester);
          expect(feed.requests, initialRequests);

          final corrected = baseline.subtract(const Duration(days: 2));
          now = corrected;
          feed.tag = 'v2.0.0';
          await tick(tester);
          expect(feed.requests, initialRequests + 1);
          expect(banner('v2.0.0'), findsOneWidget);
          // Offering a release leaves the old, future timestamp on disk.
          expect(
            (await tester.runAsync(prefs.load))!.lastUpdateCheckAt,
            baseline,
          );
          now = corrected.add(const Duration(minutes: 5));
          await tick(tester);
          now = corrected
              .add(appUpdateCheckInterval)
              .subtract(const Duration(milliseconds: 1));
          await tick(tester);
          expect(feed.requests, initialRequests + 1);
          now = corrected.add(appUpdateCheckInterval);
          await tick(tester);
          expect(feed.requests, initialRequests + 2);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    for (final nextTag in ['v2.0.0', 'v3.0.0']) {
      testWidgets('dismiss v2 while the $nextTag response body is pending', (
        tester,
      ) async {
        feed.tag = 'v2.0.0';
        await start(tester);
        expect(banner('v2.0.0'), findsOneWidget);
        now = baseline.add(appUpdateCheckInterval);
        feed.tag = nextTag;
        final body = feed.holdBody = Completer<void>();
        await tick(tester);
        expect(feed.requests, 2);
        expect(feed.bodiesStarted, 2);
        expect(banner('v2.0.0'), findsOneWidget);
        final dismissedAt = now = now.add(const Duration(minutes: 1));
        await tester.tap(find.widgetWithText(TextButton, '閉じる'));
        await prefs.settle(tester);
        expect(find.byType(AppUpdateBanner), findsNothing);
        final saved = (await tester.runAsync(prefs.load))!;
        expect(saved.dismissedUpdateVersion, 'v2.0.0');
        expect(saved.lastUpdateCheckAt, dismissedAt);

        body.complete();
        await prefs.settle(tester);
        final expected = nextTag == 'v2.0.0' ? findsNothing : findsOneWidget;
        expect(banner(nextTag), expected);
        now = now.add(const Duration(minutes: 5));
        await tick(tester);
        expect(banner(nextTag), expected);
        expect(feed.requests, 2);
        final after = (await tester.runAsync(prefs.load))!;
        expect(after.dismissedUpdateVersion, 'v2.0.0');
        expect(after.lastUpdateCheckAt, dismissedAt);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }

    Future<Completer<void>> startRecheck(
      WidgetTester tester,
      String tag,
    ) async {
      feed.tag = 'v2.0.0';
      await start(tester);
      expect(banner('v2.0.0'), findsOneWidget);
      now = baseline.add(appUpdateCheckInterval);
      feed.tag = tag;
      final body = feed.holdBody = Completer<void>();
      await tick(tester);
      expect(feed.bodiesStarted, 2);
      return body;
    }

    final closeButton = find.widgetWithText(TextButton, '閉じる');
    for (final nextTag in ['v2.0.0', 'v3.0.0']) {
      testWidgets(
        'pointer up on painted v2 dismisses v2 after $nextTag arrives',
        (tester) async {
          final body = await startRecheck(tester, nextTag);
          final press = await tester.startGesture(
            tester.getCenter(closeButton),
          );
          body.complete();
          await tester
              .idle(); // Deliver the body without repainting the button.
          expect(banner('v2.0.0'), findsOneWidget);
          expect(banner('v3.0.0'), findsNothing);
          await press.up();
          await prefs.settle(tester);

          final saved = (await tester.runAsync(prefs.load))!;
          expect(saved.dismissedUpdateVersion, 'v2.0.0');
          expect(saved.lastUpdateCheckAt, now);
          expect(banner('v2.0.0'), findsNothing);
          expect(
            banner('v3.0.0'),
            nextTag == 'v3.0.0' ? findsOneWidget : findsNothing,
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets(
      'repeat tap on painted v2 preserves its first dismissal and the v3 offer',
      (tester) async {
        final body = await startRecheck(tester, 'v3.0.0');
        final dismissedAt = now;
        await tester.tap(closeButton);
        final firstSave = (await tester.runAsync(prefs.load))!;
        expect(firstSave.dismissedUpdateVersion, 'v2.0.0');
        expect(firstSave.lastUpdateCheckAt, dismissedAt);

        body.complete();
        await tester.idle();
        now = now.add(const Duration(seconds: 1));
        expect(banner('v2.0.0'), findsOneWidget);
        expect(banner('v3.0.0'), findsNothing);
        await tester.tap(closeButton);
        await prefs.settle(tester);
        final after = (await tester.runAsync(prefs.load))!;
        expect(after.dismissedUpdateVersion, 'v2.0.0');
        expect(after.lastUpdateCheckAt, dismissedAt);
        expect(banner('v3.0.0'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('tap after v3 is painted dismisses v3', (tester) async {
      final body = await startRecheck(tester, 'v3.0.0');
      body.complete();
      await prefs.settle(tester);
      expect(banner('v3.0.0'), findsOneWidget);
      await tester.tap(closeButton);
      await prefs.settle(tester);
      expect(find.byType(AppUpdateBanner), findsNothing);
      expect(
        (await tester.runAsync(prefs.load))!.dismissedUpdateVersion,
        'v3.0.0',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }, skip: !Platform.isWindows);
}

// The widget clock drives timers. Disk reads, writes and atomic renames use
// the outer test zone so the widget can explicitly await each queued operation.
class _WidgetPrefsStore extends GakujoLocalPrefsStore {
  _WidgetPrefsStore(Directory directory) : super(directory: directory);
  final _io = Zone.current;
  Future<void>? _pending;

  Future<T> _track<T>(Future<T> Function() operation) {
    final future = _io.run(operation);
    _pending = future;
    return future;
  }

  @override
  Future<GakujoLocalPrefs?> load() => _track(super.load);

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) =>
      _track(() => super.saveAppSettings(settings));

  @override
  Future<void> saveUpdateCheck({
    DateTime? checkedAt,
    String? dismissedVersion,
  }) => _track(
    () => super.saveUpdateCheck(
      checkedAt: checkedAt,
      dismissedVersion: dismissedVersion,
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    while (_pending != null) {
      final operation = _pending!;
      _pending = null;
      await tester.runAsync(() => operation);
      await tester.pumpAndSettle();
    }
  }
}

class _ReleaseFeed extends Fake implements HttpClient {
  String tag = 'v1.0.0';
  int requests = 0;
  int bodiesStarted = 0;
  Completer<void>? holdBody;

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    final selected = tag;
    final hold = holdBody;
    Stream<List<int>> body() async* {
      bodiesStarted++;
      yield utf8.encode('{"tag_name":');
      if (hold != null) await hold.future;
      yield utf8.encode(
        '${jsonEncode(selected)},"assets":[{"name":"app.exe"}]}',
      );
    }

    return _ReleaseRequest(_ReleaseResponse(body()));
  }

  @override
  void close({bool force = false}) {}
}

class _ReleaseRequest extends Fake implements HttpClientRequest {
  _ReleaseRequest(this.response);
  final HttpClientResponse response;
  @override
  final HttpHeaders headers = _ReleaseHeaders();
  @override
  Future<HttpClientResponse> close() async => response;
}

class _ReleaseHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _ReleaseResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _ReleaseResponse(super.stream);
  @override
  int get statusCode => HttpStatus.ok;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
