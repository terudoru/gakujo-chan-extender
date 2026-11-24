import 'dart:convert';
import 'dart:math' as math;

enum GakujoStartupPage {
  previous('前回のページ'),
  home('学務のHOME'),
  reports('課題一覧'),
  messages('連絡通知');

  const GakujoStartupPage(this.label);
  final String label;
  static GakujoStartupPage fromJson(Object? value) =>
      values.firstWhere((page) => page.name == value, orElse: () => previous);
}

enum GakujoStartupZoom { previous, fixed }

class GakujoDesktopZoomSettings {
  const GakujoDesktopZoomSettings({
    this.startup = GakujoStartupZoom.fixed,
    this.fixedPercent = 100,
    this.stepPercent = 10,
    this.lastPercent = 100,
  });
  static const minimum = 0.5;
  static const maximum = 2.0;
  static const steps = [5, 10, 25];
  final GakujoStartupZoom startup;
  final int fixedPercent;
  final int stepPercent;
  final double lastPercent;
  double get step => stepPercent / 100;
  double get startupZoom => clamp(
    (startup == GakujoStartupZoom.previous ? lastPercent : fixedPercent) / 100,
  );
  static double clamp(double value) =>
      value.isFinite ? value.clamp(minimum, maximum).toDouble() : 1;
  double changeBy(double current, int direction) =>
      clamp(((current * 1000).round() + direction * stepPercent * 10) / 1000);
  double pinchFactor(double scale) => scale.isFinite && scale > 0
      ? math.pow(scale, stepPercent / 10).toDouble()
      : 1;
  GakujoDesktopZoomSettings copyWith({
    GakujoStartupZoom? startup,
    int? fixedPercent,
    int? stepPercent,
    double? lastPercent,
  }) => GakujoDesktopZoomSettings(
    startup: startup ?? this.startup,
    fixedPercent: fixedPercent ?? this.fixedPercent,
    stepPercent: stepPercent ?? this.stepPercent,
    lastPercent: lastPercent ?? this.lastPercent,
  );
  Map<String, Object> toJson() => {
    'startup': startup.name,
    'fixedPercent': fixedPercent,
    'stepPercent': stepPercent,
    'lastPercent': lastPercent,
  };
  factory GakujoDesktopZoomSettings.fromJson(Object? raw) {
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        raw = null;
      }
    }
    if (raw is! Map) return const GakujoDesktopZoomSettings();
    final values = raw;
    final fixed = values['fixedPercent'];
    final last = values['lastPercent'];
    return GakujoDesktopZoomSettings(
      startup: GakujoStartupZoom.values.firstWhere(
        (value) => value.name == values['startup'],
        orElse: () => GakujoStartupZoom.fixed,
      ),
      fixedPercent: fixed is int && fixed >= 50 && fixed <= 200 ? fixed : 100,
      stepPercent:
          values['stepPercent'] is int && steps.contains(values['stepPercent'])
          ? values['stepPercent'] as int
          : 10,
      lastPercent: last is num && last.isFinite && last >= 50 && last <= 200
          ? last.toDouble()
          : 100,
    );
  }
}
