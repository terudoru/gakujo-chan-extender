import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final path in [
    'ios/Runner/AppDelegate.swift',
    'macos/Runner/AppDelegate.swift',
  ]) {
    group(path, () {
      late String source;

      setUpAll(() {
        source = File(path).readAsStringSync();
      });

      test(
        'replaces one namespace atomically and records range after commit',
        () {
          expect(source, contains('commitChanges: false'));
          expect(source, contains('previouslySyncedRange('));
          expect(source, contains('date(byAdding: .year, value: -1'));
          expect(source, contains('date(byAdding: .year, value: 1'));
          expect(source, contains('for calendar in calendars'));
          expect(source, contains('hasMissingStoredRange = true'));
          expect(source, contains('earliest = min(earliest, previous.start)'));
          expect(source, contains('latest = max(latest, previous.end)'));
          expect(source, contains('calendar.calendarIdentifier'));
          expect(source, contains('eventNotes(notes, match: uidNamespace)'));
          final commit = source.indexOf('try eventStore.commit()');
          final remember = source.indexOf('rememberSyncedRange(', commit);
          expect(commit, greaterThanOrEqualTo(0));
          expect(remember, greaterThan(commit));
          expect(source, contains('eventStore.reset()'));
        },
      );

      // These contracts cover the native metadata paths without executing
      // EventKit. A scoped operation cannot prove an old calendar is empty.
      test('namespace sync retains old calendars for the other terms', () {
        final sync = _method(source, 'syncEvents');
        expect(sync, contains('pendingCleanupCalendars(title: title)'));
        expect(sync, contains('uidNamespace: uidNamespace,'));
        expect(sync, isNot(contains('clearPendingCleanupCalendars(')));
        expect(sync, isNot(contains('removeObject(')));
      });

      test('range delete retains old calendars for later period deletion', () {
        final delete = _method(source, 'deleteAddedEvents');
        expect(
          delete,
          contains('pendingCleanupCalendars(title: calendarTitle)'),
        );
        expect(delete, contains('start: rangeStart,'));
        expect(delete, contains('end: rangeEnd,'));
        expect(delete, isNot(contains('clearPendingCleanupCalendars(')));
        expect(delete, isNot(contains('removeObject(')));
      });

      test(
        'old calendar identifiers persist, deduplicate and isolate validation',
        () {
          final queue = _method(source, 'queueCalendarForCleanup');
          final resolve = _method(source, 'pendingCleanupCalendars');
          final key = _method(source, 'pendingCalendarCleanupKey');
          expect(queue, contains('defaults.stringArray(forKey: key) ?? []'));
          expect(queue, contains('if !identifiers.contains('));
          expect(
            queue,
            contains('identifiers.append(calendar.calendarIdentifier)'),
          );
          expect(queue, contains('defaults.set(identifiers, forKey: key)'));
          expect(resolve, contains('UserDefaults.standard.stringArray('));
          expect(
            resolve,
            contains('eventStore.calendar(withIdentifier: identifier)'),
          );
          expect(resolve, contains('calendar.allowsContentModifications'));
          expect(key, contains('title == Self.validationCalendarTitle'));
          expect(key, contains('? Self.validationPendingCalendarCleanupKey'));
          expect(key, contains(': Self.pendingCalendarCleanupKey'));
          expect(source, isNot(contains('clearPendingCleanupCalendars(')));
        },
      );

      test('does not silently write into the default calendar', () {
        expect(source, isNot(contains('return fallback')));
        expect(source, contains('missingWritableCalendar'));
      });

      test('tries other accounts when the default cannot hold a calendar', () {
        expect(source, contains('for source in calendarSourceCandidates()'));
        expect(source, contains('source.sourceType != .subscribed'));
        expect(source, contains('source.sourceType != .birthdays'));
        expect(source, contains('throw lastError ??'));
      });

      test('renames only calendars created and managed by the app', () {
        expect(
          source,
          contains('if isManagedCalendar(calendar, title: title) {'),
        );
        expect(source, isNot(contains('if calendar.title != title {')));
        expect(source, contains('forgetStoredCalendar(title: title)'));
        expect(
          source,
          contains('queueCalendarForCleanup(calendar, title: title)'),
        );
        expect(
          source,
          contains('[calendar] + pendingCleanupCalendars(title: title)'),
        );
        expect(
          source,
          contains(
            'rememberCalendar(existing, title: title, managedByApp: false)',
          ),
        );
        expect(
          source,
          contains(
            'rememberCalendar(calendar, title: title, managedByApp: true)',
          ),
        );
        expect(source, contains('calendarManagedKey(for: title)'));
      });

      test('migrates only matching legacy manual term namespaces', () {
        expect(source, contains('legacyManualNamespace('));
        expect(source, contains('dateFromLegacyNamespaceStamp('));
        expect(source, contains(r'niigata-\(academicYear)-第\(termNumber)ターム'));
        expect(source, contains('case 4, 5:'));
        expect(source, contains('case 6, 7, 8, 9:'));
        expect(source, contains('case 10, 11:'));
      });

      test('keeps the validation calendar identity reserved', () {
        expect(
          source,
          contains('validationUidNamespace = "calendar-validation"'),
        );
        expect(
          source,
          contains('== (uidNamespace == Self.validationUidNamespace)'),
        );
        expect(
          source,
          contains('calendarTitle == Self.validationCalendarTitle'),
        );
        expect(source, contains('? Self.validationUidNamespace'));
      });
    });
  }
}

String _method(String source, String name) {
  final start = source.indexOf('  private func $name(');
  expect(start, greaterThanOrEqualTo(0), reason: 'missing Swift method $name');
  final end = source.indexOf('\n  private func ', start + 1);
  return source.substring(start, end < 0 ? source.length : end);
}
