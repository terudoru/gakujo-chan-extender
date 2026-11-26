import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_restore.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_start_url_resolver.dart';
import 'package:morebettergakujo_flutter/src/gakujo_quick_jump_destination.dart';
import 'package:morebettergakujo_flutter/src/desktop_page_zoom_script.dart';
import 'package:morebettergakujo_flutter/src/widgets/settings_sections.dart';

import 'support/preference_backup_fixture.dart';

void main() {
  test('defaults preserve startup 100 percent and previous page; unknown and missing fields fall back', () async {
    for (final raw in [
      null,
      'invalid',
      {},
      {
        'startup': 'unknown',
        'fixedPercent': -1,
        'stepPercent': 13,
        'lastPercent': 999,
      },
      {'fixedPercent': '150', 'stepPercent': 10.0, 'lastPercent': double.nan},
    ]) {
      final zoom = GakujoDesktopZoomSettings.fromJson(raw);
      expect(zoom.toJson(), const GakujoDesktopZoomSettings().toJson());
      expect(zoom.startupZoom, 1);
    }
    final storage = PreferenceBackupStorage();
    var loaded = await GakujoAppSettingsStore(secureStorage: storage).load();
    expect(loaded.startupPage, GakujoStartupPage.previous);
    expect(loaded.desktopZoomSettings.startupZoom, 1);
    storage.values['more_better_gakujo_startup_page'] = 'unknown';
    storage.values['more_better_gakujo_desktop_zoom_settings'] = 'broken';
    loaded = await GakujoAppSettingsStore(secureStorage: storage).load();
    expect(loaded.startupPage, GakujoStartupPage.previous);
    expect(
      loaded.desktopZoomSettings.toJson(),
      const GakujoDesktopZoomSettings().toJson(),
    );
    for (final raw in [
      {'version': 2},
      {'version': 2, 'startupPage': 'new-version', 'desktopZoomSettings': []},
    ]) {
      final backup = parseGakujoBackup(jsonEncode(raw));
      expect(backup.startupPage, GakujoStartupPage.previous);
      expect(
        backup.desktopZoomSettings!.toJson(),
        const GakujoDesktopZoomSettings().toJson(),
      );
    }
  });

  test(
    'settings and local startup mirror persist all startup preferences',
    () async {
      final storage = PreferenceBackupStorage();
      final store = GakujoAppSettingsStore(secureStorage: storage);
      const zoom = GakujoDesktopZoomSettings(
        startup: GakujoStartupZoom.previous,
        fixedPercent: 135,
        stepPercent: 25,
        lastPercent: 175,
      );
      await store.saveDesktopZoomSettings(zoom);
      await store.saveStartupPage(GakujoStartupPage.messages);
      final loaded = await GakujoAppSettingsStore(secureStorage: storage)
          .load();
      expect(loaded.desktopZoomSettings.toJson(), zoom.toJson());
      expect(loaded.startupPage, GakujoStartupPage.messages);
      final directory = await Directory.systemTemp.createTemp(
        'startup-preferences',
      );
      try {
        final mirror = GakujoLocalPrefsStore(directory: directory);
        await mirror.saveAppSettings(loaded);
        final local = await mirror.load();
        final mac = macosStartupSettingsFromLocalPrefs(local);
        expect(mac.desktopZoomSettings.toJson(), zoom.toJson());
        expect(mac.startupPage, loaded.startupPage);
        final merged = mergeMacosLocalMessageFiltersWithSecureSettings(
          secureSettings: const GakujoAppSettings(),
          localPrefs: local,
        );
        expect(merged.desktopZoomSettings.toJson(), zoom.toJson());
        expect(merged.startupPage, loaded.startupPage);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'export parse and transactional restore round trip both preferences',
    () async {
      const settings = GakujoAppSettings(
        startupPage: GakujoStartupPage.reports,
        desktopZoomSettings: GakujoDesktopZoomSettings(
          startup: GakujoStartupZoom.previous,
          fixedPercent: 80,
          stepPercent: 5,
          lastPercent: 160,
        ),
      );
      final backup = parseGakujoBackup(
        encodeGakujoBackupPayload(buildPreferenceBackupPayload(settings)),
      );
      final storage = PreferenceBackupStorage();
      final store = GakujoAppSettingsStore(secureStorage: storage);
      Future<void> restore() => restoreGakujoBackup(
        backup: backup,
        settingsStore: store,
        historyStore: GakujoDownloadHistoryStore(secureStorage: storage),
        activityStore: GakujoActivityStore(secureStorage: storage),
        isAllowedUrl: (_) => true,
        isAllowedNavigationUrl: (_) => true,
      );
      await restore();
      final loaded = await store.load();
      expect(
        loaded.desktopZoomSettings.toJson(),
        settings.desktopZoomSettings.toJson(),
      );
      expect(loaded.startupPage, settings.startupPage);
      await store.saveStartupPage(GakujoStartupPage.home);
      await store.saveDesktopZoomSettings(const GakujoDesktopZoomSettings());
      final before = {...storage.values};
      storage.failOnce = 'more_better_gakujo_desktop_zoom_settings';
      await expectLater(restore(), throwsStateError);
      expect(storage.values, before);
    },
  );

  test('startup zoom modes, each step and continuous gestures obey settings and bounds', () {
    for (final step in GakujoDesktopZoomSettings.steps) {
      final zoom = GakujoDesktopZoomSettings(
        stepPercent: step,
        fixedPercent: 125,
        lastPercent: 150,
      );
      expect(zoom.startupZoom, 1.25);
      expect(
        zoom.copyWith(startup: GakujoStartupZoom.previous).startupZoom,
        1.5,
      );
      expect(zoom.changeBy(1, 1), 1 + step / 100);
      expect(zoom.changeBy(1, -1), 1 - step / 100);
      expect(zoom.changeBy(1.99, 1), 2);
      expect(zoom.changeBy(.51, -1), .5);
      expect(
        GakujoDesktopZoomSettings.clamp(
          desktopWheelZoom(2, -100, stepPercent: step),
        ),
        2,
      );
      expect(GakujoDesktopZoomSettings.clamp(.5 * zoom.pinchFactor(.2)), .5);
    }
    expect(
      desktopWheelZoom(1, -100, stepPercent: 5),
      lessThan(desktopWheelZoom(1, -100)),
    );
    expect(
      desktopWheelZoom(1, -100, stepPercent: 25),
      greaterThan(desktopWheelZoom(1, -100)),
    );
    expect(const GakujoDesktopZoomSettings().pinchFactor(1.2), 1.2);
    expect(
      const GakujoDesktopZoomSettings(stepPercent: 25).pinchFactor(1.2),
      greaterThan(1.2),
    );
  });

  test('startup pages reuse destinations; invalid previous falls back home and notification wins', () {
    const saved = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/student.do';
    const home = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do';
    final expected = {
      GakujoStartupPage.previous: saved,
      GakujoStartupPage.home: home,
      GakujoStartupPage.reports: GakujoQuickJumpDestination.reports.portalUrl,
      GakujoStartupPage.messages: GakujoQuickJumpDestination.messages.portalUrl,
    };
    for (final page in GakujoStartupPage.values) {
      expect(
        GakujoStartUrlResolver.resolve(
          debugAllowed: false,
          startupPage: page,
          savedUrl: saved,
          fallbackUrl: home,
        ),
        expected[page],
      );
      expect(
        GakujoStartUrlResolver.resolve(
          debugAllowed: false,
          startupPage: page,
          savedUrl: saved,
          fallbackUrl: home,
          notificationUrl: saved,
        ),
        saved,
      );
    }
    expect(
      GakujoStartUrlResolver.resolve(
        debugAllowed: false,
        savedUrl: 'https://example.test',
        fallbackUrl: home,
      ),
      home,
    );
    expect(
      GakujoStartUrlResolver.resolve(
        debugAllowed: false,
        notificationUrl: 'https://example.test',
        startupPage: GakujoStartupPage.messages,
      ),
      GakujoQuickJumpDestination.messages.portalUrl,
    );
  });

  testWidgets(
    'startup sections expose all supported choices and save selected values',
    (tester) async {
      var zoom = const GakujoDesktopZoomSettings();
      var page = GakujoStartupPage.previous;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (_, setState) => Column(
                  children: [
                    GakujoStartupPageSection(
                      page: page,
                      onChanged: (value) => setState(() => page = value!),
                    ),
                    GakujoDesktopZoomSection(
                      settings: zoom,
                      onStartupChanged: (value) =>
                          setState(() => zoom = zoom.copyWith(startup: value)),
                      onFixedPercentChanged: (value) => setState(
                        () => zoom = zoom.copyWith(fixedPercent: value),
                      ),
                      onStepChanged: (value) => setState(
                        () => zoom = zoom.copyWith(stepPercent: value),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('連絡通知'));
      await tester.pumpAndSettle();
      expect(page, GakujoStartupPage.messages);
      await tester.ensureVisible(find.text('25%'));
      await tester.tap(find.text('25%'));
      await tester.pumpAndSettle();
      expect(zoom.stepPercent, 25);
      await tester.ensureVisible(find.text('前回の倍率を引き継ぐ'));
      await tester.tap(find.text('前回の倍率を引き継ぐ'));
      await tester.pumpAndSettle();
      expect(zoom.startup, GakujoStartupZoom.previous);
    },
  );
}
