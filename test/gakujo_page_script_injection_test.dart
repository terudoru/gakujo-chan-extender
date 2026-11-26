import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_expired_page_recovery_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_gpa_display_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_message_filter_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_timeout_popup_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

class _LocalPrefs extends GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

class _Settings extends GakujoAppSettingsStore {
  _Settings(this.settings);

  final GakujoAppSettings settings;

  @override
  Future<GakujoAppSettings> load() async => settings;
}

void main() {
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
  const windowsPlugin = MethodChannel('io.jns.webview.win');
  const windowsView = MethodChannel('io.jns.webview.win/73');
  const windowsEvents = EventChannel('io.jns.webview.win/73/events');

  testWidgets(
    'leaf scripts honor the document and isolate a controller failure',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        storage,
        (call) async => call.method == 'readAll'
            ? <String, String>{}
            : call.method == 'containsKey'
            ? false
            : null,
      );
      messenger.setMockMethodCallHandler(
        paths,
        (_) async => throw MissingPluginException('No filesystem in fixture'),
      );
      messenger.setMockMethodCallHandler(downloads, (call) async {
        if (call.method == 'getDownloadRoot') return {'isConfigured': false};
        throw MissingPluginException();
      });
      messenger.setMockMethodCallHandler(
        windowsPlugin,
        (call) async => call.method == 'initialize' ? {'textureId': 73} : null,
      );
      addTearDown(() {
        for (final channel in [
          storage,
          paths,
          downloads,
          windowsPlugin,
          windowsView,
        ]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        messenger.setMockStreamHandler(windowsEvents, null);
      });

      final scripts = <String>[];
      final leafScripts = {
        GakujoExpiredPageRecoveryScript.build(): 'recovery',
        GakujoTimeoutPopupScript.buildWithLoginObserver(): 'timeout',
        GakujoGpaDisplayScript.build(): 'gpa',
        GakujoMessageFilterScript.build(keywords: const []): 'filter',
      };
      final holdRecovery = Completer<void>();
      var failRecovery = false;
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        windowsEvents,
        MockStreamHandler.inline(
          onListen: (_, events) {
            sink = events;
          },
        ),
      );
      messenger.setMockMethodCallHandler(windowsView, (call) async {
        if (call.method == 'addScriptToExecuteOnDocumentCreated') return 'id';
        if (call.method != 'executeScript') return null;
        if (call.arguments == gakujoPortalAuthStateProbeScript) {
          return jsonEncode({'hasAuthenticatedMarker': true});
        }
        final script = leafScripts[call.arguments];
        if (script != null) scripts.add(script);
        if (script == 'recovery') {
          await holdRecovery.future;
          if (failRecovery) throw PlatformException(code: 'synthetic_failure');
        }
        return jsonEncode('');
      });

      Future<void> start(String url) async {
        sink.success({'type': 'navigationStarting', 'value': url});
        await tester.idle();
        sink.success({'type': 'urlChanged', 'value': url});
        await tester.idle();
        sink.success({
          'type': 'loadingStateChanged',
          'value': windows.LoadingState.loading.index,
        });
        await tester.idle();
      }

      Future<void> finish() async {
        sink.success({
          'type': 'loadingStateChanged',
          'value': windows.LoadingState.navigationCompleted.index,
        });
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: GakujoWebApp(
              appSettingsStore: _Settings(
                const GakujoAppSettings(
                  setupCompleted: true,
                  disabledFeatureFlags: {
                    GakujoFeatureFlag.autoBackup,
                    GakujoFeatureFlag.deadlineNotifications,
                    GakujoFeatureFlag.updateNotice,
                  },
                ),
              ),
              localPrefsStore: _LocalPrefs(),
              gakujoReachable: () async => false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await start('about:blank');
        await finish();
        expect(scripts, isEmpty);

        await start(gakujoHomePortalUrl);
        await finish();
        expect(scripts, ['recovery']);

        // The old finish no longer owns the document even at the same URL.
        await start(gakujoHomePortalUrl);
        holdRecovery.complete();
        await tester.pumpAndSettle();
        expect(scripts, ['recovery']);

        failRecovery = true;
        await finish();
        expect(scripts, ['recovery', 'recovery', 'timeout', 'gpa', 'filter']);
        expect(tester.takeException(), isNull);
      } finally {
        if (!holdRecovery.isCompleted) holdRecovery.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
    skip: !Platform.isWindows,
  );
}
