import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'allowed_web_origins.dart';
import 'gakujo_activity_store.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_assignment.dart';
import 'gakujo_dated_activity.dart';
import 'gakujo_notification_history.dart';

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

/// One notification per assignment or identified message, wherever it was
/// found. Other deadlines are told apart by their own key.
String deadlineNotificationKey(
  GakujoDeadlineEntry entry,
  GakujoAssignment? assignment, {
  Set<String> collidingAssignmentIds = const {},
}) {
  if (entry.source == '連絡通知') {
    return gakujoMessageNotificationKey(entry.url) ?? entry.key;
  }
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
    this.topic,
    this.legacyIds = const [],
    this.notificationAccount,
  });

  final int id;
  final String title;
  final String body;
  final String url;
  final DateTime at;
  final DateTime? dueAt;
  final String? assignmentId;
  final GakujoNotificationTopic? topic;
  // Historical OS ids that can be attributed to this assignment.
  final List<int> legacyIds;
  final String? notificationAccount;

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
        topic: assignment.isSurvey
            ? GakujoNotificationTopic.survey
            : GakujoNotificationTopic.coursework,
        notificationAccount: assignment.notificationAccount,
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

/// One mounted receiver on the notification channel. Platform messages are FIFO
/// on a messenger. Send take/end synchronously with local ownership changes.
class NotificationTapConsumer {
  NotificationTapConsumer._(this._channel, this._handler);

  static final _run = List.generate(
    4,
    (_) => Random.secure().nextInt(1 << 30).toRadixString(16).padLeft(8, '0'),
  ).join();
  static int _generation = 0;
  static NotificationTapConsumer? _current;
  final String _token = '$_run:${++_generation}';
  final MethodChannel _channel;
  final FutureOr<bool> Function(String) _handler;
  final _detached = Completer<void>();
  Future<void> get detached => _detached.future;
  bool get isCurrent => identical(this, _current);
  bool _takeStarted = false;
  bool _mayHaveReceipt = false;
  bool _legacy = false;
  bool _dispatching = false;

  Map<String, Object> get _arguments => {'version': 1, 'consumer': _token};

  void _install() {
    _current?.dispose();
    _current = this;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'deadlineNotificationTapped') {
        throw MissingPluginException(
          'Unknown notification method ${call.method}',
        );
      }
      final args = call.arguments;
      if (!isCurrent ||
          (args is Map &&
              args.containsKey('consumer') &&
              args['consumer'] != _token)) {
        return false;
      }
      final url = args is Map ? args['url'] : args;
      if (url is! String || url.trim().isEmpty) return false;
      return _handler(url.trim());
    });
  }

  Future<void> dispatchStartup(
    Future<void> Function(String?) navigate, {
    required bool debugAllowed,
  }) async {
    if (!isCurrent || _takeStarted) return;
    _takeStarted = true;
    _mayHaveReceipt = true;
    var accepted = false;
    try {
      final url = await _take();
      if (!isCurrent) return;
      if (url == null) _finish(false); // Release an uncertain receipt.
      _dispatching = true;
      final target = deadlineNotificationTargetUrl(
        url?.trim(),
        debugAllowed: debugAllowed,
      );
      if (url != null && target == null) {
        _finish(true); // Terminal policy rejection.
      }
      await navigate(target);
      accepted = true;
    } finally {
      _finish(accepted);
    }
  }

  Future<String?> _take() async {
    for (var attempt = 0; attempt < 2 && isCurrent; attempt++) {
      try {
        final reply = await _channel.invokeMethod<Object?>(
          'takePendingNotificationUrl',
          _arguments,
        );
        if (!isCurrent) return null; // Disposal already released the receipt.
        if (reply is String || reply == null) {
          _legacy = true;
          _mayHaveReceipt = false;
          return reply as String?;
        }
        if (reply
            case {
              'version': 1,
              'consumer': final String owner,
              'url': final String? url,
            }
            when owner == _token) {
          _mayHaveReceipt = url != null;
          return url;
        }
      } on MissingPluginException {
        return null;
      } on PlatformException {
        // A reply can be lost after native has claimed the tap. Only this
        // token can retrieve the same receipt without claiming another event.
      }
    }
    return null;
  }

  void _finish(bool accepted) {
    if (!_mayHaveReceipt) return;
    _mayHaveReceipt = false;
    unawaited(_control('finishPendingNotification', {'accepted': accepted}));
  }

  Future<void> _control(String method, [Map<String, Object>? extra]) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _channel.invokeMethod<void>(method, {..._arguments, ...?extra});
        return;
      } on MissingPluginException {
        return;
      } on PlatformException {
        // Both controls are idempotent and scoped to this registration.
      }
    }
  }

  void dispose() {
    if (!isCurrent) return;
    _current = null;
    _detached.complete();
    _channel.setMethodCallHandler(null);
    if (!_dispatching) _finish(false);
    if (_takeStarted && !_legacy) {
      unawaited(_control('endNotificationConsumer'));
    }
  }
}

