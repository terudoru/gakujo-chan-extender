import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'allowed_web_origins.dart';
import 'gakujo_activity_store.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_assignment.dart';

typedef DeadlineNotificationTappedCallback = FutureOr<void> Function(
  String url,
);

@visibleForTesting
String? deadlineNotificationTargetUrl(
  String? url, {
  required bool debugAllowed,
}) {
  final normalized = url?.trim();
  if (!AllowedWebOrigins.canLoad(
    normalized,
    debugAllowed: debugAllowed,
  )) {
    return null;
  }
  // Inspect the original query: URI parsing can repair invalid percent escapes.
  final beforeFragment = normalized!.split('#').first;
  final queryStart = beforeFragment.indexOf('?');
  if (queryStart >= 0) {
    final query = beforeFragment.substring(queryStart + 1);
    if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(query)) {
      return null;
    }
    try {
      for (final name in Uri.parse(normalized).queryParametersAll.keys) {
        final lower = name.toLowerCase();
        if (lower == '_eventid' ||
            lower == '_flowexecutionkey' ||
            lower.startsWith('_eventid_')) {
          return null;
        }
      }
    } on FormatException {
      return null;
    }
  }
  return normalized;
}

/// Which [GakujoNotificationTopic] a deadline outside 連絡通知 is about.
/// Gakujo writes some tab names in half-width katakana (ﾚﾎﾟｰﾄ・小ﾃｽﾄ・ｱﾝｹｰﾄ).
GakujoNotificationTopic notificationTopicFor(GakujoDeadlineEntry entry) {
  final text = '${entry.title} ${entry.dueText}';
  bool mentions(List<String> words) => words.any(text.contains);
  if (mentions(const ['アンケート', 'ｱﾝｹｰﾄ'])) {
    return GakujoNotificationTopic.survey;
  }
  if (mentions(const ['小テスト', '小ﾃｽﾄ', 'レポート', 'ﾚﾎﾟｰﾄ', '課題']) ||
      entry.source == 'レポート・小テスト') {
    return GakujoNotificationTopic.coursework;
  }
  return GakujoNotificationTopic.other;
}

/// Whether [entry] may become an OS notification under the student's
/// choices. A 連絡通知 follows [messages]; in keyword mode it need not carry
/// a deadline. One the student hid with [excludeKeywords] never notifies.
bool isNotifiableDeadline(
  GakujoDeadlineEntry entry, {
  required Set<GakujoNotificationTopic> topics,
  required GakujoMessageNotificationSettings messages,
  List<String> excludeKeywords = const [],
}) {
  if (entry.source == '連絡通知') {
    final text = '${entry.title} ${entry.dueText}';
    if (excludeKeywords.any(
      (keyword) => keyword.isNotEmpty && text.contains(keyword),
    )) {
      return false;
    }
    return messages.allows(
      text: text,
      isDeadline: entry.isDeadline,
    );
  }
  return entry.isDeadline && topics.contains(notificationTopicFor(entry));
}

/// The assignment [entry] is about, from the レポート・小テスト list.
GakujoAssignment? assignmentForDeadline(
  GakujoDeadlineEntry entry,
  Iterable<GakujoAssignment> assignments,
) {
  if (entry.source == '連絡通知' || entry.assignment.isEmpty) {
    return null;
  }
  return findAssignment(
    assignments,
    title: entry.assignment,
    course: entry.course,
    courseCode: entry.courseCode,
  );
}

/// One notification per assignment, wherever it was found. Other deadlines
/// are told apart by their own key.
String deadlineNotificationKey(
  GakujoDeadlineEntry entry,
  GakujoAssignment? assignment,
) {
  if (assignment != null) {
    return 'assignment|${assignment.id}';
  }
  if (entry.assignment.isNotEmpty &&
      (entry.course.isNotEmpty || entry.courseCode.isNotEmpty)) {
    return 'assignment|${assignmentId(
      course: entry.course,
      courseCode: entry.courseCode,
      title: entry.assignment,
    )}';
  }
  return entry.key;
}

