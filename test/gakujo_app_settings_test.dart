import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
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
}

class _TrackingSecureStorage extends FlutterSecureStorage {
  _TrackingSecureStorage(this.values);

  final Map<String, String> values;
  Object? readAllError;
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
    final error = readAllError;
    if (error != null) {
      throw error;
    }
    return Map<String, String>.from(values);
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
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
