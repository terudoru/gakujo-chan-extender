import 'package:flutter/services.dart';

import 'gakujo_academic_calendar.dart';
import 'gakujo_calendar_export.dart';

int _tokyoDateBoundaryMillis(
  DateTime value, {
  int hour = 0,
  int minute = 0,
  int second = 0,
}) {
  return DateTime.utc(
    value.year,
    value.month,
    value.day,
    hour - 9,
    minute,
    second,
  ).millisecondsSinceEpoch;
}

DateTime _calendarDateAfterDays(DateTime value, int days) {
  return DateTime(value.year, value.month, value.day + days);
}

String _calendarEventNamespace(List<GakujoCalendarEvent> events) {
  String? namespace;
  for (final event in events) {
    final separator = event.id.indexOf('|');
    if (separator <= 0) {
      throw ArgumentError.value(
        event.id,
        'events',
        'カレンダー予定IDに同期範囲の識別子がありません',
      );
    }
    final candidate = event.id.substring(0, separator);
    if (namespace != null && namespace != candidate) {
      throw ArgumentError.value(
        events,
        'events',
        '異なる同期範囲のカレンダー予定を同時に追加できません',
      );
    }
    namespace = candidate;
  }
  return namespace!;
}

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
    if (events.isEmpty) {
      throw ArgumentError.value(events, 'events', '同期対象のカレンダー予定がありません');
    }
    final uidNamespace = _calendarEventNamespace(events);
    final result = await _channel.invokeMapMethod<String, Object?>(
      'syncEvents',
      {
        'calendarTitle': calendarTitle ?? 'More Better Gakujo 授業',
        'uidNamespace': uidNamespace,
        'rangeStartMillis': _tokyoDateBoundaryMillis(rangeStart),
        'rangeEndMillis': _tokyoDateBoundaryMillis(
          _calendarDateAfterDays(rangeEnd, 1),
        ),
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
        'rangeStartMillis': _tokyoDateBoundaryMillis(rangeStart),
        'rangeEndMillis': _tokyoDateBoundaryMillis(
          _calendarDateAfterDays(rangeEnd, 1),
        ),
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
    List<GakujoClassDaySwap> classDaySwaps = const [],
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
      final excludedKeys = <DateTime>{
        if (course.recursWeekly) ...noClassKeys,
        ...course.excludedDates.map(
          (date) => DateTime(date.year, date.month, date.day),
        ),
      };

      void addEvent(DateTime date) {
        final dayKey = DateTime(date.year, date.month, date.day);
        if (!excludedKeys.contains(dayKey)) {
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
      }

      if (!course.recursWeekly) {
        final sourceDate = course.sourceDate;
        if (sourceDate != null) {
          final date = DateTime(
            sourceDate.year,
            sourceDate.month,
            sourceDate.day,
          );
          if (!date.isBefore(rangeStart) && !date.isAfter(rangeEnd)) {
            addEvent(date);
          }
        }
        continue;
      }

      // Walk every day so that a 授業振替日 runs the timetable of the swapped
      // weekday instead of its own.
      for (var date =
              DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
          !date.isAfter(rangeEnd);
          date = _calendarDateAfterDays(date, 1)) {
        if (GakujoCalendarExport.timetableWeekdayFor(date, classDaySwaps) ==
            course.weekday) {
          addEvent(date);
        }
      }
    }
    // Gakujo also lists the meetings of a weekly class one by one; when the
    // weekly series is not cut on that date (no-class days not applied), the
    // same meeting would otherwise appear twice.
    final seen = <String>{};
    final unique = [
      for (final event in events)
        if (seen.add('${event.start.toIso8601String()}|${event.title}')) event,
    ];
    unique.sort((a, b) => a.start.compareTo(b.start));
    return unique;
  }

  static String _eventInstanceId(
    GakujoCalendarCourse course,
    String uidNamespace,
    DateTime start,
  ) {
    String normalize(String value) {
      return value.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    final normalizedCourseCode =
        GakujoCalendarExport.courseCodeFromText(course.courseCode);
    final stableCourseIdentity = normalizedCourseCode.isNotEmpty
        ? normalizedCourseCode
        : normalize(GakujoCalendarExport.displayTitleForCourse(course));
    return [
      uidNamespace,
      stableCourseIdentity,
      course.weekday,
      course.period,
      normalize(GakujoCalendarExport.displayLocationForCourse(course)),
      start.year,
      start.month.toString().padLeft(2, '0'),
      start.day.toString().padLeft(2, '0'),
    ].join('|');
  }
}