/// A notification booked ahead of an assignment's closing time.
class GakujoReminder {
  const GakujoReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.url,
    required this.at,
  });

  final int id;
  final String title;
  final String body;
  final String url;
  final DateTime at;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'url': url,
      'atMillis': at.millisecondsSinceEpoch,
    };
  }
}

/// Reminders for assignments still open, at the times the student chose.
/// [lateReminders], when supplied, collects the latest elapsed reminder per
/// assignment for platforms that cannot book ahead.
List<GakujoReminder> planReminders({
  required Iterable<GakujoAssignment> assignments,
  required Set<GakujoNotificationTopic> topics,
  required GakujoNotificationPreferences preferences,
  required DateTime now,
  Duration horizon = const Duration(days: 30),
  List<GakujoReminder>? lateReminders,
}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final reminders = <GakujoReminder>[];
  for (final assignment in assignments) {
    final topic = assignment.isSurvey
        ? GakujoNotificationTopic.survey
        : GakujoNotificationTopic.coursework;
    if (!topics.contains(topic) ||
        preferences.isMuted(assignment.course) ||
        (preferences.skipSubmitted && assignment.isSubmitted)) {
      continue;
    }
    final due = assignment.dueAt;
    if (!due.isAfter(now)) {
      continue;
    }
    final shown = assignment.dueInJapan;
    GakujoReminder? late;
    for (final offset in GakujoReminderOffset.values) {
      if (!preferences.reminderOffsets.contains(offset)) {
        continue;
      }
      final at = due.subtract(offset.before);
      final isLate = !at.isAfter(now);
      if ((isLate && lateReminders == null) || at.isAfter(now.add(horizon))) {
        continue;
      }
      final id = '${assignment.id}|${offset.storageValue}';
      final reminder = GakujoReminder(
        // Stable across runs so a reminder is replaced, not duplicated.
        id: id.codeUnits.fold<int>(17, (hash, unit) {
          return (hash * 31 + unit) & 0x3fffffff;
        }),
        title: '【あと${offset.label.replaceAll('前', '')}】'
            '${assignment.kind} ${assignment.title}',
        body: '${assignment.course}　'
            '${shown.month}/${shown.day} '
            '${two(shown.hour)}:${two(shown.minute)}まで',
        url: assignment.url,
        at: at,
      );
      if (isLate) {
        if (late == null || at.isAfter(late.at)) {
          late = reminder;
        }
      } else {
        reminders.add(reminder);
      }
    }
    if (late != null) {
      lateReminders?.add(late);
    }
  }
  reminders.sort((a, b) => a.at.compareTo(b.at));
  return reminders;
}

