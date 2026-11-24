import 'dart:convert';

enum GakujoReportInitialSort {
  deadline('期限切れ・提出状態・締切（既定）'),
  original('学務の元の順'),
  title('タイトル'),
  courseNumber('開講番号');

  const GakujoReportInitialSort(this.label);
  final String label;
  static GakujoReportInitialSort fromJson(Object? value) =>
      values.firstWhere((sort) => sort.name == value, orElse: () => deadline);
}

class GakujoAutoBackupSettings {
  const GakujoAutoBackupSettings({
    this.intervalHours = 6,
    this.generations = 10,
  });
  static const intervals = [1, 6, 12, 24];
  static const generationCounts = [10, 30, 100];
  final int intervalHours;
  final int generations;
  Duration get interval => Duration(hours: intervalHours);
  GakujoAutoBackupSettings copyWith({int? intervalHours, int? generations}) =>
      GakujoAutoBackupSettings(
        intervalHours: intervalHours ?? this.intervalHours,
        generations: generations ?? this.generations,
      );
  Map<String, Object> toJson() => {
    'intervalHours': intervalHours,
    'generations': generations,
  };
  factory GakujoAutoBackupSettings.fromJson(Object? raw) {
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        raw = null;
      }
    }
    if (raw is! Map) return const GakujoAutoBackupSettings();
    return GakujoAutoBackupSettings(
      intervalHours:
          raw['intervalHours'] is int &&
              intervals.contains(raw['intervalHours'])
          ? raw['intervalHours'] as int
          : 6,
      generations:
          raw['generations'] is int &&
              generationCounts.contains(raw['generations'])
          ? raw['generations'] as int
          : 10,
    );
  }
}
