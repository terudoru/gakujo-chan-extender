import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_adapters.dart';

void main() {
  test('portable settings compare against the current snapshot', () {
    final settings = GakujoAppSettings();
    final snapshot = exportStarSyncPortableSettings(settings);
    expect(portableSyncSettingsMatch(settings, snapshot), isTrue);
    expect(
      portableSyncSettingsMatch(settings, {
        ...snapshot,
        'messageExcludeKeywords': ['changed'],
      }),
      isFalse,
    );
  });

  test('sync backup removes local settings and nested credentials', () {
    final payload = <String, Object?>{
      'version': 2,
      'downloadSaveMode': 'local',
      'pageMode': 'local',
      'disabledFeatureFlags': [
        GakujoFeatureFlag.messageStars.storageValue,
        'other',
      ],
      'nested': {
        'password': 'hidden',
        'accessToken': 'hidden',
        'safe': 'kept',
      },
    };
    final portable = portableSyncBackupPayload(payload);
    expect(portable, isNot(contains('downloadSaveMode')));
    expect(portable, isNot(contains('pageMode')));
    expect(portable['disabledFeatureFlags'], ['other']);
    expect(portable['nested'], {'safe': 'kept'});
    expect(payload['downloadSaveMode'], 'local');
  });
}