class GakujoNotificationService {
  GakujoNotificationService({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const _channel = MethodChannel(
    'net.yoshida.morebettergakujo/notifications',
  );

  DeadlineNotificationTappedCallback? _deadlineNotificationTapped;

  String? targetUrl(String? url, {required bool debugAllowed}) {
    return deadlineNotificationTargetUrl(
      url,
      debugAllowed: debugAllowed,
    );
  }

  void setDeadlineNotificationTappedHandler(
    DeadlineNotificationTappedCallback? handler,
  ) {
    _deadlineNotificationTapped = handler;
    _channel.setMethodCallHandler(handler == null ? null : _handleMethodCall);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'deadlineNotificationTapped') {
      throw MissingPluginException(
          'Unknown notification method ${call.method}');
    }
    final arguments = call.arguments;
    final url = arguments is Map ? arguments['url'] : arguments;
    final normalized = url is String ? url.trim() : '';
    final handler = _deadlineNotificationTapped;
    if (normalized.isEmpty || handler == null) {
      return false;
    }
    await handler(normalized);
    return true;
  }

  Future<String?> takePendingNotificationUrl() async {
    try {
      final url = await _channel.invokeMethod<String>(
        'takePendingNotificationUrl',
      );
      final normalized = url?.trim();
      return normalized == null || normalized.isEmpty ? null : normalized;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  bool _permissionRefused = false;

  /// The student may have allowed notifications in the system settings
  /// meanwhile, as when returning to the app.
  void forgetRefusal() {
    _permissionRefused = false;
  }

  /// Asks for permission to notify. Once refused, it is not asked again
  /// until [forgetRefusal]: reminders are rebooked by background refreshes,
  /// and Android would otherwise raise the prompt at random moments.
  Future<bool> requestPermission() async {
    if (_permissionRefused) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      _permissionRefused = result != true;
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> notifyDeadline(GakujoDeadlineEntry entry) {
    return _show(title: entry.title, body: entry.dueText, url: entry.url);
  }

  Future<bool> notifyReminder(GakujoReminder reminder) {
    return _show(
      title: reminder.title,
      body: reminder.body,
      url: reminder.url,
    );
  }

  Future<bool> _show({
    required String title,
    required String body,
    required String url,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'notifyDeadline',
        {'title': title, 'body': body, 'url': url},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  final Map<int, ({GakujoReminder reminder, Timer timer})> _inAppReminders = {};
  Timer? _inAppReminderCheck;
  Future<void> Function(GakujoReminder)? _onInAppReminder;

  /// Books [reminders] with the OS, replacing earlier ones. Where the OS
  /// cannot book ahead (Windows), they fire from the app while it is open.
  /// Returns whether the OS booked them. [onInAppReminder] handles delivery
  /// when an in-app timer fires, so the coordinator can also record it.
  Future<bool> scheduleReminders(
    List<GakujoReminder> reminders, {
    Future<void> Function(GakujoReminder)? onInAppReminder,
  }) async {
    for (final booked in _inAppReminders.values) {
      booked.timer.cancel();
    }
    _inAppReminders.clear();
    _inAppReminderCheck?.cancel();
    _inAppReminderCheck = null;
    _onInAppReminder = onInAppReminder;
    try {
      final booked = await _channel.invokeMethod<bool>(
        'scheduleReminders',
        {
          'reminders': [for (final reminder in reminders) reminder.toJson()],
        },
      );
      if (booked == true) {
        return true;
      }
    } on PlatformException {
      // Fall back to reminders from the running app.
    } on MissingPluginException {
      // Same.
    }
    final now = _now();
    for (final reminder in reminders) {
      _inAppReminders[reminder.id] = (
        reminder: reminder,
        timer: Timer(reminder.at.difference(now), () => _remind(reminder.id)),
      );
    }
    if (_inAppReminders.isNotEmpty) {
      // A timer does not count the time the computer sleeps, so it can go
      // off long after its time. The clock catches those.
      _inAppReminderCheck = Timer.periodic(const Duration(minutes: 1), (_) {
        final now = _now();
        for (final booked in _inAppReminders.values.toList()) {
          if (!booked.reminder.at.isAfter(now)) {
            _remind(booked.reminder.id);
          }
        }
      });
    }
    return false;
  }

  void _remind(int id) {
    final booked = _inAppReminders.remove(id);
    if (booked == null) {
      return;
    }
    booked.timer.cancel();
    if (_inAppReminders.isEmpty) {
      _inAppReminderCheck?.cancel();
      _inAppReminderCheck = null;
    }
    final reminder = booked.reminder;
    final onInAppReminder = _onInAppReminder;
    if (onInAppReminder != null) {
      unawaited(onInAppReminder(reminder));
    } else {
      unawaited(notifyReminder(reminder));
    }
  }
}

class GakujoDeadlineNotificationCoordinator {
  GakujoDeadlineNotificationCoordinator({
    required GakujoActivityStore activityStore,
    required GakujoNotificationService notificationService,
    DateTime Function()? now,
  })  : _activityStore = activityStore,
        _notificationService = notificationService,
        _now = now ?? DateTime.now;

  final GakujoActivityStore _activityStore;
  final GakujoNotificationService _notificationService;
  final DateTime Function() _now;
  Future<void> _pendingNotificationOperation = Future<void>.value();

  /// Notifies new deadlines the student chose through [topics] and
  /// [messages].
  Future<void> notifyPendingDeadlines({
    required bool notificationsEnabled,
    Set<GakujoNotificationTopic> topics = const {
      ...GakujoNotificationTopic.values,
    },
    GakujoMessageNotificationSettings messages =
        const GakujoMessageNotificationSettings(
      mode: GakujoMessageNotificationMode.deadlines,
    ),
    GakujoNotificationPreferences preferences =
        const GakujoNotificationPreferences(),
    List<String> messageExcludeKeywords = const [],
  }) {
    return _enqueueNotificationOperation(
      () => _notifyPendingDeadlines(
        notificationsEnabled: notificationsEnabled,
        topics: topics,
        messages: messages,
        preferences: preferences,
        messageExcludeKeywords: messageExcludeKeywords,
      ),
    );
  }

  Future<void> _notifyPendingDeadlines({
    required bool notificationsEnabled,
    required Set<GakujoNotificationTopic> topics,
    required GakujoMessageNotificationSettings messages,
    required GakujoNotificationPreferences preferences,
    required List<String> messageExcludeKeywords,
  }) async {
    if (!notificationsEnabled) {
      return;
    }
    final deadlines = await _activityStore.loadDeadlines();
    final notifiedKeys = await _activityStore.loadNotifiedDeadlineKeys();
    final assignments = await _activityStore.loadAssignments();
    final pending = <String, GakujoDeadlineEntry>{};
    for (final entry in deadlines) {
      if (pending.length >= 5) {
        break;
      }
      if (!isNotifiableDeadline(
            entry,
            topics: topics,
            messages: messages,
            excludeKeywords: messageExcludeKeywords,
          ) ||
          _activityStore.isDeadlinePassed(entry)) {
        continue;
      }
      final assignment = assignmentForDeadline(entry, assignments);
      if (preferences.isMuted(assignment?.course ?? entry.course) ||
          (preferences.skipSubmitted && (assignment?.isSubmitted ?? false))) {
        continue;
      }
      final key = deadlineNotificationKey(entry, assignment);
      if (notifiedKeys.contains(key) || notifiedKeys.contains(entry.key)) {
        continue;
      }
      pending.putIfAbsent(key, () => entry);
    }
    if (pending.isEmpty) {
      return;
    }
    if (!await _notificationService.requestPermission()) {
      return;
    }
    final notifiedNow = <String>[];
    for (final MapEntry(:key, value: entry) in pending.entries) {
      if (await _notificationService.notifyDeadline(entry)) {
        notifiedNow.add(key);
      }
    }
    await _activityStore.addNotifiedDeadlineKeys(notifiedNow);
  }

  /// Books reminders for open assignments, or clears them when reminders
  /// or notifications are off.
  Future<void> syncReminders({
    required bool notificationsEnabled,
    required Set<GakujoNotificationTopic> topics,
    required GakujoNotificationPreferences preferences,
  }) {
    return _enqueueNotificationOperation(() async {
      final lateReminders = <GakujoReminder>[];
      final reminders = notificationsEnabled
          ? planReminders(
              assignments: await _activityStore.loadAssignments(),
              topics: topics,
              preferences: preferences,
              now: _now(),
              lateReminders: lateReminders,
            )
          : const <GakujoReminder>[];
      if (reminders.isNotEmpty &&
          !await _notificationService.requestPermission()) {
        return;
      }
      final booksAhead = await _notificationService.scheduleReminders(
        reminders,
        onInAppReminder: (reminder) => _enqueueNotificationOperation(
          () => _notifyReminderOnce(reminder),
        ),
      );
      if (booksAhead || lateReminders.isEmpty) {
        return;
      }
      if (reminders.isEmpty &&
          !await _notificationService.requestPermission()) {
        return;
      }
      for (final reminder in lateReminders) {
        await _notifyReminderOnce(reminder);
      }
    });
  }

  Future<void> _notifyReminderOnce(GakujoReminder reminder) async {
    final key = 'reminder|${reminder.id}';
    final notifiedKeys = await _activityStore.loadNotifiedDeadlineKeys();
    if (notifiedKeys.contains(key)) {
      return;
    }
    if (await _notificationService.notifyReminder(reminder)) {
      await _activityStore.addNotifiedDeadlineKeys([key]);
    }
  }

  Future<T> _enqueueNotificationOperation<T>(
    Future<T> Function() operation,
  ) {
    final next = _pendingNotificationOperation.then((_) => operation());
    _pendingNotificationOperation = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }
}
