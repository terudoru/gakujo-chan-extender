part of 'gakujo_web_app.dart';

enum _ToolbarAction {
  addFavorite,
  copyUrl,
  openExternal,
  reload,
}

enum GakujoQuickJumpDestination {
  grades,
  reports,
  messages,
  downloads,
  syllabus,
  schedule,
}

enum _CalendarValidationAction { add, delete }

enum _SecureStorageRecoveryAction { retry, reset, continueWithoutStorage }

enum _ScheduleIntegrationAction {
  syncCalendar,
  deleteDeviceCalendar,
  validation,
}

class _PageTextSnapshot {
  const _PageTextSnapshot({
    required this.title,
    required this.text,
    required this.messageItems,
  });

  final String title;
  final String text;
  final List<_MessageActivityCandidate> messageItems;
}

class _MessageActivityCandidate {
  const _MessageActivityCandidate({
    required this.title,
    required this.url,
    required this.text,
  });

  final String title;
  final String url;
  final String text;

  factory _MessageActivityCandidate.fromJson(Map<dynamic, dynamic> json) {
    return _MessageActivityCandidate(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
    );
  }
}

class _ActivityScanResult {
  const _ActivityScanResult({
    required this.updateCount,
    required this.deadlineCount,
  });

  final int updateCount;
  final int deadlineCount;
}

class _ResolvedCalendarTerm {
  const _ResolvedCalendarTerm({
    required this.termRange,
    required this.uidNamespace,
    required this.label,
    required this.termName,
  });

  final GakujoCalendarTermRange termRange;
  final String uidNamespace;
  final String label;
  final String? termName;
}

class _ScheduleIntegrationDialogResult {
  const _ScheduleIntegrationDialogResult({
    required this.action,
    required this.settings,
  });

  final _ScheduleIntegrationAction action;
  final GakujoCalendarImportSettings settings;
}

class _OfficialGoogleScheduleIntegration {
  const _OfficialGoogleScheduleIntegration({
    required this.status,
    required this.url,
    required this.label,
    required this.diagnostics,
  });

  const _OfficialGoogleScheduleIntegration.notFound()
      : status = 'not_found',
        url = '',
        label = '',
        diagnostics = const {};

  final String status;
  final String url;
  final String label;
  final Map<String, Object?> diagnostics;

  factory _OfficialGoogleScheduleIntegration.fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<dynamic, dynamic>) {
        final rawDiagnostics = decoded['diagnostics'];
        return _OfficialGoogleScheduleIntegration(
          status: decoded['status']?.toString() ?? 'not_found',
          url: decoded['url']?.toString() ?? '',
          label: decoded['label']?.toString() ?? '',
          diagnostics: rawDiagnostics is Map<dynamic, dynamic>
              ? rawDiagnostics.map(
                  (key, value) => MapEntry(key.toString(), value),
                )
              : const {},
        );
      }
    } on FormatException {
      // Fall through to not_found.
    }
    return const _OfficialGoogleScheduleIntegration.notFound();
  }
}

class _OfficialScheduleExportFetch {
  const _OfficialScheduleExportFetch({
    required this.status,
    required this.httpStatus,
    required this.url,
    required this.contentType,
    required this.text,
    required this.diagnostics,
  });

  const _OfficialScheduleExportFetch.notFound()
      : status = 'not_found',
        httpStatus = 0,
        url = '',
        contentType = '',
        text = '',
        diagnostics = const {};

  final String status;
  final int httpStatus;
  final String url;
  final String contentType;
  final String text;
  final Map<String, Object?> diagnostics;

  int get textLength => text.length;

  factory _OfficialScheduleExportFetch.fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<dynamic, dynamic>) {
        final rawDiagnostics = decoded['diagnostics'];
        return _OfficialScheduleExportFetch(
          status: decoded['status']?.toString() ?? 'not_found',
          httpStatus:
              int.tryParse(decoded['httpStatus']?.toString() ?? '') ?? 0,
          url: decoded['url']?.toString() ?? '',
          contentType: decoded['contentType']?.toString() ?? '',
          text: decoded['text']?.toString() ?? '',
          diagnostics: rawDiagnostics is Map<dynamic, dynamic>
              ? rawDiagnostics.map(
                  (key, value) => MapEntry(key.toString(), value),
                )
              : const {},
        );
      }
    } on FormatException {
      // Fall through to not_found.
    }
    return const _OfficialScheduleExportFetch.notFound();
  }
}