class GakujoNotificationService {
  GakujoNotificationService({
    DateTime Function()? now,
    this.activeAccount,
    GakujoNotificationHistoryStore? historyStore,
  }) : _now = now ?? DateTime.now,
       _historyStore = historyStore ?? GakujoNotificationHistoryStore();

  final DateTime Function() _now;
  final String? Function()? activeAccount;
  final GakujoNotificationHistoryStore _historyStore;

  bool get _nativeHistory => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };

  static const _channel = MethodChannel(
    'net.yoshida.morebettergakujo/notifications',
  );

  NotificationTapConsumer? _legacyConsumer;

  String? targetUrl(String? url, {required bool debugAllowed}) {
    return deadlineNotificationTargetUrl(
      url,
      debugAllowed: debugAllowed,
    );
  }

  bool isForActiveAccount(String? account) =>
      account == null || account == activeAccount?.call();

  String? _nativeReminderAccount;

  bool get waitingForNativeReminderAccount =>
      _nativeHistory && activeAccount != null && activeAccount!() == null;

  Future<void> cancelOtherAccountsReminders() async {
    if (!_nativeHistory) return;
    final account = activeAccount?.call();
    if (account == null || account == _nativeReminderAccount) return;
    // Only the native booking store knows which owner survived a cold start.
    // Keep matching reservations intact when the assignment cache is unreadable.
    try {
      await _channel.invokeMethod<void>('cancelOtherAccountsReminders', {
        'account': account,
      });
      _nativeReminderAccount = account;
    } on MissingPluginException {
      // An unavailable bridge will fall back to in-app timers.
    } on PlatformException catch (error) {
      developer.log('Failed to reconcile reminder account: ${error.code}');
    }
  }

  void setDeadlineNotificationTappedHandler(
    DeadlineNotificationTappedCallback? handler,
  ) {
    _legacyConsumer?.dispose();
    _legacyConsumer = handler == null
        ? null
        : bindNotificationTaps((url) async {
            await handler(url);
            return true;
          });
  }

  NotificationTapConsumer bindNotificationTaps(
    FutureOr<bool> Function(String) handler, {
    BinaryMessenger? messenger,
  }) {
    final channel = MethodChannel(
      _channel.name,
      _channel.codec,
      messenger ?? _channel.binaryMessenger,
    );
    return NotificationTapConsumer._(channel, handler).._install();
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
    if (granted == null &&
        (_permissionRefused || permissionGranted.value == false)) {
      granted = false;
    }
    permissionGranted.value = granted;
    // Android reports "not enabled" before the first prompt too, so only a
    // grant may clear an earlier refusal; it never records one itself.
    if (granted == true) {
      _permissionRefused = false;
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
      account: entry.notificationAccount,
    );
  }

  Future<bool> notifyReminder(GakujoReminder reminder) {
    return _show(
      title: reminder.title,
      body: reminder.body,
      url: reminder.url,
      account: reminder.notificationAccount,
    );
  }

  Future<bool> _show({
    required String title,
    required String body,
    required String url,
    required String? account,
  }) async {
    if (!isForActiveAccount(account)) return false;
    final historyUrl = targetUrl(url, debugAllowed: kDebugMode);
    final nativeHistory = _nativeHistory;
    final historyGeneration = _historyStore.generation;
    bool posted;
    try {
      posted = await _channel.invokeMethod<bool>(
        'notifyDeadline',
        {
          'title': title,
          'body': body,
          'url': url,
          if (nativeHistory && account != null) ...{
            'historyAccount': account,
            'historyUrl': ?historyUrl,
          },
        },
      ) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
    if (posted && !nativeHistory && account != null) {
      try {
        await _historyStore.record(account, GakujoNotificationHistoryEntry(
          title: title.isEmpty ? '課題期限' : title,
          body: body.isEmpty ? '提出期限を検出しました' : body,
          postedAt: _now(),
          url: historyUrl,
        ), generation: historyGeneration);
      } on Object catch (error) {
        developer.log('Failed to save notification history: ${error.runtimeType}');
      }
    }
    return posted;
  }

  Future<List<GakujoNotificationHistoryEntry>> loadHistory(String account) async {
    if (account != activeAccount?.call()) return [];
    final entries = _nativeHistory
        ? GakujoNotificationHistoryEntry.newestFirst(
            await _channel.invokeListMethod<Object?>(
              'loadNotificationHistory',
              {'account': account},
            ) ?? [],
          )
        : await _historyStore.load(account);
    return account == activeAccount?.call() ? entries : [];
  }

  Future<void> clearHistory() async {
    if (_nativeHistory) {
      try {
        await _channel.invokeMethod<void>('clearNotificationHistory');
      } on MissingPluginException {
        // No local history on older bridges.
      }
    } else {
      await _historyStore.clear();
    }
  }

  Future<void> collectHistory() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    try {
      await _channel.invokeListMethod<Object?>('loadNotificationHistory');
    } on PlatformException {
      // The history dialog reports read failures on demand.
    } on MissingPluginException {
      // No native history bridge.
    }
  }

  final Map<int, ({GakujoReminder reminder, Timer timer})> _inAppReminders = {};
  Timer? _inAppReminderCheck;
  Future<void> Function(GakujoReminder)? _onInAppReminder;

  /// Books [reminders] with the OS, replacing earlier ones. Where the OS
  /// cannot book ahead (Windows and Linux), they fire from the app while open.
  /// Returns whether the OS booked them. [onInAppReminder] handles delivery
  /// when an in-app timer fires, so the coordinator can also record it.
  Future<bool> scheduleReminders(
    List<GakujoReminder> reminders, {
    Future<void> Function(GakujoReminder)? onInAppReminder,
  }) async {
    final account = activeAccount?.call();
    final eligible = reminders.where((reminder) =>
        isForActiveAccount(reminder.notificationAccount)).toList();
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
          'reminders': [
            for (final reminder in eligible)
              {
                ...reminder.toJson(),
                if (_nativeHistory && reminder.notificationAccount != null) ...{
                  'historyAccount': reminder.notificationAccount,
                  'historyUrl': ?targetUrl(reminder.url, debugAllowed: kDebugMode),
                },
              },
          ],
        },
      );
      if (booked == true) {
        _nativeReminderAccount = account;
        return true;
      }
    } on PlatformException {
      // Fall back to reminders from the running app.
    } on MissingPluginException {
      // Same.
    }
    final now = _now();
    for (final reminder in eligible) {
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
    // After sleep several offsets of one assignment are overdue together;
    // only the most urgent one is worth showing.
    final now = _now();
    final supersededBy = _inAppReminders.values.any(
      (other) =>
          other.reminder.assignmentId != null &&
          other.reminder.assignmentId == reminder.assignmentId &&
          other.reminder.at.isAfter(reminder.at) &&
          !other.reminder.at.isAfter(now),
    );
    if (supersededBy) {
      return;
    }
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
    required this._activityStore,
    required this._notificationService,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now;

  final GakujoActivityStore _activityStore;
  final GakujoNotificationService _notificationService;
  final DateTime Function() _now;
  Future<void> _pendingNotificationOperation = Future<void>.value();
  int _reminderGeneration = 0;
  int _bookedReminderGeneration = 0;
  int _queuedReminderSyncs = 0;
  bool _reminderNotificationsEnabled = false;
  Set<GakujoNotificationTopic> _reminderTopics = const {};
  GakujoNotificationPreferences _reminderPreferences =
      const GakujoNotificationPreferences();
  final _deferredReminders =
      <({int generation, Future<void> Function() notify})>[];

  Future<bool> _hasPermission(bool allowPermissionRequest) async {
    if (allowPermissionRequest) {
      return _notificationService.requestPermission();
    }
    // Older or unsupported runners fall back to requestPermission, which
    // answers silently once the student has decided.
    return await _notificationService.checkPermission() ??
        await _notificationService.requestPermission();
  }

  /// Rebooks cached assignments immediately when OS settings granted access.
  Future<void> onAppResumed({
    required bool notificationsEnabled,
    required Set<GakujoNotificationTopic> topics,
    required GakujoNotificationPreferences preferences,
  }) async {
    final generation = _reminderGeneration;
    final previouslyGranted = _notificationService.permissionGranted.value;
    final granted = await _notificationService.checkPermission();
    // A settings sync during the OS check supersedes the resume snapshot.
    final hasNewerSettings = generation != _reminderGeneration;
    final enabled = hasNewerSettings
        ? _reminderNotificationsEnabled
        : notificationsEnabled;
    if (granted == true && previouslyGranted != true && enabled) {
      await syncReminders(
        notificationsEnabled: enabled,
        topics: hasNewerSettings ? _reminderTopics : topics,
        preferences: hasNewerSettings ? _reminderPreferences : preferences,
        allowPermissionRequest: false,
      );
    }
  }

  /// Notifies new deadlines the student chose through [topics] and
  /// [messages]. When supplied, [currentSettings] also gates each send using
  /// the latest saved choices, including changes made while an await is pending.
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
    GakujoAppSettings Function()? currentSettings,
  }) {
    return _enqueueNotificationOperation(
      () => _notifyPendingDeadlines(
        notificationsEnabled: notificationsEnabled,
        allowPermissionRequest: allowPermissionRequest,
        topics: topics,
        messages: messages,
        preferences: preferences,
        messageExcludeKeywords: messageExcludeKeywords,
        currentSettings: currentSettings,
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
    required GakujoAppSettings Function()? currentSettings,
  }) async {
    if (!notificationsEnabled) {
      return;
    }
    bool stillAllowed(
      GakujoDeadlineEntry entry,
      GakujoAssignment? assignment,
      GakujoAppSettings? settings,
    ) => settings == null ||
        (settings.isFeatureEnabled(GakujoFeatureFlag.deadlineNotifications) &&
            isNotifiableDeadline(
              entry,
              topics: settings.notificationTopics,
              messages: settings.messageNotification,
              excludeKeywords: settings.messageExcludeKeywords,
            ) &&
            !(settings.notificationPreferences.skipSubmitted &&
                (assignment?.isSubmitted ?? false)));
    final deadlines = await _activityStore.loadDeadlines();
    late final Set<String> notifiedKeys;
    try {
      notifiedKeys = await _loadNotifiedKeys(strict: true);
    } on StateError {
      return;
    }
    final assignments = await _activityStore.loadAssignments();
    final seenIds = <String>{};
    final collidingIds = <String>{};
    for (final assignment in assignments) {
      if (!seenIds.add(assignment.notificationId)) {
        collidingIds.add(assignment.notificationId);
      }
    }
    final isWholeList = await _activityStore.assignmentsAreWholeList();
    final latestSettings = currentSettings?.call();
    final pending = <String, GakujoDeadlineEntry>{};
    for (final entry in deadlines) {
      if (pending.length >= 5) {
        break;
      }
      if (!_notificationService.isForActiveAccount(entry.notificationAccount) ||
          !isNotifiableDeadline(
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
      if (preferences.skipSubmitted && (assignment?.isSubmitted ?? false)) {
        continue;
      }
      // New choices may suppress this pass, but do not widen its original scope.
      if (!stillAllowed(entry, assignment, latestSettings)) {
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
      final assignment = assignmentForDeadline(entry, assignments);
      // Permission and the preceding native send can both outlive a settings save.
      if (!stillAllowed(entry, assignment, currentSettings?.call())) {
        continue;
      }
      if (assignment != null
          ? !assignment.dueAt.isAfter(_now())
          : _activityStore.isDeadlinePassed(entry, now: _now())) {
        continue;
      }
      if (await _notificationService.notifyDeadline(entry)) {
        notifiedNow.add(key);
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
    _reminderNotificationsEnabled = notificationsEnabled;
    _reminderTopics = Set.unmodifiable(topics);
    _reminderPreferences = preferences.copyWith(
      reminderOffsets: Set.unmodifiable(preferences.reminderOffsets),
    );
    final generation = ++_reminderGeneration;
    // Suppress timer callbacks until every queued sync has finished.
    _queuedReminderSyncs += 1;
    return _enqueueNotificationOperation(() async {
      try {
        bool needsAssignments() => _reminderNotificationsEnabled &&
            _reminderPreferences.reminderOffsets.isNotEmpty &&
            (_reminderTopics.contains(GakujoNotificationTopic.coursework) ||
                _reminderTopics.contains(GakujoNotificationTopic.survey));
        bool deferNativeReplacement() =>
            needsAssignments() && _notificationService.waitingForNativeReminderAccount;

        // Startup and authentication challenges say nothing about who owns
        // existing OS bookings. Explicit cancellation still goes through.
        if (deferNativeReplacement()) return;
        if (needsAssignments()) {
          await _notificationService.cancelOtherAccountsReminders();
          if (deferNativeReplacement()) return;
        }
        // With no eligible reminder topic or offset, no assignment data is
        // needed to cancel existing bookings.
        final shouldLoadAssignments = needsAssignments();
        var assignments = shouldLoadAssignments
            ? await _activityStore.loadAssignmentsIfAvailable()
            : const <GakujoAssignment>[];
        if (assignments == null) {
          return;
        }
        if (_reminderNotificationsEnabled) {
          await _loadNotifiedKeys();
        }
        // Topics or offsets may be enabled while history is loading.
        if (!shouldLoadAssignments && needsAssignments()) {
          assignments = await _activityStore.loadAssignmentsIfAvailable();
          if (assignments == null) {
            return;
          }
        }
        final availableAssignments = assignments;
        final lateReminders = <GakujoReminder>[];
        List<GakujoReminder> planCurrentReminders() {
          lateReminders.clear();
          return _reminderNotificationsEnabled
              ? planReminders(
                  assignments: availableAssignments.where((assignment) =>
                      _notificationService.isForActiveAccount(assignment.notificationAccount)),
                  topics: _reminderTopics,
                  preferences: _reminderPreferences,
                  now: _now(),
                  lateReminders: lateReminders,
                )
              : const <GakujoReminder>[];
        }
        var reminders = planCurrentReminders();
        if (reminders.isNotEmpty) {
          final granted = await _hasPermission(allowPermissionRequest);
          // Settings can be committed while the OS permission request waits.
          // Reuse the readable assignment snapshot even if a later sync cannot
          // read it, rather than booking the superseded policy or discarding it.
          reminders = planCurrentReminders();
          if (!granted &&
              (reminders.isNotEmpty || lateReminders.isNotEmpty)) {
            return;
          }
        }
        if (deferNativeReplacement()) return;
        // Only replacing bookings permanently invalidates their callbacks.
        _bookedReminderGeneration = generation;
        _deferredReminders.clear();
        final booksAhead = await _notificationService.scheduleReminders(
          reminders,
          onInAppReminder: (reminder) => _enqueueNotificationOperation(() async {
            if (generation != _bookedReminderGeneration) {
              return;
            }
            Future<void> notify() =>
                _notifyReminderWithLatestSettings(reminder);
            if (_queuedReminderSyncs > 0) {
              // The one-shot timer has fired; a skipped sync cannot rebook it.
              _deferredReminders.add((generation: generation, notify: notify));
              return;
            }
            await notify();
          }),
        );
        if (booksAhead || lateReminders.isEmpty) {
          return;
        }
        if (reminders.isEmpty && !await _hasPermission(allowPermissionRequest)) {
          return;
        }
        for (final reminder in lateReminders) {
          await _notifyReminderWithLatestSettings(reminder);
        }
      } finally {
        _queuedReminderSyncs -= 1;
        if (_queuedReminderSyncs == 0) {
          final deferred = _deferredReminders.toList();
          _deferredReminders.clear();
          for (final reminder in deferred) {
            if (reminder.generation == _bookedReminderGeneration) {
              try {
                await reminder.notify();
              } on Object catch (error, stackTrace) {
                developer.log(
                  'Failed to deliver deferred reminder',
                  name: 'MoreBetterGakujo',
                  error: error,
                  stackTrace: stackTrace,
                );
              }
            }
          }
        }
      }
    });
  }

  Future<void> _notifyReminderWithLatestSettings(
    GakujoReminder reminder,
  ) async {
    final assignments = reminder.assignmentId != null
        ? await _activityStore.loadAssignmentsIfAvailable()
        : null;
    late final Set<String> notifiedKeys;
    try {
      notifiedKeys = await _loadNotifiedKeys(strict: true);
    } on StateError {
      return;
    }
    // Settings can change while either storage read is in progress. Read them
    // together after the awaits, immediately before deciding whether to send.
    final preferences = _reminderPreferences;
    final topics = _reminderTopics;
    final dueAt = reminder.dueAt;
    if (!_reminderNotificationsEnabled ||
        preferences.reminderOffsets.isEmpty ||
        (dueAt != null &&
            !preferences.reminderOffsets.any(
              (offset) => dueAt.subtract(offset.before) == reminder.at,
            )) ||
        (reminder.topic != null && !topics.contains(reminder.topic))) {
      return;
    }
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
    if ((dueAt != null && !dueAt.isAfter(_now())) ||
        await _notificationService.notifyReminder(reminder)) {
      await _activityStore.addNotifiedDeadlineKeys([key]);
    }
  }

  Future<Set<String>> _loadNotifiedKeys({bool strict = false}) async {
    final keys = strict
        ? await _activityStore.loadNotifiedDeadlineKeysForNotifications()
        : await _activityStore.loadNotifiedDeadlineKeys();
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
    // Older builds saved kind|URL|title|preview for messages. Keep that
    // history effective when a detail scan changes the title or preview.
    return {
      ...keys,
      for (final key in keys)
        ?gakujoLegacyMessageNotificationKey(key),
    };
  }

  Future<T> _enqueueNotificationOperation<T>(
    Future<T> Function() operation,
  ) {
    final next = _pendingNotificationOperation.then((_) => operation());
    _pendingNotificationOperation = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }
}
