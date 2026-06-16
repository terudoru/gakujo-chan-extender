import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage_factory.dart';

enum DownloadSaveMode {
  autoSortToConfiguredFolder,
  flatToConfiguredFolder,
  flatWithPickerEachTime,
}

extension DownloadSaveModeLabels on DownloadSaveMode {
  String get label {
    return switch (this) {
      DownloadSaveMode.autoSortToConfiguredFolder => '自動仕分け+指定場所保存',
      DownloadSaveMode.flatToConfiguredFolder => '自動仕分けなし+指定場所保存',
      DownloadSaveMode.flatWithPickerEachTime => '自動仕分けなし+適宜保存場所指定',
    };
  }

  String get storageValue {
    return switch (this) {
      DownloadSaveMode.autoSortToConfiguredFolder => 'auto_sort_configured',
      DownloadSaveMode.flatToConfiguredFolder => 'flat_configured',
      DownloadSaveMode.flatWithPickerEachTime => 'flat_picker_each_time',
    };
  }

  bool get needsConfiguredRoot {
    return switch (this) {
      DownloadSaveMode.autoSortToConfiguredFolder ||
      DownloadSaveMode.flatToConfiguredFolder =>
        true,
      DownloadSaveMode.flatWithPickerEachTime => false,
    };
  }

  bool get autoSortByCourse {
    return this == DownloadSaveMode.autoSortToConfiguredFolder;
  }

  static DownloadSaveMode fromStorageValue(String? value) {
    return DownloadSaveMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => DownloadSaveMode.autoSortToConfiguredFolder,
    );
  }
}

enum GakujoPageMode {
  mobile,
  desktop,
}

extension GakujoPageModeLabels on GakujoPageMode {
  String get label {
    return switch (this) {
      GakujoPageMode.mobile => 'モバイル版',
      GakujoPageMode.desktop => 'デスクトップ版',
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoPageMode.mobile => 'mobile',
      GakujoPageMode.desktop => 'desktop',
    };
  }

  String get startUrl {
    return switch (this) {
      GakujoPageMode.mobile =>
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do',
      GakujoPageMode.desktop =>
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    };
  }

  static GakujoPageMode fromStorageValue(String? value) {
    return GakujoPageMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => GakujoPageMode.mobile,
    );
  }
}

class GakujoAppSettings {
  const GakujoAppSettings({
    this.downloadSaveMode = DownloadSaveMode.autoSortToConfiguredFolder,
    this.pageMode = GakujoPageMode.mobile,
    this.loginCredentials,
  });

  final DownloadSaveMode downloadSaveMode;
  final GakujoPageMode pageMode;
  final GakujoLoginCredentials? loginCredentials;

  bool get hasLoginCredentials => loginCredentials?.isComplete ?? false;

  GakujoAppSettings copyWith({
    DownloadSaveMode? downloadSaveMode,
    GakujoPageMode? pageMode,
    Object? loginCredentials = _unchanged,
  }) {
    return GakujoAppSettings(
      downloadSaveMode: downloadSaveMode ?? this.downloadSaveMode,
      pageMode: pageMode ?? this.pageMode,
      loginCredentials: loginCredentials == _unchanged
          ? this.loginCredentials
          : loginCredentials as GakujoLoginCredentials?,
    );
  }
}

class GakujoLoginCredentials {
  const GakujoLoginCredentials({
    required this.loginId,
    required this.password,
  });

  final String loginId;
  final String password;

  bool get isComplete => loginId.trim().isNotEmpty && password.isNotEmpty;
}

const _unchanged = Object();

class GakujoAppSettingsStore {
  GakujoAppSettingsStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageFactory.create();

  static const _downloadSaveModeKey = 'more_better_gakujo_download_save_mode';
  static const _pageModeKey = 'more_better_gakujo_page_mode';
  static const _loginIdKey = 'more_better_gakujo_login_id';
  static const _loginPasswordKey = 'more_better_gakujo_login_password';

  final FlutterSecureStorage _secureStorage;

  Future<GakujoAppSettings> load() async {
    final values = await Future.wait([
      _secureStorage.read(key: _downloadSaveModeKey),
      _secureStorage.read(key: _pageModeKey),
      _secureStorage.read(key: _loginIdKey),
      _secureStorage.read(key: _loginPasswordKey),
    ]);
    final loginId = values[2]?.trim() ?? '';
    final password = values[3] ?? '';
    return GakujoAppSettings(
      downloadSaveMode: DownloadSaveModeLabels.fromStorageValue(values[0]),
      pageMode: GakujoPageModeLabels.fromStorageValue(values[1]),
      loginCredentials: loginId.isNotEmpty && password.isNotEmpty
          ? GakujoLoginCredentials(loginId: loginId, password: password)
          : null,
    );
  }

  Future<void> saveDownloadSaveMode(DownloadSaveMode mode) {
    return _secureStorage.write(
      key: _downloadSaveModeKey,
      value: mode.storageValue,
    );
  }

  Future<void> savePageMode(GakujoPageMode mode) {
    return _secureStorage.write(
      key: _pageModeKey,
      value: mode.storageValue,
    );
  }

  Future<void> saveLoginCredentials({
    required String loginId,
    required String password,
  }) async {
    final trimmedLoginId = loginId.trim();
    if (trimmedLoginId.isEmpty || password.isEmpty) {
      await clearLoginCredentials();
      return;
    }

    await Future.wait([
      _secureStorage.write(key: _loginIdKey, value: trimmedLoginId),
      _secureStorage.write(key: _loginPasswordKey, value: password),
    ]);
  }

  Future<void> clearLoginCredentials() {
    return Future.wait([
      _secureStorage.delete(key: _loginIdKey),
      _secureStorage.delete(key: _loginPasswordKey),
    ]);
  }
}
