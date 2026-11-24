import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

class _LocalPrefs extends GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;
  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

class _ViewPreferencesStore extends GakujoAppSettingsStore {
  _ViewPreferencesStore(this.settings);
  GakujoAppSettings settings;
  @override
  Future<GakujoAppSettings> load() async => settings;
  @override
  Future<void> saveDesktopZoomSettings(GakujoDesktopZoomSettings value) async {
    settings = settings.copyWith(desktopZoomSettings: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const window = MethodChannel('net.yoshida.morebettergakujo/window');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
  const notifications = MethodChannel(
    'net.yoshida.morebettergakujo/notifications',
  );
  const windowsPlugin = MethodChannel('io.jns.webview.win');
  const windowsView = MethodChannel('io.jns.webview.win/73');
  const windowsEvents = EventChannel('io.jns.webview.win/73/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(
      storage,
      (call) async => call.method == 'readAll'
          ? <String, String>{}
          : call.method == 'containsKey'
          ? false
          : null,
    );
    messenger.setMockMethodCallHandler(
      window,
      (call) async => call.method == 'secretServiceStatus' ? 'running' : null,
    );
    messenger.setMockMethodCallHandler(
      paths,
      (_) async =>
          throw MissingPluginException('No filesystem in startup fixture'),
    );
    messenger.setMockMethodCallHandler(downloads, (call) async {
      if (call.method == 'getDownloadRoot') return {'isConfigured': false};
      throw MissingPluginException();
    });
    messenger.setMockMethodCallHandler(
      windowsPlugin,
      (call) async => call.method == 'initialize' ? {'textureId': 73} : null,
    );
    messenger.setMockStreamHandler(
      windowsEvents,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
  });
  tearDown(() {
    for (final channel in [
      storage,
      window,
      paths,
      downloads,
      notifications,
      windowsPlugin,
      windowsView,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockStreamHandler(windowsEvents, null);
  });
  testWidgets(
    'startup page and zoom preferences apply to the real toolbar and keyboard',
    (tester) async {
      final visited = <String>[];
      messenger.setMockMethodCallHandler(windowsView, (call) async {
        if (call.method == 'loadUrl') visited.add(call.arguments as String);
        return null;
      });
      for (final mode in GakujoStartupZoom.values) {
        String? notificationTarget = mode == GakujoStartupZoom.previous
            ? GakujoQuickJumpDestination.reports.portalUrl
            : null;
        final expectedUrl =
            notificationTarget ?? GakujoQuickJumpDestination.messages.portalUrl;
        messenger.setMockMethodCallHandler(notifications, (call) async {
          if (call.method == 'takePendingNotificationUrl') {
            final result = notificationTarget;
            notificationTarget = null;
            return result;
          }
          throw MissingPluginException();
        });
        final store = _ViewPreferencesStore(
          GakujoAppSettings(
            setupCompleted: true,
            startupPage: GakujoStartupPage.messages,
            disabledFeatureFlags: const {
              GakujoFeatureFlag.autoBackup,
              GakujoFeatureFlag.deadlineNotifications,
            },
            desktopZoomSettings: GakujoDesktopZoomSettings(
              startup: mode,
              fixedPercent: 125,
              lastPercent: 150,
              stepPercent: 25,
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: GakujoWebApp(
              appSettingsStore: store,
              localPrefsStore: _LocalPrefs(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final initial = mode == GakujoStartupZoom.fixed ? 125 : 150;
        expect(find.text('$initial%'), findsOneWidget);
        expect(visited.last, expectedUrl);
        if (mode == GakujoStartupZoom.fixed) {
          await tester.tap(find.byTooltip('設定'));
          await tester.pumpAndSettle();
          final section = find.text('学務情報システムの画面');
          for (
            var frame = 0;
            frame < 20 && section.evaluate().isEmpty;
            frame++
          ) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(
            section,
            findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((text) => text.data)
                .join('|'),
          );
          await tester.ensureVisible(section);
          await tester.pumpAndSettle();
          await tester.tap(section);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('前回の倍率を引き継ぐ'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('前回の倍率を引き継ぐ'));
          await tester.pumpAndSettle();
          expect(
            store.settings.desktopZoomSettings.startup,
            GakujoStartupZoom.previous,
          );
          expect(store.settings.desktopZoomSettings.lastPercent, initial);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('拡大'));
        await tester.pumpAndSettle();
        expect(find.text('${initial + 25}%'), findsOneWidget);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.text('$initial%'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(store.settings.desktopZoomSettings.lastPercent, initial);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
    skip: !Platform.isWindows,
  );
}
