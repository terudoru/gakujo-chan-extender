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

  for (final gpa in [0.0, 3.25, 5.0]) {
    test('saveLastGpa round-trips $gpa', () async {
      await store.saveLastGpa(gpa);

      final loaded = await GakujoLocalPrefsStore(directory: directory).load();
      expect(loaded?.lastGpa, gpa);
      expect(loaded?.lastGpa, isA<double>());
    });
  }

  test('saveAppSettings preserves last GPA', () async {
    await store.saveLastGpa(3.25);

    await store.saveAppSettings(const GakujoAppSettings(
      pageMode: GakujoPageMode.mobile,
    ));

    final loaded = await store.load();
    expect(loaded?.lastGpa, 3.25);
    expect(loaded?.appSettings?.pageMode, GakujoPageMode.mobile);
  });

  test('saveLastPageUrl preserves last GPA', () async {
    const lastPageUrl = 'https://example.com';
    await store.saveLastGpa(3.25);

    await store.saveLastPageUrl(lastPageUrl);

    final loaded = await store.load();
    expect(loaded?.lastGpa, 3.25);
    expect(loaded?.lastPageUrl, lastPageUrl);
  });

  test('saveLastGpa preserves settings and last page URL', () async {
    const lastPageUrl = 'https://example.com';
    await store.saveAppSettings(const GakujoAppSettings(
      pageMode: GakujoPageMode.mobile,
      setupCompleted: true,
      messageExcludeKeywords: ['survey'],
    ));
    await store.saveLastPageUrl(lastPageUrl);
    await store.saveLastGpa(2.5);

    await store.saveLastGpa(3.25);

    final loaded = await store.load();
    expect(loaded?.lastGpa, 3.25);
    expect(loaded?.appSettings?.pageMode, GakujoPageMode.mobile);
    expect(loaded?.appSettings?.setupCompleted, isTrue);
    expect(loaded?.appSettings?.messageExcludeKeywords, ['survey']);
    expect(loaded?.lastPageUrl, lastPageUrl);
  });

  test('saveLastGpa preserves partial settings keys', () async {
    await File('${directory.path}/${GakujoLocalPrefsStore.fileName}')
        .writeAsString('{"version":1,"pageMode":"mobile"}');

    await store.saveLastGpa(3.25);
    await store.saveLastPageUrl('https://example.com');

    final loaded = await store.load();
    expect(loaded?.lastGpa, 3.25);
    expect(loaded?.appSettingsKeys, {'pageMode'});
    final raw = jsonDecode(await File(
      '${directory.path}/${GakujoLocalPrefsStore.fileName}',
    ).readAsString()) as Map;
    expect(raw.keys,
        unorderedEquals(['version', 'pageMode', 'lastPageUrl', 'lastGpa']));
  });

  test('saveLastGpa clears GPA without changing settings or last page URL',
      () async {
    const lastPageUrl = 'https://example.com';
    await store.saveAppSettings(const GakujoAppSettings(
      pageMode: GakujoPageMode.mobile,
    ));
    await store.saveLastPageUrl(lastPageUrl);
    await store.saveLastGpa(3.25);

    await store.saveLastGpa(null);

    final loaded = await store.load();
    expect(loaded?.lastGpa, isNull);
    expect(loaded?.appSettings?.pageMode, GakujoPageMode.mobile);
    expect(loaded?.lastPageUrl, lastPageUrl);
    final raw = jsonDecode(await File(
      '${directory.path}/${GakujoLocalPrefsStore.fileName}',
    ).readAsString()) as Map;
    expect(raw.containsKey('lastGpa'), isFalse);
  });

  for (final invalidGpa in ['3.25', -1, 9]) {
    test('decodes invalid stored GPA ${jsonEncode(invalidGpa)} as null',
        () async {
      await File('${directory.path}/${GakujoLocalPrefsStore.fileName}')
          .writeAsString(jsonEncode({'lastGpa': invalidGpa}));

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded?.lastGpa, isNull);
    });
  }

  test('a GPA-only file has no app settings', () async {
    await File('${directory.path}/${GakujoLocalPrefsStore.fileName}')
        .writeAsString('{"lastGpa":3}');

    final loaded = await store.load();
    expect(loaded?.lastGpa, 3.0);
    expect(loaded?.lastGpa, isA<double>());
    expect(loaded?.appSettings, isNull);
    expect(loaded?.appSettingsKeys, isEmpty);
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

  test('failed atomic replace preserves the previous mirror file', () async {
    const oldUrl = 'https://gakujo.iess.niigata-u.ac.jp/old';
    const newUrl = 'https://gakujo.iess.niigata-u.ac.jp/new';
    await store.saveAppSettings(const GakujoAppSettings(
      pageMode: GakujoPageMode.mobile,
      setupCompleted: true,
    ));
    await store.saveLastPageUrl(oldUrl);
    final failingStore = GakujoLocalPrefsStore(
      directory: directory,
      atomicReplace: (temporaryFile, targetFile) async {
        expect(await temporaryFile.exists(), isTrue);
        expect(await targetFile.exists(), isTrue);
        throw const FileSystemException('atomic replace failed');
      },
    );

    await expectLater(
      failingStore.saveLastPageUrl(newUrl),
      throwsA(isA<FileSystemException>()),
    );

    final loaded = await GakujoLocalPrefsStore(directory: directory).load();
    expect(loaded?.lastPageUrl, oldUrl);
    expect(loaded?.appSettings?.pageMode, GakujoPageMode.mobile);
    expect(loaded?.appSettings?.setupCompleted, isTrue);
    expect(
      await directory
          .list()
          .where((entry) => entry.path.endsWith('.tmp'))
          .toList(),
      isEmpty,
    );
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

  test('setup and local mirror exclude untouched startup placeholders',
      () async {
    final startup = macosStartupSettingsFromLocalPrefs(null);
    final settings = gakujoSettingsForPersistence(
      startup.copyWith(setupCompleted: true),
      placeholderFeatureFlags: startup.disabledFeatureFlags,
    );

    expect(settings.disabledFeatureFlags, isEmpty);
    expect(settings.setupCompleted, isTrue);
    await store.saveAppSettings(settings);
    expect((await store.load())!.appSettings!.disabledFeatureFlags, isEmpty);
    expect(startup.disabledFeatureFlags, {
      GakujoFeatureFlag.loginAutofill,
      GakujoFeatureFlag.twoFactorAutofill,
    });
  });

  test('setup preserves flags already disabled in local preferences', () {
    const localSettings = GakujoAppSettings(
      disabledFeatureFlags: {
        GakujoFeatureFlag.loginAutofill,
        GakujoFeatureFlag.gpaDisplay,
      },
    );
    final startup = macosStartupSettingsFromLocalPrefs(
      const GakujoLocalPrefs(appSettings: localSettings),
    );
    final settings = gakujoSettingsForPersistence(
      startup,
      placeholderFeatureFlags: startup.disabledFeatureFlags
          .difference(localSettings.disabledFeatureFlags),
    );

    expect(settings.disabledFeatureFlags, localSettings.disabledFeatureFlags);
  });

  for (final flag in [
    GakujoFeatureFlag.loginAutofill,
    GakujoFeatureFlag.twoFactorAutofill,
  ]) {
    test('setup persists $flag explicitly toggled back off', () {
      final startup = macosStartupSettingsFromLocalPrefs(null);
      final settings = gakujoSettingsForPersistence(
        startup,
        placeholderFeatureFlags: startup.disabledFeatureFlags,
        changedFeatureFlags: {flag},
      );

      expect(settings.disabledFeatureFlags, {flag});
    });

    test('setup keeps $flag explicitly toggled on enabled', () {
      final startup = macosStartupSettingsFromLocalPrefs(null);
      final settings = gakujoSettingsForPersistence(
        startup.copyWith(
          disabledFeatureFlags: startup.disabledFeatureFlags.difference({flag}),
        ),
        placeholderFeatureFlags: startup.disabledFeatureFlags,
        changedFeatureFlags: {flag},
      );

      expect(settings.disabledFeatureFlags, isEmpty);
    });
  }

  test('real secure settings retain disabled flags after placeholders clear',
      () {
    const settings = GakujoAppSettings(
      disabledFeatureFlags: {
        GakujoFeatureFlag.loginAutofill,
        GakujoFeatureFlag.twoFactorAutofill,
      },
    );

    expect(
      gakujoSettingsForPersistence(settings, placeholderFeatureFlags: {})
          .disabledFeatureFlags,
      settings.disabledFeatureFlags,
    );
  });

  test('macOS keeps local filters when secure credentials become available',
      () {
    const localPrefs = GakujoLocalPrefs(
      appSettings: GakujoAppSettings(
        pageMode: GakujoPageMode.mobile,
        disabledFeatureFlags: {
          GakujoFeatureFlag.gpaDisplay,
          GakujoFeatureFlag.loginAutofill,
        },
        messageExcludeKeywords: ['アンケート'],
      ),
    );
    const secureSettings = GakujoAppSettings(
      loginCredentials: GakujoLoginCredentials(
        loginId: 'student',
        password: 'password',
      ),
      disabledFeatureFlags: {GakujoFeatureFlag.twoFactorAutofill},
      messageExcludeKeywords: ['古い設定'],
    );

    final merged = mergeMacosLocalMessageFiltersWithSecureSettings(
      secureSettings: secureSettings,
      localPrefs: localPrefs,
    );

    expect(merged.pageMode, secureSettings.pageMode);
    expect(merged.messageExcludeKeywords, ['アンケート']);
    expect(merged.loginCredentials?.loginId, 'student');
    expect(merged.disabledFeatureFlags, secureSettings.disabledFeatureFlags);
  });

  test('macOS falls back to secure settings when no local mirror exists', () {
    const secureSettings = GakujoAppSettings(
      pageMode: GakujoPageMode.mobile,
      messageExcludeKeywords: ['アンケート'],
    );

    final merged = mergeMacosLocalMessageFiltersWithSecureSettings(
      secureSettings: secureSettings,
      localPrefs: null,
    );

    expect(identical(merged, secureSettings), isTrue);
  });

  test('partial local JSON preserves missing secure filters and choices',
      () async {
    await File('${directory.path}/${GakujoLocalPrefsStore.fileName}')
        .writeAsString('{"version":1,"pageMode":"mobile"}');
    // Updating navigation must not fill missing settings with default values.
    await store.saveLastPageUrl('https://example.com');
    final local = await store.load();
    const secure = GakujoAppSettings(
      messageExcludeKeywords: ['広告'],
      notificationTopics: {GakujoNotificationTopic.other},
      messageNotification: GakujoMessageNotificationSettings(
        mode: GakujoMessageNotificationMode.deadlines,
      ),
      notificationPreferences: GakujoNotificationPreferences(
        skipSubmitted: false,
        mutedCourses: {'科目'},
        reminderOffsets: {GakujoReminderOffset.threeDays},
      ),
    );
    final merged = mergeMacosLocalMessageFiltersWithSecureSettings(
      secureSettings: secure,
      localPrefs: local,
    );
    expect(merged.messageExcludeKeywords, secure.messageExcludeKeywords);
    expect(merged.notificationTopics, secure.notificationTopics);
    expect(merged.messageNotification.toJson(),
        secure.messageNotification.toJson());
    expect(merged.notificationPreferences.toJson(),
        secure.notificationPreferences.toJson());
    final raw = jsonDecode(await File(
      '${directory.path}/${GakujoLocalPrefsStore.fileName}',
    ).readAsString()) as Map;
    expect(raw.keys, unorderedEquals(['version', 'pageMode', 'lastPageUrl']));
  });

  test('present empty filters override secure values without resetting choices',
      () async {
    await File('${directory.path}/${GakujoLocalPrefsStore.fileName}')
        .writeAsString('{"version":1,"messageExcludeKeywords":[]}');
    const preferences = GakujoNotificationPreferences(mutedCourses: {'科目'});
    final merged = mergeMacosLocalMessageFiltersWithSecureSettings(
      secureSettings: const GakujoAppSettings(
        messageExcludeKeywords: ['広告'],
        notificationPreferences: preferences,
      ),
      localPrefs: await store.load(),
    );
    expect(merged.messageExcludeKeywords, isEmpty);
    expect(merged.notificationPreferences.toJson(), preferences.toJson());
  });

  test('present local topics preserve a missing secure message rule', () async {
    await File('${directory.path}/${GakujoLocalPrefsStore.fileName}')
        .writeAsString(
            '{"version":1,"notificationTopics":["message","report"]}');
    final local = await store.load();
    const messages = GakujoMessageNotificationSettings(
      mode: GakujoMessageNotificationMode.keywords,
      keywords: ['授業'],
    );
    final merged = mergeMacosLocalMessageFiltersWithSecureSettings(
      secureSettings: const GakujoAppSettings(
        messageExcludeKeywords: ['広告'],
        messageNotification: messages,
      ),
      localPrefs: local,
    );
    expect(local!.appSettings!.messageNotification.mode,
        GakujoMessageNotificationMode.deadlines);
    expect(merged.messageNotification.toJson(), messages.toJson());
    expect(merged.notificationTopics, {GakujoNotificationTopic.coursework});
    expect(merged.messageExcludeKeywords, ['広告']);
  });
}
