import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  });

  final DownloadSaveMode downloadSaveMode;
  final GakujoPageMode pageMode;

  GakujoAppSettings copyWith({
    DownloadSaveMode? downloadSaveMode,
    GakujoPageMode? pageMode,
  }) {
    return GakujoAppSettings(
      downloadSaveMode: downloadSaveMode ?? this.downloadSaveMode,
      pageMode: pageMode ?? this.pageMode,
    );
  }
}

class GakujoAppSettingsStore {
  GakujoAppSettingsStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _downloadSaveModeKey = 'more_better_gakujo_download_save_mode';
  static const _pageModeKey = 'more_better_gakujo_page_mode';

  final FlutterSecureStorage _secureStorage;

  Future<GakujoAppSettings> load() async {
    final values = await Future.wait([
      _secureStorage.read(key: _downloadSaveModeKey),
      _secureStorage.read(key: _pageModeKey),
    ]);
    return GakujoAppSettings(
      downloadSaveMode: DownloadSaveModeLabels.fromStorageValue(values[0]),
      pageMode: GakujoPageModeLabels.fromStorageValue(values[1]),
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
}
