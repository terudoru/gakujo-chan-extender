import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'gakujo_app_settings.dart';

class GakujoLocalPrefs {
  const GakujoLocalPrefs({
    this.appSettings,
    this.lastPageUrl,
  });

  final GakujoAppSettings? appSettings;
  final String? lastPageUrl;
}

class GakujoLocalPrefsStore {
  GakujoLocalPrefsStore({Directory? directory}) : _directory = directory;

  static const fileName = 'local_prefs.json';

  final Directory? _directory;
  Future<void> _pendingWrite = Future<void>.value();

  Future<GakujoLocalPrefs?> load() async {
    await _pendingWrite;
    return _read();
  }

  Future<void> saveAppSettings(GakujoAppSettings settings) {
    return _enqueueUpdate((current) {
      return GakujoLocalPrefs(
        appSettings: settings.copyWith(loginCredentials: null),
        lastPageUrl: current?.lastPageUrl,
      );
    });
  }

  Future<void> saveLastPageUrl(String? url) {
    return _enqueueUpdate((current) {
      return GakujoLocalPrefs(
        appSettings: current?.appSettings,
        lastPageUrl: url,
      );
    });
  }

  Future<void> clear() {
    return _enqueue(() async {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  Future<void> _enqueueUpdate(
    GakujoLocalPrefs Function(GakujoLocalPrefs? current) update,
  ) {
    return _enqueue(() async {
      final current = await _read();
      await _write(update(current));
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _pendingWrite.then((_) => operation());
    _pendingWrite = next.catchError((Object _) {});
    return next;
  }

  Future<GakujoLocalPrefs?> _read() async {
    final file = await _file();
    if (!await file.exists()) {
      return null;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return _decodePrefs(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(GakujoLocalPrefs prefs) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_encodePrefs(prefs)), flush: true);
  }

  Future<File> _file() async {
    final directory = _directory ?? await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  static Map<String, Object?> _encodePrefs(GakujoLocalPrefs prefs) {
    final settings = prefs.appSettings;
    return {
      'version': 1,
      if (settings != null) ...{
        'downloadSaveMode': settings.downloadSaveMode.storageValue,
        'pageMode': settings.pageMode.storageValue,
        'disabledFeatureFlags': settings.disabledFeatureFlags
            .map((flag) => flag.storageValue)
            .toList(),
        'setupCompleted': settings.setupCompleted,
        'calendarImportSettings': settings.calendarImportSettings.toJson(),
        'messageExcludeKeywords':
            normalizeMessageExcludeKeywords(settings.messageExcludeKeywords),
      },
      if (prefs.lastPageUrl != null) 'lastPageUrl': prefs.lastPageUrl,
    };
  }

  static GakujoLocalPrefs _decodePrefs(Map<String, dynamic> raw) {
    const settingsKeys = {
      'downloadSaveMode',
      'pageMode',
      'disabledFeatureFlags',
      'setupCompleted',
      'calendarImportSettings',
      'messageExcludeKeywords',
    };
    final hasSettings = settingsKeys.any(raw.containsKey);
    final disabledFeatureFlags = switch (raw['disabledFeatureFlags']) {
      final List<dynamic> values => values
          .map((value) => GakujoFeatureFlagLabels.fromStorageValue(
                value.toString(),
              ))
          .whereType<GakujoFeatureFlag>()
          .toSet(),
      _ => <GakujoFeatureFlag>{},
    };
    final messageExcludeKeywords = switch (raw['messageExcludeKeywords']) {
      final List<dynamic> values => normalizeMessageExcludeKeywords(
          values.map((value) => value.toString()),
        ),
      _ => const <String>[],
    };
    return GakujoLocalPrefs(
      appSettings: hasSettings
          ? GakujoAppSettings(
              downloadSaveMode: DownloadSaveModeLabels.fromStorageValue(
                raw['downloadSaveMode']?.toString(),
              ),
              pageMode: GakujoPageModeLabels.fromStorageValue(
                raw['pageMode']?.toString(),
              ),
              disabledFeatureFlags: disabledFeatureFlags,
              setupCompleted: raw['setupCompleted'] == true,
              calendarImportSettings: GakujoCalendarImportSettings.fromJson(
                raw['calendarImportSettings'],
              ),
              messageExcludeKeywords: messageExcludeKeywords,
            )
          : null,
      lastPageUrl:
          raw['lastPageUrl'] is String ? raw['lastPageUrl'] as String : null,
    );
  }
}

GakujoAppSettings macosStartupSettingsFromLocalPrefs(
  GakujoLocalPrefs? prefs,
) {
  final settings = prefs?.appSettings ?? const GakujoAppSettings();
  return settings.copyWith(
    loginCredentials: null,
    disabledFeatureFlags: {
      ...settings.disabledFeatureFlags,
      GakujoFeatureFlag.loginAutofill,
      GakujoFeatureFlag.twoFactorAutofill,
    },
  );
}
