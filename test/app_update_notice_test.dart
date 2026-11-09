import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/app_update_service.dart';
import 'package:morebettergakujo_flutter/src/widgets/app_update_banner.dart';

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
}
