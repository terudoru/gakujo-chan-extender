import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_service.dart';

void main() {
  const channel = MethodChannel('net.yoshida.morebettergakujo/calendar');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('deleteAddedEvents asks native side to remove marked events in range',
      () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return {'removed': '7'};
    });

    final result =
        await const MethodChannelGakujoCalendarService().deleteAddedEvents(
      rangeStart: DateTime(2026, 6, 11, 13),
      rangeEnd: DateTime(2026, 8, 5, 1),
      calendarTitle: 'More Better Gakujo 検証',
    );

    expect(result.removed, 7);
    expect(capturedCall?.method, 'deleteAddedEvents');
    expect(
      (capturedCall?.arguments as Map<dynamic, dynamic>)['calendarTitle'],
      'More Better Gakujo 検証',
    );
    expect(
      (capturedCall?.arguments as Map<dynamic, dynamic>)['rangeStartMillis'],
      DateTime(2026, 6, 11).millisecondsSinceEpoch,
    );
    expect(
      (capturedCall?.arguments as Map<dynamic, dynamic>)['rangeEndMillis'],
      DateTime(2026, 8, 5, 23, 59, 59).millisecondsSinceEpoch,
    );
  });

  test('syncEvents can target a validation calendar title', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return {'added': 1, 'removed': 0, 'openedFallback': false};
    });

    final result = await const MethodChannelGakujoCalendarService().syncEvents(
      events: [
        GakujoCalendarEvent(
          id: 'validation-1',
          title: '検証予定',
          start: DateTime(2026, 6, 11, 8, 45),
          end: DateTime(2026, 6, 11, 10, 15),
          location: '検証教室 A',
          teacher: 'More Better Gakujo',
          notes: '木曜 1限\n08:45 - 10:15\n教室: 検証教室 A',
        ),
      ],
      rangeStart: DateTime(2026, 6, 11),
      rangeEnd: DateTime(2026, 6, 11),
      calendarTitle: 'More Better Gakujo 検証',
    );

    expect(result.added, 1);
    expect(capturedCall?.method, 'syncEvents');
    expect(
      (capturedCall?.arguments as Map<dynamic, dynamic>)['calendarTitle'],
      'More Better Gakujo 検証',
    );
    final payload =
        (capturedCall?.arguments as Map<dynamic, dynamic>)['events'] as List;
    final eventJson = payload.single as Map<dynamic, dynamic>;
    expect(eventJson['title'], '検証予定');
    expect(
      eventJson['startMillis'],
      DateTime.utc(2026, 6, 10, 23, 45).millisecondsSinceEpoch,
    );
    expect(
      eventJson['endMillis'],
      DateTime.utc(2026, 6, 11, 1, 15).millisecondsSinceEpoch,
    );
    expect(eventJson['location'], '検証教室 A');
    expect(eventJson['teacher'], 'More Better Gakujo');
    expect(eventJson['notes'], contains('木曜 1限'));
    expect(eventJson['notes'], contains('08:45 - 10:15'));
  });

  test('buildEvents expands classes into concrete event instances', () {
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: const [
        GakujoCalendarCourse(
          title: '日本国憲法',
          weekday: DateTime.monday,
          period: 1,
          location: 'E-260',
          teacher: '山田 太郎',
        ),
      ],
      rangeStart: DateTime(2026, 6, 11),
      rangeEnd: DateTime(2026, 6, 30),
      uidNamespace: 'niigata-2026-第2ターム',
      termLabel: '2026年度 第2ターム',
    );

    expect(events, hasLength(3));
    expect(events.first.title, '日本国憲法');
    expect(events.first.start, DateTime(2026, 6, 15, 8, 45));
    expect(events.first.end, DateTime(2026, 6, 15, 10, 15));
    expect(events.first.location, 'E-260');
    expect(events.first.teacher, '山田 太郎');
    expect(events.first.notes, contains('月曜 1限'));
    expect(events.first.notes, contains('08:45 - 10:15'));
    expect(events.first.notes, contains('教室: E-260'));
    expect(events.first.notes, contains('担当教員: 山田 太郎'));
    expect(events.first.notes, contains('ターム: 2026年度 第2ターム'));
  });

  test('buildEvents serializes lesson times as Asia/Tokyo wall clock', () {
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: const [
        GakujoCalendarCourse(
          title: '日本国憲法',
          weekday: DateTime.monday,
          period: 1,
        ),
      ],
      rangeStart: DateTime(2026, 6, 15),
      rangeEnd: DateTime(2026, 6, 15),
    );

    expect(events.single.start, DateTime(2026, 6, 15, 8, 45));
    expect(events.single.end, DateTime(2026, 6, 15, 10, 15));
    expect(
      events.single.toJson()['startMillis'],
      DateTime.utc(2026, 6, 14, 23, 45).millisecondsSinceEpoch,
    );
  });

  test('buildEvents prefers official Google schedule display fields', () {
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: const [
        GakujoCalendarCourse(
          title: '人工知能入門',
          weekday: DateTime.wednesday,
          period: 4,
          officialTitle: '人工知能入門（Gコード）',
          officialLocation: '工学部 101',
          officialDescription: '学務Google連携の説明',
        ),
      ],
      rangeStart: DateTime(2026, 6, 29),
      rangeEnd: DateTime(2026, 7, 3),
      uidNamespace: 'niigata-2026-第2ターム',
      termLabel: '2026年度 第2ターム',
    );

    expect(events, hasLength(1));
    expect(events.single.title, '人工知能入門（Gコード）');
    expect(events.single.id, contains('人工知能入門（Gコード）'));
    expect(events.single.location, '工学部 101');
    expect(events.single.id, contains('工学部 101'));
    expect(events.single.notes, contains('学務Google連携の説明'));
    expect(events.single.notes, contains('ターム: 2026年度 第2ターム'));
  });

  test('buildEvents excludes no-class days', () {
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: const [
        GakujoCalendarCourse(
          title: '月曜講義',
          weekday: DateTime.monday,
          period: 2,
        ),
      ],
      rangeStart: DateTime(2026, 6, 11),
      rangeEnd: DateTime(2026, 6, 30),
      noClassDates: [DateTime(2026, 6, 22)],
      uidNamespace: 'niigata-2026-第2ターム',
    );

    expect(
      events.map((event) => event.start),
      [
        DateTime(2026, 6, 15, 10, 30),
        DateTime(2026, 6, 29, 10, 30),
      ],
    );
  });

  test('buildEvents expands source-date observations as weekly courses', () {
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: [
        GakujoCalendarCourse(
          title: '物理学基礎BⅠ',
          weekday: DateTime.wednesday,
          period: 1,
          location: '総合教育研究棟 F-271',
          sourceDate: DateTime(2026, 6, 17),
        ),
      ],
      rangeStart: DateTime(2026, 6, 11),
      rangeEnd: DateTime(2026, 7, 10),
      uidNamespace: 'niigata-2026-第2ターム',
    );

    expect(
      events.map((event) => event.start),
      [
        DateTime(2026, 6, 17, 8, 45),
        DateTime(2026, 6, 24, 8, 45),
        DateTime(2026, 7, 1, 8, 45),
        DateTime(2026, 7, 8, 8, 45),
      ],
    );
  });

  test('buildEvents ignores malformed weekdays and periods', () {
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: const [
        GakujoCalendarCourse(
          title: '曜日なし',
          weekday: 0,
          period: 1,
        ),
        GakujoCalendarCourse(
          title: '時限なし',
          weekday: DateTime.monday,
          period: 99,
        ),
        GakujoCalendarCourse(
          title: '有効な講義',
          weekday: DateTime.monday,
          period: 1,
        ),
      ],
      rangeStart: DateTime(2026, 6, 11),
      rangeEnd: DateTime(2026, 6, 20),
      uidNamespace: 'niigata-2026-第2ターム',
    );

    expect(events, hasLength(1));
    expect(events.single.title, '有効な講義');
  });

  test('buildEvents gives stable IDs for the same class instance', () {
    List<GakujoCalendarEvent> build() {
      return GakujoCalendarEventBuilder.buildEvents(
        courses: const [
          GakujoCalendarCourse(
            title: ' 情報 リテラシー ',
            weekday: DateTime.tuesday,
            period: 3,
            location: ' A-101 ',
          ),
        ],
        rangeStart: DateTime(2026, 6, 11),
        rangeEnd: DateTime(2026, 6, 20),
        uidNamespace: 'niigata-2026-第2ターム',
      );
    }

    expect(build().single.id, build().single.id);
  });
}
