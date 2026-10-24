import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const directory = 'android/app/src/main';
  final source = File(
    '$directory/kotlin/net/yoshida/morebettergakujo/DeadlineReminders.kt',
  ).readAsStringSync();

  test('exact-alarm grants reach the non-exported restore receiver on API 31+',
      () {
    final manifest = File('$directory/AndroidManifest.xml').readAsStringSync();
    final receiver = RegExp(
      r'<receiver\s+android:name="\.DeadlineReminderRestoreReceiver"[\s\S]*?</receiver>',
    ).firstMatch(manifest)!.group(0)!;
    expect(receiver, contains('android:exported="false"'));
    expect(
        receiver,
        contains(
          'android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED',
        ));
    final handler = source.substring(
      source.indexOf('class DeadlineReminderRestoreReceiver'),
    );
    expect(handler, contains('Intent.ACTION_BOOT_COMPLETED'));
    expect(handler, contains('Intent.ACTION_MY_PACKAGE_REPLACED'));
    expect(
        handler,
        matches(RegExp(
          r'AlarmManager\.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> \{\s*'
          r'if \(Build\.VERSION\.SDK_INT >= Build\.VERSION_CODES\.S\) \{\s*'
          r'DeadlineReminders\.restore\(context\)',
        )));
    expect(handler, contains('DeadlineReminderDelivery.attempt('));
  });

  test('replacement and restore cancel old ids before booking the new list',
      () {
    final replace = source.substring(
      source.indexOf('fun replace('),
      source.indexOf('fun parse('),
    );
    final cancel = replace.indexOf('cancel(context, old)');
    final save = replace.indexOf('save(context, reminders)');
    final book = replace.indexOf('book(context, reminders)');
    expect(cancel, greaterThanOrEqualTo(0));
    expect(save, greaterThan(cancel));
    expect(book, greaterThan(save));
    expect(replace, contains('replace(context, load(context))'));
  });

  test('delivery records stable keys and trigger times before refilling', () {
    final show = source.substring(
      source.indexOf('fun show(context: Context, intent: Intent)'),
      source.indexOf('private fun show('),
    );
    expect(show, contains('intent.getLongExtra(EXTRA_AT_MILLIS, 0L)'));
    expect(source, contains('putExtra(EXTRA_AT_MILLIS, reminder.atMillis)'));
    expect(show, contains('intent.getStringExtra(EXTRA_STABLE_KEY)'));
    expect(source, contains('putExtra(EXTRA_STABLE_KEY, reminder.stableKey)'));
    expect(
        source,
        contains(
            'putExtra(EXTRA_LEGACY_IDS, reminder.legacyIds.toIntArray())'));
    expect(source, contains('.put("stableKey", reminder.stableKey)'));
    expect(source, contains('item.optString("stableKey")'));
    expect(show, contains('DeadlineReminderDelivery.wasDelivered('));
    expect(show, contains('reminder.stableKey, reminder.legacyIds'));
    expect(show, contains('stableKey = reminder.stableKey'));
    final record = show.indexOf('DeadlineReminderDelivery.record(');
    final persist = show.indexOf('.putString(KEY_DELIVERED,');
    final refill = show.indexOf('book(context, load(context))');
    expect(record, greaterThan(0));
    expect(persist, greaterThan(record));
    expect(refill, greaterThan(persist));
  });

  test('delivered history loads legacy numeric ids through the bounded parser',
      () {
    final loader =
        source.substring(source.indexOf('private fun loadDelivered('));
    expect(loader, contains('DeadlineReminderDelivery.readHistory('));
    expect(loader, contains('array.opt(it)'));
  });

  test('successful per-file downloads retain offered document permissions', () {
    final activity = File(
      '$directory/kotlin/net/yoshida/morebettergakujo/MainActivity.kt',
    ).readAsStringSync();
    final handler = activity.substring(
      activity.indexOf('private fun handleCreateDownloadFileResult('),
      activity.indexOf('private fun downloadToConfiguredFolder('),
    );
    final save = handler.indexOf('performDownloadToUri(args, uri)');
    final persist =
        handler.indexOf('GakujoDocumentPermissions.persistIfOffered(');
    expect(save, greaterThanOrEqualTo(0));
    expect(persist, greaterThan(save));
    expect(handler,
        contains('contentResolver.takePersistableUriPermission(uri, it)'));
    expect(handler.indexOf('result.success('), greaterThan(persist));
  });
}
