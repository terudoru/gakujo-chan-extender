import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/migrating_secure_storage.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('message exclude keywords are normalized and persisted', () async {
    final storage = _TrackingSecureStorage({});
    final store = GakujoAppSettingsStore(secureStorage: storage);

    await store.saveMessageExcludeKeywords([
      ' アンケート ',
      '',
      'アンケート',
      '集中  講義',
      '集中 講義',
    ]);

    final settings = await store.load();

    expect(settings.messageExcludeKeywords, ['アンケート', '集中 講義']);
  });

  test('message exclude keywords can be loaded from fallback text format',
      () async {
    final storage = _TrackingSecureStorage({
      'more_better_gakujo_message_exclude_keywords': 'アンケート\n説明会,説明会',
    });
    final store = GakujoAppSettingsStore(secureStorage: storage);

    final settings = await store.load();

    expect(settings.messageExcludeKeywords, ['アンケート', '説明会']);
  });

  test('defaults to the desktop portal when no page mode is saved', () async {
    final store = GakujoAppSettingsStore(
      secureStorage: _TrackingSecureStorage({}),
    );

    final settings = await store.load();

    expect(settings.pageMode, GakujoPageMode.desktop);
    expect(
      settings.pageMode.startUrl,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    );
  });

  test('falls back to the desktop portal for invalid saved page modes',
      () async {
    final store = GakujoAppSettingsStore(
      secureStorage: _TrackingSecureStorage({
        'more_better_gakujo_page_mode': 'unknown',
      }),
    );

    final settings = await store.load();

    expect(settings.pageMode, GakujoPageMode.desktop);
  });

  test('calendar import settings persist selected term target', () {
    final settings = GakujoCalendarImportSettings.fromJson({
      'method': 'device_calendar',
      'termSource': 'official',
      'termTarget': 'second',
      'includeNoClassDates': true,
      'calendarTitle': '授業',
    });

    expect(settings.termTarget, GakujoCalendarTermTarget.second);
    expect(settings.toJson()['termTarget'], 'second');
  });

  test('calendar import settings reserve the validation calendar title', () {
    const settings = GakujoCalendarImportSettings(
      calendarTitle: GakujoCalendarImportSettings.validationCalendarTitle,
    );

    expect(
      settings.effectiveCalendarTitle,
      GakujoCalendarImportSettings.defaultCalendarTitle,
    );
  });

  test('calendar import settings round-trip through secure storage', () async {
    final storage = _TrackingSecureStorage({});
    final store = GakujoAppSettingsStore(secureStorage: storage);
    const expected = GakujoCalendarImportSettings(
      method: GakujoCalendarImportMethod.icsFile,
      termSource: GakujoCalendarTermSource.pageOrManual,
      termTarget: GakujoCalendarTermTarget.fourth,
      includeNoClassDates: false,
      calendarTitle: ' 工学部授業 ',
    );

    await store.saveCalendarImportSettings(expected);
    final settings = await GakujoAppSettingsStore(
      secureStorage: storage,
    ).load();

    expect(settings.calendarImportSettings.method, expected.method);
    expect(settings.calendarImportSettings.termSource, expected.termSource);
    expect(settings.calendarImportSettings.termTarget, expected.termTarget);
    expect(settings.calendarImportSettings.includeNoClassDates, isFalse);
    expect(settings.calendarImportSettings.calendarTitle, '工学部授業');
  });

  test('load reads settings with a single readAll call', () async {
    final storage = _TrackingSecureStorage({
      'more_better_gakujo_page_mode': 'desktop',
      'more_better_gakujo_login_id': 'student',
      'more_better_gakujo_login_password': 'secret',
      'more_better_gakujo_setup_completed': 'true',
    });
    final store = GakujoAppSettingsStore(secureStorage: storage);

    final settings = await store.load();

    expect(storage.readAllCount, 1);
    expect(storage.readKeys, isEmpty);
    expect(settings.pageMode, GakujoPageMode.desktop);
    expect(settings.loginCredentials?.loginId, 'student');
    expect(settings.setupCompleted, isTrue);
  });

  test('load falls back to sequential key reads when readAll fails', () async {
    final storage = _TrackingSecureStorage({
      'more_better_gakujo_page_mode': 'desktop',
    })
      ..readAllError = StateError('denied');
    final store = GakujoAppSettingsStore(secureStorage: storage);

    final settings = await store.load();

    expect(storage.readAllCount, 1);
    expect(storage.readKeys.first, 'more_better_gakujo_download_save_mode');
    expect(
        storage.readKeys.last, 'more_better_gakujo_message_exclude_keywords');
    expect(settings.pageMode, GakujoPageMode.desktop);
  });

  test('load reads legacy settings when migrating primary times out', () async {
    final primary = _TrackingSecureStorage({})
      ..readDelay = const Duration(seconds: 4);
    final fallback = _TrackingSecureStorage({
      'more_better_gakujo_page_mode': 'mobile',
      'more_better_gakujo_login_id': 'student',
      'more_better_gakujo_login_password': 'secret',
    });
    final store = GakujoAppSettingsStore(
      secureStorage: MigratingSecureStorage(
        primary: primary,
        fallback: fallback,
      ),
    );

    final settings = await store.load();

    expect(settings.pageMode, GakujoPageMode.mobile);
    expect(settings.loginCredentials?.loginId, 'student');
    expect(settings.loginCredentials?.password, 'secret');
  });

  test('load migrates a complete legacy login pair into one record', () async {
    final storage = _TrackingSecureStorage({
      'more_better_gakujo_login_id': ' student ',
      'more_better_gakujo_login_password': 'old-secret',
    });
    final store = GakujoAppSettingsStore(secureStorage: storage);

    final settings = await store.load();

    expect(settings.loginCredentials?.loginId, 'student');
    expect(settings.loginCredentials?.password, 'old-secret');
    expect(
      storage.values['more_better_gakujo_login_credentials_v2'],
      contains('old-secret'),
    );
    expect(storage.values.containsKey('more_better_gakujo_login_id'), isFalse);
    expect(
      storage.values.containsKey('more_better_gakujo_login_password'),
      isFalse,
    );
  });

  test('failed credential record write preserves the previous complete pair',
      () async {
    final storage = _TrackingSecureStorage({
      'more_better_gakujo_login_id': 'old-student',
      'more_better_gakujo_login_password': 'old-secret',
    })
      ..writeErrorKey = 'more_better_gakujo_login_credentials_v2';
    final store = GakujoAppSettingsStore(secureStorage: storage);

    await expectLater(
      store.saveLoginCredentials(
        loginId: 'new-student',
        password: 'new-secret',
      ),
      throwsA(isA<StateError>()),
    );

    storage.writeErrorKey = null;
    final settings = await store.load();
    expect(settings.loginCredentials?.loginId, 'old-student');
    expect(settings.loginCredentials?.password, 'old-secret');
  });

  test('failed legacy cleanup cannot create mixed login credentials', () async {
    final storage = _TrackingSecureStorage({
      'more_better_gakujo_login_id': 'old-student',
      'more_better_gakujo_login_password': 'old-secret',
    })
      ..deleteErrorKey = 'more_better_gakujo_login_password';
    final store = GakujoAppSettingsStore(secureStorage: storage);

    await store.saveLoginCredentials(
      loginId: 'new-student',
      password: 'new-secret',
    );
    final settings = await store.load();

    expect(settings.loginCredentials?.loginId, 'new-student');
    expect(settings.loginCredentials?.password, 'new-secret');
    expect(
      storage.values['more_better_gakujo_login_password'],
      'old-secret',
    );
  });

  test('credential tombstone keeps a partial legacy delete cleared', () async {
    final storage = _TrackingSecureStorage({
      'more_better_gakujo_login_id': 'old-student',
      'more_better_gakujo_login_password': 'old-secret',
    })
      ..deleteErrorKey = 'more_better_gakujo_login_password';
    final store = GakujoAppSettingsStore(secureStorage: storage);

    await store.clearLoginCredentials();
    final settings = await store.load();

    expect(settings.loginCredentials, isNull);
    expect(
      storage.values['more_better_gakujo_login_password'],
      'old-secret',
    );
    expect(
      storage.values['more_better_gakujo_login_credentials_v2'],
      contains('"cleared":true'),
    );
  });

  test('malformed credential record does not revive a legacy pair', () async {
    final storage = _TrackingSecureStorage({
      'more_better_gakujo_login_credentials_v2': '{broken',
      'more_better_gakujo_login_id': 'old-student',
      'more_better_gakujo_login_password': 'old-secret',
      'more_better_gakujo_calendar_import_settings': '{"termTarget":"third"}',
    });
    final store = GakujoAppSettingsStore(secureStorage: storage);

    final settings = await store.load();

    expect(settings.loginCredentials, isNull);
    expect(
      settings.calendarImportSettings.termTarget,
      GakujoCalendarTermTarget.third,
    );
  });

  test('concurrent feature changes preserve every disabled flag', () async {
    final storage = _TrackingSecureStorage({})
      ..readAllDelay = const Duration(milliseconds: 20);
    final store = GakujoAppSettingsStore(secureStorage: storage);

    await Future.wait([
      store.saveFeatureEnabled(
        GakujoFeatureFlag.gpaDisplay,
        enabled: false,
      ),
      store.saveFeatureEnabled(
        GakujoFeatureFlag.reportTools,
        enabled: false,
      ),
    ]);

    final settings = await store.load();
    expect(
      settings.disabledFeatureFlags,
      containsAll({
        GakujoFeatureFlag.gpaDisplay,
        GakujoFeatureFlag.reportTools,
      }),
    );
  });
}

class _TrackingSecureStorage extends FlutterSecureStorage {
  _TrackingSecureStorage(this.values);

  final Map<String, String> values;
  Object? readAllError;
  String? writeErrorKey;
  String? deleteErrorKey;
  Duration readDelay = Duration.zero;
  Duration readAllDelay = Duration.zero;
  int readAllCount = 0;
  final List<String> readKeys = [];

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readAllCount += 1;
    final snapshot = Map<String, String>.from(values);
    if (readAllDelay > Duration.zero) {
      await Future<void>.delayed(readAllDelay);
    }
    final error = readAllError;
    if (error != null) {
      throw error;
    }
    return snapshot;
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    readKeys.add(key);
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (writeErrorKey == key) {
      throw StateError('write failed for $key');
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (deleteErrorKey == key) {
      throw StateError('delete failed for $key');
    }
    values.remove(key);
  }
}
