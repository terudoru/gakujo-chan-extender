import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'allowed_web_origins.dart';
import 'gakujo_activity_store.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_assignment.dart';
import 'gakujo_dated_activity.dart';

typedef DeadlineNotificationTappedCallback = FutureOr<void> Function(
  String url,
);

@visibleForTesting
String? deadlineNotificationTargetUrl(
  String? url, {
  required bool debugAllowed,
}) {
  final normalized = url;
  if (normalized == null) {
    return null;
  }
  if (!AllowedWebOrigins.canLoad(
    normalized,
    debugAllowed: debugAllowed,
  )) {
    return null;
  }
  // Browsers delete raw tabs and line breaks while parsing a URL, which could
  // join '_even<TAB>tId' into '_eventId' after the checks below.
  if (RegExp(r'[\x00-\x20\x7f]').hasMatch(normalized)) {
    return null;
  }
  // Inspect the original query: URI parsing can repair invalid percent escapes.
  final beforeFragment = normalized.split('#').first;
  final queryStart = beforeFragment.indexOf('?');
  if (queryStart >= 0) {
    final query = beforeFragment.substring(queryStart + 1);
    if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(query)) {
      return null;
    }
    try {
      for (final name in Uri.parse(normalized).queryParametersAll.keys) {
        // A decoded control or space in a name is never a real parameter.
        if (RegExp(r'[\x00-\x20\x7f]').hasMatch(name)) {
          return null;
        }
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
    final messageText =
        entry.messageText.isEmpty ? entry.dueText : entry.messageText;
    final text = '${entry.title} $messageText';
    final lowerText = text.toLowerCase();
    if (excludeKeywords.any(
      (keyword) =>
          keyword.isNotEmpty && lowerText.contains(keyword.toLowerCase()),
    )) {
      return false;
    }
    return messages.allows(
      text: text,
      isDeadline: entry.isDeadline,
      postedAt: GakujoDatedActivity.messagePostedAt(messageText),
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
    kind: entry.assignmentKind,
  );
}

/// One notification per assignment, wherever it was found. Other deadlines
/// are told apart by their own key.
String deadlineNotificationKey(
  GakujoDeadlineEntry entry,
  GakujoAssignment? assignment, {
  Set<String> collidingAssignmentIds = const {},
}) {
  if (assignment != null) {
    final id = collidingAssignmentIds.contains(assignment.notificationId)
        ? assignment.id
        : assignment.notificationId;
    return 'assignment|$id';
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
    this.dueAt,
    this.assignmentId,
    this.legacyIds = const [],
  });

  final int id;
  final String title;
  final String body;
  final String url;
  final DateTime at;
  final DateTime? dueAt;
  final String? assignmentId;
  // Historical OS ids that can be attributed to this assignment.
  final List<int> legacyIds;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'stableKey': assignmentId ?? id.toString(),
      'legacyIds': legacyIds,
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
  final currentAssignments = assignments.toList();
  final ids = <String, int>{};
  for (final assignment in currentAssignments) {
    ids.update(assignment.notificationId, (count) => count + 1,
        ifAbsent: () => 1);
  }
  bool remindable(GakujoAssignment assignment) {
    final topic = assignment.isSurvey
        ? GakujoNotificationTopic.survey
        : GakujoNotificationTopic.coursework;
    return topics.contains(topic) &&
        !preferences.isMuted(assignment.course) &&
        !(preferences.skipSubmitted && assignment.isSubmitted) &&
        assignment.dueAt.isAfter(now);
  }

  // Old unqualified history can only be attributed to an assignment when no
  // other remindable assignment shares that identity.
  final remindableIds = <String, int>{};
  for (final assignment in currentAssignments.where(remindable)) {
    remindableIds.update(assignment.notificationId, (count) => count + 1,
        ifAbsent: () => 1);
  }
  for (final assignment in currentAssignments) {
    if (!remindable(assignment)) {
      continue;
    }
    final due = assignment.dueAt;
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
      // Keep existing bookings unless another kind shares the old identity.
      final assignmentId = ids[assignment.notificationId]! > 1
          ? assignment.id
          : assignment.notificationId;
      int idFor(String assignmentId) => '$assignmentId|${offset.storageValue}'
          .codeUnits
          .fold<int>(17, (hash, unit) => (hash * 31 + unit) & 0x3fffffff);
      final reminder = GakujoReminder(
        // Stable across runs so a reminder is replaced, not duplicated.
        id: idFor(assignmentId),
        title: '【あと${offset.label.replaceAll('前', '')}】'
            '${assignment.kind} ${assignment.title}',
        body: '${assignment.course}　'
            '${shown.month}/${shown.day} '
            '${two(shown.hour)}:${two(shown.minute)}まで',
        url: assignment.url,
        at: at,
        dueAt: due,
        assignmentId: assignment.id,
        legacyIds: [
          if (remindableIds[assignment.notificationId] == 1)
            idFor(assignment.notificationId),
          idFor(assignment.id),
        ],
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
  final permissionGranted = ValueNotifier<bool?>(null);

  /// Reads the OS state without displaying a permission prompt.
  Future<bool?> checkPermission() async {
    bool? granted;
    try {
      granted = await _channel.invokeMethod<bool>('checkPermission');
    } on PlatformException {
      // This platform cannot currently report its permission state.
    } on MissingPluginException {
      // Older or unsupported platforms leave the state unknown.
    }
    permissionGranted.value = granted;
    if (granted != null) {
      _permissionRefused = !granted;
    }
    return granted;
  }

  Future<bool> openNotificationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Allows an explicit retry. Resume uses [checkPermission] without prompting.
  void forgetRefusal() {
    _permissionRefused = false;
  }

  /// Asks for permission to notify. Once refused, it is not asked again
  /// until [forgetRefusal] or [checkPermission] observes a grant: reminders are
  /// rebooked by background refreshes, which should not keep raising prompts.
  Future<bool> requestPermission() async {
    if (_permissionRefused) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      _permissionRefused = result != true;
      permissionGranted.value = result;
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> notifyDeadline(GakujoDeadlineEntry entry) {
    return _show(
      title: entry.title,
      body: entry.dueText,
      url: durableGakujoLink(entry.url, entry.source),
    );
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
    } else if (reminder.dueAt?.isAfter(_now()) ?? true) {
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

  Future<bool> _hasPermission(bool allowPermissionRequest) async {
    return allowPermissionRequest
        ? await _notificationService.requestPermission()
        : await _notificationService.checkPermission() == true;
  }

  /// Rebooks cached assignments immediately when OS settings granted access.
  Future<void> onAppResumed({
    required bool notificationsEnabled,
    required Set<GakujoNotificationTopic> topics,
    required GakujoNotificationPreferences preferences,
  }) async {
    final previouslyGranted = _notificationService.permissionGranted.value;
    final granted = await _notificationService.checkPermission();
    if (granted == true && previouslyGranted != true && notificationsEnabled) {
      await syncReminders(
        notificationsEnabled: notificationsEnabled,
        topics: topics,
        preferences: preferences,
        allowPermissionRequest: false,
      );
    }
  }

  /// Notifies new deadlines the student chose through [topics] and
  /// [messages].
  Future<void> notifyPendingDeadlines({
    required bool notificationsEnabled,
    bool allowPermissionRequest = true,
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
        allowPermissionRequest: allowPermissionRequest,
        topics: topics,
        messages: messages,
        preferences: preferences,
        messageExcludeKeywords: messageExcludeKeywords,
      ),
    );
  }

  Future<void> _notifyPendingDeadlines({
    required bool notificationsEnabled,
    required bool allowPermissionRequest,
    required Set<GakujoNotificationTopic> topics,
    required GakujoMessageNotificationSettings messages,
    required GakujoNotificationPreferences preferences,
    required List<String> messageExcludeKeywords,
  }) async {
    if (!notificationsEnabled) {
      return;
    }
    final deadlines = await _activityStore.loadDeadlines();
    final notifiedKeys = await _loadNotifiedKeys();
    final assignments = await _activityStore.loadAssignments();
    final seenIds = <String>{};
    final collidingIds = <String>{};
    for (final assignment in assignments) {
      if (!seenIds.add(assignment.notificationId)) {
        collidingIds.add(assignment.notificationId);
      }
    }
    final isWholeList = await _activityStore.assignmentsAreWholeList();
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
      )) {
        continue;
      }
      final assignment = assignmentForDeadline(entry, assignments);
      // A whole list proves an unmatched list entry was withdrawn. Messages
      // and schedule-only entries do not make that promise.
      if (isWholeList && entry.source == 'レポート・小テスト' && assignment == null) {
        continue;
      }
      if (assignment != null
          ? !assignment.dueAt.isAfter(_now())
          : _activityStore.isDeadlinePassed(entry, now: _now())) {
        continue;
      }
      if (preferences.isMuted(assignment?.course ?? entry.course) ||
          (preferences.skipSubmitted && (assignment?.isSubmitted ?? false))) {
        continue;
      }
      final key = deadlineNotificationKey(entry, assignment,
          collidingAssignmentIds: collidingIds);
      if (notifiedKeys.contains(key) ||
          notifiedKeys.contains(entry.key) ||
          (assignment != null &&
              notifiedKeys.contains('assignment|${assignment.id}'))) {
        continue;
      }
      pending.putIfAbsent(key, () => entry);
    }
    if (pending.isEmpty) {
      return;
    }
    if (!await _hasPermission(allowPermissionRequest)) {
      return;
    }
    final notifiedNow = <String>[];
    for (final MapEntry(:key, value: entry) in pending.entries) {
      if (await _notificationService.notifyDeadline(entry)) {
        notifiedNow.add(key);
        final assignment = assignmentForDeadline(entry, assignments);
        if (assignment != null) {
          // Remember the kind before a same-title collision appears. Older
          // builds saved only the unqualified key, so those may repeat once.
          notifiedNow.add('assignment|${assignment.id}');
        }
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
    bool allowPermissionRequest = true,
  }) {
    return _enqueueNotificationOperation(() async {
      if (notificationsEnabled) {
        await _loadNotifiedKeys();
      }
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
          !await _hasPermission(allowPermissionRequest)) {
        return;
      }
      final booksAhead = await _notificationService.scheduleReminders(
        reminders,
        onInAppReminder: (reminder) => _enqueueNotificationOperation(
          () => _notifyReminderOnce(reminder,
              topics: topics, preferences: preferences),
        ),
      );
      if (booksAhead || lateReminders.isEmpty) {
        return;
      }
      if (reminders.isEmpty && !await _hasPermission(allowPermissionRequest)) {
        return;
      }
      for (final reminder in lateReminders) {
        await _notifyReminderOnce(reminder,
            topics: topics, preferences: preferences);
      }
    });
  }

  Future<void> _notifyReminderOnce(
    GakujoReminder reminder, {
    required Set<GakujoNotificationTopic> topics,
    required GakujoNotificationPreferences preferences,
  }) async {
    final assignments = reminder.assignmentId != null
        ? await _activityStore.loadAssignmentsIfAvailable()
        : null;
    if (assignments != null) {
      GakujoAssignment? current;
      for (final assignment in assignments) {
        if (assignment.id == reminder.assignmentId) {
          current = assignment;
          break;
        }
      }
      final assignment = current;
      if (assignment == null ||
          (preferences.skipSubmitted && assignment.isSubmitted) ||
          preferences.isMuted(assignment.course) ||
          !topics.contains(assignment.isSurvey
              ? GakujoNotificationTopic.survey
              : GakujoNotificationTopic.coursework) ||
          assignment.dueAt != reminder.dueAt ||
          !preferences.reminderOffsets.any((offset) =>
              assignment.dueAt.subtract(offset.before) == reminder.at)) {
        return;
      }
    }
    final trigger = reminder.at.millisecondsSinceEpoch;
    final key = 'reminder|${reminder.assignmentId ?? reminder.id}|$trigger';
    final legacyKeys = {
      for (final id in {reminder.id, ...reminder.legacyIds}) 'reminder|$id',
    };
    final notifiedKeys = await _loadNotifiedKeys();
    if (notifiedKeys.contains(key) ||
        legacyKeys
            .any((legacyKey) => notifiedKeys.contains('$legacyKey|$trigger'))) {
      return;
    }
    for (final legacyKey in legacyKeys) {
      final legacySeen = notifiedKeys
          .where((key) => key.startsWith('$legacyKey|legacySeen|'))
          .map((key) => int.tryParse(key.split('|').last))
          .whereType<int>();
      if (notifiedKeys.contains(legacyKey) &&
          legacySeen.any((seen) =>
              trigger <= seen + const Duration(hours: 2).inMilliseconds)) {
        return;
      }
    }
    final dueAt = reminder.dueAt;
    if ((dueAt != null && !dueAt.isAfter(_now())) ||
        await _notificationService.notifyReminder(reminder)) {
      await _activityStore.addNotifiedDeadlineKeys([key]);
    }
  }

  Future<Set<String>> _loadNotifiedKeys() async {
    final keys = await _activityStore.loadNotifiedDeadlineKeys();
    final firstSeen = _now().millisecondsSinceEpoch;
    final migrationKeys = <String>[];
    for (final key
        in keys.where((key) => RegExp(r'^reminder\|-?\d+$').hasMatch(key))) {
      if (!keys.any((other) => other.startsWith('$key|legacySeen|'))) {
        migrationKeys.add('$key|legacySeen|$firstSeen');
      }
    }
    if (migrationKeys.isNotEmpty) {
      await _activityStore.addNotifiedDeadlineKeys(migrationKeys);
      keys.addAll(migrationKeys);
    }
    return keys;
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
