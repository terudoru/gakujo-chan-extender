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

      test('replaces one namespace atomically and records range after commit',
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
        expect(
          source,
          contains('eventNotes(notes, match: uidNamespace)'),
        );
        final commit = source.indexOf('try eventStore.commit()');
        final clearPending = source.indexOf(
          'clearPendingCleanupCalendars(title: title)',
          commit,
        );
        final remember = source.indexOf('rememberSyncedRange(', commit);
        expect(commit, greaterThanOrEqualTo(0));
        expect(clearPending, greaterThan(commit));
        expect(remember, greaterThan(commit));
        expect(source, contains('eventStore.reset()'));
      });

      test('does not silently write into the default calendar', () {
        expect(source, isNot(contains('return fallback')));
        expect(source, contains('missingWritableCalendar'));
      });

      test('renames only calendars created and managed by the app', () {
        expect(
          source,
          contains('if isManagedCalendar(calendar, title: title) {'),
        );
        expect(source, isNot(contains('if calendar.title != title {')));
        expect(source, contains('forgetStoredCalendar(title: title)'));
        expect(source,
            contains('queueCalendarForCleanup(calendar, title: title)'));
        expect(source,
            contains('[calendar] + pendingCleanupCalendars(title: title)'));
        expect(
          source,
          contains(
              'rememberCalendar(existing, title: title, managedByApp: false)'),
        );
        expect(
          source,
          contains(
              'rememberCalendar(calendar, title: title, managedByApp: true)'),
        );
        expect(source, contains('calendarManagedKey(for: title)'));
      });

      test('migrates only matching legacy manual term namespaces', () {
        expect(source, contains('legacyManualNamespace('));
        expect(source, contains('dateFromLegacyNamespaceStamp('));
        expect(
          source,
          contains(r'niigata-\(academicYear)-第\(termNumber)ターム'),
        );
        expect(source, contains('case 4, 5:'));
        expect(source, contains('case 6, 7, 8, 9:'));
        expect(source, contains('case 10, 11:'));
      });

      test('keeps the validation calendar identity reserved', () {
        expect(
            source, contains('validationUidNamespace = "calendar-validation"'));
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
