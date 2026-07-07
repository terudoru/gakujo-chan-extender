import 'package:flutter/services.dart';

import 'gakujo_calendar_export.dart';

class GakujoCalendarSyncResult {
  const GakujoCalendarSyncResult({
    required this.added,
    required this.removed,
    required this.openedFallback,
  });

  final int added;
  final int removed;
  final bool openedFallback;

  factory GakujoCalendarSyncResult.fromJson(Map<dynamic, dynamic> json) {
    return GakujoCalendarSyncResult(
      added: int.tryParse(json['added']?.toString() ?? '') ?? 0,
      removed: int.tryParse(json['removed']?.toString() ?? '') ?? 0,
      openedFallback: json['openedFallback'] == true,
    );
  }
}

class GakujoCalendarDeleteResult {
  const GakujoCalendarDeleteResult({required this.removed});

  final int removed;

  factory GakujoCalendarDeleteResult.fromJson(Map<dynamic, dynamic> json) {
    return GakujoCalendarDeleteResult(
      removed: int.tryParse(json['removed']?.toString() ?? '') ?? 0,
    );
  }
}

class GakujoCalendarEvent {
  const GakujoCalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location = '',
    this.teacher = '',
    this.notes = '',
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final String teacher;
  final String notes;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'startMillis': _tokyoWallClockMillis(start),
      'endMillis': _tokyoWallClockMillis(end),
      'location': location,
      'teacher': teacher,
      'notes': notes,
    };
  }

  static int _tokyoWallClockMillis(DateTime value) {
    if (value.isUtc) {
      return value.millisecondsSinceEpoch;
    }
    return DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour - 9,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    ).millisecondsSinceEpoch;
  }
}

abstract class GakujoCalendarService {
  const GakujoCalendarService();

  bool get supportsDirectSync;

  Future<GakujoCalendarSyncResult> syncEvents({
    required List<GakujoCalendarEvent> events,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? calendarTitle,
  });

  Future<GakujoCalendarDeleteResult> deleteAddedEvents({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? calendarTitle,
  });
}

class MethodChannelGakujoCalendarService extends GakujoCalendarService {
  const MethodChannelGakujoCalendarService();

  static const _channel = MethodChannel(
    'net.yoshida.morebettergakujo/calendar',
  );

  @override
  bool get supportsDirectSync => true;

  @override
  Future<GakujoCalendarSyncResult> syncEvents({
    required List<GakujoCalendarEvent> events,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? calendarTitle,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'syncEvents',
      {
        'calendarTitle': calendarTitle ?? 'More Better Gakujo 授業',
        'rangeStartMillis': DateTime(
          rangeStart.year,
          rangeStart.month,
          rangeStart.day,
        ).millisecondsSinceEpoch,
        'rangeEndMillis': DateTime(
          rangeEnd.year,
          rangeEnd.month,
          rangeEnd.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch,
        'events': events.map((event) => event.toJson()).toList(),
      },
    );
    return GakujoCalendarSyncResult.fromJson(result ?? const {});
  }

  @override
  Future<GakujoCalendarDeleteResult> deleteAddedEvents({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? calendarTitle,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'deleteAddedEvents',
      {
        if (calendarTitle != null) 'calendarTitle': calendarTitle,
        'rangeStartMillis': DateTime(
          rangeStart.year,
          rangeStart.month,
          rangeStart.day,
        ).millisecondsSinceEpoch,
        'rangeEndMillis': DateTime(
          rangeEnd.year,
          rangeEnd.month,
          rangeEnd.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch,
      },
    );
    return GakujoCalendarDeleteResult.fromJson(result ?? const {});
  }
}

class UnsupportedGakujoCalendarService extends GakujoCalendarService {
  const UnsupportedGakujoCalendarService();

  @override
  bool get supportsDirectSync => false;

  @override
  Future<GakujoCalendarSyncResult> syncEvents({
    required List<GakujoCalendarEvent> events,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? calendarTitle,
  }) {
    throw MissingPluginException(
      'OSカレンダー直接連携はこのプラットフォームでは未対応です',
    );
  }

  @override
  Future<GakujoCalendarDeleteResult> deleteAddedEvents({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? calendarTitle,
  }) {
    throw MissingPluginException(
      'OSカレンダー直接連携はこのプラットフォームでは未対応です',
    );
  }
}

class GakujoCalendarEventBuilder {
  const GakujoCalendarEventBuilder._();

  static List<GakujoCalendarEvent> buildEvents({
    required List<GakujoCalendarCourse> courses,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    List<DateTime> noClassDates = const [],
    String uidNamespace = 'manual',
    String termLabel = '',
  }) {
    final noClassKeys = noClassDates
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet();
    final events = <GakujoCalendarEvent>[];
    for (final course in courses) {
      final time = GakujoCalendarExport.periodTimes[course.period];
      if (time == null ||
          course.title.trim().isEmpty ||
          course.weekday < DateTime.monday ||
          course.weekday > DateTime.sunday) {
        continue;
      }
      var date = _firstDateOnOrAfter(rangeStart, course.weekday);
      while (!date.isAfter(rangeEnd)) {
        final dayKey = DateTime(date.year, date.month, date.day);
        if (!noClassKeys.contains(dayKey)) {
          final start = DateTime(
            date.year,
            date.month,
            date.day,
            time.startHour,
            time.startMinute,
          );
          final end = DateTime(
            date.year,
            date.month,
            date.day,
            time.endHour,
            time.endMinute,
          );
          events.add(
            GakujoCalendarEvent(
              id: _eventInstanceId(course, uidNamespace, start),
              title: GakujoCalendarExport.displayTitleForCourse(course),
              start: start,
              end: end,
              location: GakujoCalendarExport.displayLocationForCourse(course),
              teacher: course.teacher.trim(),
              notes: GakujoCalendarExport.descriptionForCourse(
                course: course,
                periodTime: time,
                termLabel: termLabel,
              ),
            ),
          );
        }
        date = date.add(const Duration(days: DateTime.daysPerWeek));
      }
    }
    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  static DateTime _firstDateOnOrAfter(DateTime start, int weekday) {
    final date = DateTime(start.year, start.month, start.day);
    final delta = (weekday - date.weekday) % DateTime.daysPerWeek;
    return date.add(Duration(days: delta));
  }

  static String _eventInstanceId(
    GakujoCalendarCourse course,
    String uidNamespace,
    DateTime start,
  ) {
    String normalize(String value) {
      return value.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    final tokyoStart = start.toUtc().add(const Duration(hours: 9));
    return [
      uidNamespace,
      normalize(GakujoCalendarExport.displayTitleForCourse(course)),
      course.weekday,
      course.period,
      normalize(GakujoCalendarExport.displayLocationForCourse(course)),
      tokyoStart.year,
      tokyoStart.month.toString().padLeft(2, '0'),
      tokyoStart.day.toString().padLeft(2, '0'),
    ].join('|');
  }
}
