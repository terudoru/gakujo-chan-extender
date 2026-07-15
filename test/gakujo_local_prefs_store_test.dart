import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late GakujoLocalPrefsStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gakujo_local_prefs_');
    store = GakujoLocalPrefsStore(directory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('round-trips non-sensitive settings and last page URL', () async {
    const lastPageUrl =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do';
    const settings = GakujoAppSettings(
      downloadSaveMode: DownloadSaveMode.flatWithPickerEachTime,
      pageMode: GakujoPageMode.mobile,
      loginCredentials: GakujoLoginCredentials(
        loginId: 'student',
        password: 'secret-password',
      ),
      disabledFeatureFlags: {
        GakujoFeatureFlag.gpaDisplay,
        GakujoFeatureFlag.reportTools,
      },
      setupCompleted: true,
      calendarImportSettings: GakujoCalendarImportSettings(
        method: GakujoCalendarImportMethod.icsFile,
        termSource: GakujoCalendarTermSource.pageOrManual,
        termTarget: GakujoCalendarTermTarget.third,
        includeNoClassDates: false,
        calendarTitle: '工学部授業',
      ),
      messageExcludeKeywords: [' アンケート ', '説明会'],
    );

    await store.saveAppSettings(settings);
    await store.saveLastPageUrl(lastPageUrl);

    final loaded = await store.load();
    final loadedSettings = loaded?.appSettings;
    expect(loadedSettings?.downloadSaveMode,
        DownloadSaveMode.flatWithPickerEachTime);
    expect(loadedSettings?.pageMode, GakujoPageMode.mobile);
    expect(loadedSettings?.loginCredentials, isNull);
    expect(
      loadedSettings?.disabledFeatureFlags,
      {GakujoFeatureFlag.gpaDisplay, GakujoFeatureFlag.reportTools},
    );
    expect(loadedSettings?.setupCompleted, isTrue);
    expect(
      loadedSettings?.calendarImportSettings.method,
      GakujoCalendarImportMethod.icsFile,
    );
    expect(
      loadedSettings?.calendarImportSettings.termTarget,
      GakujoCalendarTermTarget.third,
    );
    expect(loadedSettings?.messageExcludeKeywords, ['アンケート', '説明会']);
    expect(loaded?.lastPageUrl, lastPageUrl);

    final json = jsonDecode(
      await File(
        '${directory.path}${Platform.pathSeparator}'
        '${GakujoLocalPrefsStore.fileName}',
      ).readAsString(),
    ) as Map<String, dynamic>;
    expect(json.containsKey('loginCredentials'), isFalse);
    expect(json.containsKey('loginId'), isFalse);
    expect(json.containsKey('password'), isFalse);
    expect(jsonEncode(json), isNot(contains('secret-password')));
  });

  test('returns null when the mirror file is missing', () async {
    expect(await store.load(), isNull);
  });

  test('returns null when the mirror file contains broken JSON', () async {
    await File(
      '${directory.path}${Platform.pathSeparator}'
      '${GakujoLocalPrefsStore.fileName}',
    ).writeAsString('{broken');

    expect(await store.load(), isNull);
  });

  test('macOS startup settings restore display state without secrets', () {
    const prefs = GakujoLocalPrefs(
      appSettings: GakujoAppSettings(
        pageMode: GakujoPageMode.mobile,
        loginCredentials: GakujoLoginCredentials(
          loginId: 'student',
          password: 'secret-password',
        ),
        disabledFeatureFlags: {GakujoFeatureFlag.gpaDisplay},
        setupCompleted: true,
      ),
    );

    final settings = macosStartupSettingsFromLocalPrefs(prefs);

    expect(settings.pageMode, GakujoPageMode.mobile);
    expect(settings.setupCompleted, isTrue);
    expect(settings.loginCredentials, isNull);
    expect(
      settings.disabledFeatureFlags,
      containsAll({
        GakujoFeatureFlag.gpaDisplay,
        GakujoFeatureFlag.loginAutofill,
        GakujoFeatureFlag.twoFactorAutofill,
      }),
    );
  });
}
