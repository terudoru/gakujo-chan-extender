part of 'gakujo_web_app.dart';

const _gakujoNativeDownloadsChannel = MethodChannel(
  'net.yoshida.morebettergakujo/downloads',
);

@visibleForTesting
DateTime gakujoCalendarDateAfterDays(DateTime value, int days) {
  return DateTime(value.year, value.month, value.day + days);
}

@visibleForTesting
String gakujoManualCalendarUidNamespace({
  required GakujoCalendarTermRange termRange,
}) {
  final academicYear = GakujoAcademicCalendar.academicYearFor(termRange.start);
  final termIdentity = _manualTermIdentityForRange(termRange);
  final termNumber = switch (termIdentity) {
    'first' => 1,
    'second' => 2,
    'third' => 3,
    _ => 4,
  };
  return 'niigata-$academicYear-第$termNumberターム';
}

@visibleForTesting
String gakujoLegacyManualIcsUidNamespace(GakujoCalendarTermRange termRange) {
  String stamp(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${twoDigits(value.month)}${twoDigits(value.day)}';
  }

  return 'manual-${stamp(termRange.start)}-${stamp(termRange.end)}';
}

String _manualTermIdentityForRange(GakujoCalendarTermRange range) {
  final start =
      DateTime.utc(range.start.year, range.start.month, range.start.day);
  final end = DateTime.utc(range.end.year, range.end.month, range.end.day);
  final midpoint = start.add(Duration(days: end.difference(start).inDays ~/ 2));
  return switch (midpoint.month) {
    4 || 5 => 'first',
    6 || 7 || 8 || 9 => 'second',
    10 || 11 => 'third',
    _ => 'fourth',
  };
}

@visibleForTesting
bool isAllowedGakujoGoogleCalendarUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == 'calendar.google.com';
}

@visibleForTesting
Set<int> initialGakujoAmbiguousCourseTermSelections(
  GakujoCalendarCourse course,
) {
  final normalized = course.termHint
      .replaceAll('１', '1')
      .replaceAll('２', '2')
      .replaceAll('３', '3')
      .replaceAll('４', '4');
  return {
    for (final match in RegExp(r'第\s*([1-4])\s*ターム').allMatches(normalized))
      if (int.tryParse(match.group(1) ?? '') case final term?) term,
  };
}

@visibleForTesting
List<GakujoCalendarCourse> applyGakujoAmbiguousCourseTermSelections(
  List<GakujoCalendarCourse> courses,
  Map<String, Set<int>> selections,
) {
  return [
    for (final course in courses)
      if (!GakujoCalendarExport.hasAmbiguousTermCode(course))
        course
      else if ((selections[GakujoCalendarExport.courseIdentityKey(course)] ??
              const <int>{})
          case final selectedTerms when selectedTerms.isNotEmpty)
        course.copyWith(
          termHint: (selectedTerms.toList()..sort())
              .map((term) => '第$termターム')
              .join(' '),
        ),
  ];
}

@visibleForTesting
Future<GakujoDownloadResult> exportGakujoCalendarWithNativePicker({
  required String ics,
  required String fileName,
}) async {
  final raw =
      await _gakujoNativeDownloadsChannel.invokeMethod<Map<dynamic, dynamic>>(
    'exportDownloadedFile',
    {
      'bytes': Uint8List.fromList(utf8.encode(ics)),
      'fileName': fileName,
      'mimeType': 'text/calendar',
    },
  );
  return GakujoDownloadResult.fromMap(raw);
}

@visibleForTesting
bool isBroadGakujoScheduleExtraction(GakujoCalendarExtraction extraction) {
  final weekdayCount = extraction.courses
      .where((course) => course.weekday >= 1 && course.weekday <= 7)
      .map((course) => course.weekday)
      .toSet()
      .length;
  final codedCourseCount = extraction.courses
      .where((course) => course.courseCode.trim().isNotEmpty)
      .length;
  return weekdayCount >= 3 && codedCourseCount >= 4;
}

@visibleForTesting
bool isUsableGakujoScheduleExtraction(
  GakujoCalendarExtraction extraction, {
  required bool isOfficial,
}) {
  if (extraction.courses.isEmpty) {
    return false;
  }
  return isOfficial || isBroadGakujoScheduleExtraction(extraction);
}

int _gakujoScheduleCourseEvidenceScore(
  GakujoCalendarExtraction extraction,
) {
  return extraction.courses.length +
      (isBroadGakujoScheduleExtraction(extraction) ? 10000 : 0);
}

@visibleForTesting
GakujoCalendarExtraction mergeGakujoScheduleExtractionEvidence(
  GakujoCalendarExtraction current,
  GakujoCalendarExtraction candidate,
) {
  final candidateWins = _gakujoScheduleCourseEvidenceScore(candidate) >
      _gakujoScheduleCourseEvidenceScore(current);
  final winner = candidateWins ? candidate : current;
  final other = candidateWins ? current : candidate;
  return GakujoCalendarExtraction(
    courses: winner.courses,
    termRange: winner.termRange ?? other.termRange,
  );
}

@visibleForTesting
Future<GakujoCalendarTermRange?> showGakujoCalendarTermRangeDialog({
  required BuildContext context,
  required String title,
  required String description,
  required String actionLabel,
  DateTime? initialDate,
}) async {
  return await showDialog<GakujoCalendarTermRange>(
    context: context,
    builder: (dialogContext) => _GakujoCalendarTermRangeDialog(
      title: title,
      description: description,
      actionLabel: actionLabel,
      initialDate: initialDate ?? DateTime.now(),
    ),
  );
}

class _GakujoCalendarTermRangeDialog extends StatefulWidget {
  const _GakujoCalendarTermRangeDialog({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.initialDate,
  });

  final String title;
  final String description;
  final String actionLabel;
  final DateTime initialDate;

  @override
  State<_GakujoCalendarTermRangeDialog> createState() =>
      _GakujoCalendarTermRangeDialogState();
}

class _GakujoCalendarTermRangeDialogState
    extends State<_GakujoCalendarTermRangeDialog> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final date = widget.initialDate;
    _startController = TextEditingController(
      text: '${date.year}/${date.month.toString().padLeft(2, '0')}/01',
    );
    _endController = TextEditingController();
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _submit() {
    final start = parseCalendarDate(_startController.text);
    final end = parseCalendarDate(_endController.text);
    if (start == null || end == null || end.isBefore(start)) {
      setState(() {
        _errorText = 'YYYY/MM/DD形式で、終了日が開始日以降になるように入力してください';
      });
      return;
    }
    Navigator.of(context).pop(
      GakujoCalendarTermRange(start: start, end: end),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.description),
          const SizedBox(height: 12),
          TextField(
            controller: _startController,
            decoration: const InputDecoration(
              labelText: '開始日',
              hintText: '2026/06/11',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.datetime,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _endController,
            decoration: const InputDecoration(
              labelText: '終了日',
              hintText: '2026/08/08',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.datetime,
            onSubmitted: (_) => _submit(),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

extension _GakujoWebAppCalendar on _GakujoWebAppState {
  Future<void> _exportCurrentScheduleToCalendar({
    GakujoCalendarImportSettings? importSettings,
  }) async {
    if (!_canRunPageScripts) {
      _showSnackBar('スケジュールページを読み込んでから使ってください');
      return;
    }

    final rawSettings = importSettings ?? _appSettings.calendarImportSettings;
    final settings = _effectiveCalendarImportSettings(rawSettings);
    if (settings.method == GakujoCalendarImportMethod.officialGoogle) {
      await _ensureSchedulePageForCalendarImport();
      await _openOfficialGoogleScheduleIntegration(
        showMissingMessage: true,
        successMessage: '本家Googleスケジュール連携を開きました',
      );
      return;
    }

    List<GakujoCalendarCourse>? fallbackCourses;
    GakujoCalendarTermRange? fallbackTermRange;
    String? fallbackUidNamespace;
    String? fallbackTermLabel;

    try {
      final preferredTerm = settings.termSource ==
              GakujoCalendarTermSource.officialAcademicCalendar
          ? await _resolveCalendarTerm(settings: settings)
          : null;
      final extraction = await _readCalendarScheduleForImport(
        preferredTermRange: preferredTerm?.termRange,
      );
      final extractedCourses = extraction.courses;
      if (extractedCourses.isEmpty) {
        _showSnackBar('本家Google連携から取り込める授業が見つかりませんでした。スケジュールページで再実行してください');
        return;
      }

      final resolvedTerm = preferredTerm ??
          await _resolveCalendarTerm(
            extraction: extraction,
            settings: settings,
          );
      if (resolvedTerm == null) {
        return;
      }
      final termRange = resolvedTerm.termRange;
      final uidNamespace = resolvedTerm.uidNamespace;
      final icsUidNamespace = resolvedTerm.termName == null
          ? gakujoLegacyManualIcsUidNamespace(termRange)
          : uidNamespace;
      final termLabel = resolvedTerm.label;
      final coursesWithResolvedAmbiguousTerms =
          await _resolveAmbiguousCalendarCourseTerms(extractedCourses);
      if (coursesWithResolvedAmbiguousTerms == null) {
        return;
      }
      final courses = GakujoCalendarExport.filterCoursesForTerm(
        courses: coursesWithResolvedAmbiguousTerms,
        termRange: termRange,
        termName: resolvedTerm.termName ?? '',
      );
      if (courses.isEmpty) {
        _showSnackBar(
            '${resolvedTerm.termName ?? '選択した期間'}に追加できる授業が見つかりませんでした');
        return;
      }
      fallbackCourses = courses;
      fallbackTermRange = termRange;
      fallbackUidNamespace = icsUidNamespace;
      fallbackTermLabel = termLabel;
      final shouldUseDirect =
          settings.method == GakujoCalendarImportMethod.deviceCalendar ||
              (settings.method == GakujoCalendarImportMethod.automatic &&
                  _calendarService.supportsDirectSync);
      if (shouldUseDirect && _calendarService.supportsDirectSync) {
        final events = GakujoCalendarEventBuilder.buildEvents(
          courses: courses,
          rangeStart: termRange.start,
          rangeEnd: termRange.end,
          noClassDates: termRange.noClassDates,
          uidNamespace: uidNamespace,
          termLabel: termLabel,
        );
        final result = await _calendarService.syncEvents(
          events: events,
          rangeStart: termRange.start,
          rangeEnd: termRange.end,
          calendarTitle: settings.effectiveCalendarTitle,
        );
        _showSnackBar(_calendarSyncMessage(result, resolvedTerm.termName));
        return;
      }
      if (settings.method == GakujoCalendarImportMethod.icsFile ||
          settings.method == GakujoCalendarImportMethod.deviceCalendar) {
        await _writeCalendarFallbackFile(
          courses: courses,
          termRange: termRange,
          uidNamespace: icsUidNamespace,
          termLabel: termLabel,
          calendarName: settings.effectiveCalendarTitle,
          reason: settings.method == GakujoCalendarImportMethod.deviceCalendar
              ? 'この環境ではOSカレンダー直接追加に未対応のため'
              : null,
        );
        return;
      }
      final openedOfficial = await _openOfficialGoogleScheduleIntegration(
        showMissingMessage: false,
        successMessage: 'この環境ではOSカレンダー直接追加に未対応のため、本家Googleスケジュール連携を開きました',
      );
      if (openedOfficial) {
        return;
      }
      await _writeCalendarFallbackFile(
        courses: courses,
        termRange: termRange,
        uidNamespace: icsUidNamespace,
        termLabel: termLabel,
        calendarName: settings.effectiveCalendarTitle,
        reason: null,
      );
    } on PlatformException catch (error) {
      if (isCancelledDownloadError(error)) {
        return;
      }
      if (_calendarService.supportsDirectSync &&
          (error.code == 'calendar_permission_denied' ||
              error.code == 'calendar_sync_failed')) {
        developer.log(
          'Falling back to iCalendar file after direct calendar sync failed',
          name: 'MoreBetterGakujo',
          error: error,
        );
        final courses = fallbackCourses;
        final termRange = fallbackTermRange;
        final uidNamespace = fallbackUidNamespace;
        final termLabel = fallbackTermLabel;
        if (termRange == null ||
            courses == null ||
            courses.isEmpty ||
            uidNamespace == null ||
            termLabel == null) {
          _showSnackBar('OSカレンダーに追加できませんでした: ${error.message ?? error.code}');
          return;
        }
        final reason = error.code == 'calendar_permission_denied'
            ? 'カレンダーへのアクセスが許可されていないため'
                '（システム設定＞プライバシーとセキュリティ＞カレンダーで許可できます）'
            : 'OSカレンダーに追加できなかったため';
        // The fallback runs inside this catch block, so its own exceptions
        // (notably the user cancelling the save dialog) would otherwise escape
        // unhandled. Swallow cancellation and report only real failures.
        try {
          await _writeCalendarFallbackFile(
            courses: courses,
            termRange: termRange,
            uidNamespace: uidNamespace,
            termLabel: termLabel,
            calendarName: settings.effectiveCalendarTitle,
            reason: reason,
          );
        } on PlatformException catch (fallbackError) {
          if (!isCancelledDownloadError(fallbackError)) {
            _showSnackBar('カレンダー用ファイルを作成できませんでした: '
                '${fallbackError.message ?? fallbackError.code}');
          }
        }
        return;
      }
      developer.log(
        'Failed to export calendar file',
        name: 'MoreBetterGakujo',
        error: error,
      );
      _showSnackBar('カレンダー用ファイルを作成できませんでした: ${error.message ?? error.code}');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to export calendar file',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('カレンダー用ファイルを作成できませんでした: $error');
    }
  }

  GakujoCalendarImportSettings _effectiveCalendarImportSettings(
    GakujoCalendarImportSettings settings,
  ) {
    if (!_calendarService.supportsDirectSync &&
        settings.method == GakujoCalendarImportMethod.deviceCalendar) {
      return settings.copyWith(method: GakujoCalendarImportMethod.icsFile);
    }
    if (_calendarService.supportsDirectSync &&
        settings.method == GakujoCalendarImportMethod.officialGoogle) {
      return settings.copyWith(
          method: GakujoCalendarImportMethod.deviceCalendar);
    }
    return settings;
  }

  List<GakujoCalendarImportMethod> _calendarImportMethodChoices() {
    if (!_calendarService.supportsDirectSync) {
      return GakujoCalendarImportMethod.values
          .where(
              (method) => method != GakujoCalendarImportMethod.deviceCalendar)
          .toList(growable: false);
    }
    return GakujoCalendarImportMethod.values
        .where((method) => method != GakujoCalendarImportMethod.officialGoogle)
        .toList(growable: false);
  }

  Future<_ResolvedCalendarTerm?> _resolveCalendarTerm({
    required GakujoCalendarImportSettings settings,
    GakujoCalendarExtraction? extraction,
    String manualTitle = 'ターム期間を入力',
    String manualDescription = 'ページからターム期間を読み取れませんでした。書き出す授業期間を入力してください。',
    String manualActionLabel = '書き出し',
  }) async {
    if (settings.termSource ==
        GakujoCalendarTermSource.officialAcademicCalendar) {
      final officialTerm = await _officialAcademicTermFor(
        DateTime.now(),
        target: settings.termTarget,
      );
      if (officialTerm != null) {
        final termRange = _calendarTermRangeForOfficial(
          officialTerm,
          includeNoClassDates: settings.includeNoClassDates,
        );
        return _ResolvedCalendarTerm(
          termRange: termRange,
          uidNamespace:
              'niigata-${officialTerm.academicYear}-${officialTerm.name}',
          label: '${officialTerm.academicYear}年度 ${officialTerm.name}',
          termName: officialTerm.name,
        );
      }
    }

    final pageRange = extraction?.termRange;
    final termRange = pageRange ??
        await _askCalendarTermRange(
          title: manualTitle,
          description: manualDescription,
          actionLabel: manualActionLabel,
        );
    if (termRange == null) {
      return null;
    }
    final effectiveRange = settings.includeNoClassDates
        ? termRange
        : GakujoCalendarTermRange(
            start: termRange.start,
            end: termRange.end,
            sourceText: termRange.sourceText,
          );
    return _ResolvedCalendarTerm(
      termRange: effectiveRange,
      uidNamespace: gakujoManualCalendarUidNamespace(
        termRange: termRange,
      ),
      label: _calendarRangeLabel(termRange),
      termName: null,
    );
  }

  GakujoCalendarTermRange _calendarTermRangeForOfficial(
    GakujoAcademicTerm officialTerm, {
    required bool includeNoClassDates,
  }) {
    return GakujoCalendarTermRange(
      start: officialTerm.start,
      end: officialTerm.end,
      sourceText:
          '${officialTerm.academicYear}年度 ${officialTerm.name} 公式授業暦 ${officialTerm.sourceUrl}',
      noClassDates: includeNoClassDates ? officialTerm.noClassDates : const [],
    );
  }

  Future<List<GakujoCalendarCourse>?> _resolveAmbiguousCalendarCourseTerms(
    List<GakujoCalendarCourse> courses,
  ) async {
    final uniqueAmbiguous = <String, GakujoCalendarCourse>{};
    for (final course in courses) {
      if (GakujoCalendarExport.hasAmbiguousTermCode(course)) {
        uniqueAmbiguous.putIfAbsent(
          GakujoCalendarExport.courseIdentityKey(course),
          () => course,
        );
      }
    }
    if (uniqueAmbiguous.isEmpty) {
      return courses;
    }

    final selections = await _askAmbiguousCalendarCourseTerms(
      uniqueAmbiguous.values.toList(growable: false),
    );
    if (selections == null) {
      return null;
    }
    return applyGakujoAmbiguousCourseTermSelections(courses, selections);
  }

  Future<Map<String, Set<int>>?> _askAmbiguousCalendarCourseTerms(
    List<GakujoCalendarCourse> courses,
  ) {
    if (!mounted) {
      return Future<Map<String, Set<int>>?>.value(null);
    }
    final selections = <String, Set<int>>{
      for (final course in courses)
        GakujoCalendarExport.courseIdentityKey(course):
            initialGakujoAmbiguousCourseTermSelections(course),
    };
    return showDialog<Map<String, Set<int>>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('期間不明の授業を確認'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '開講番号の3桁目が0の授業は、実施タームを判定できません。追加するタームを選んでください。',
                      ),
                      const SizedBox(height: 12),
                      for (final course in courses) ...[
                        _AmbiguousCalendarCourseTermSelector(
                          course: course,
                          selectedTerms:
                              selections[GakujoCalendarExport.courseIdentityKey(
                                    course,
                                  )] ??
                                  <int>{},
                          onChanged: (term, selected) {
                            final key =
                                GakujoCalendarExport.courseIdentityKey(course);
                            final next = {
                              ...(selections[key] ?? <int>{}),
                            };
                            if (selected) {
                              next.add(term);
                            } else {
                              next.remove(term);
                            }
                            selections[key] = next;
                            setDialogState(() {});
                          },
                        ),
                        const Divider(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop({}),
                  child: const Text('すべてスキップ'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    selections.map(
                      (key, value) => MapEntry(key, Set<int>.of(value)),
                    ),
                  ),
                  child: const Text('適用'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showScheduleIntegrationDialog() async {
    if (!_tryStartPageNavigationOperation()) {
      _showSnackBar('カレンダー連携を処理中です');
      return;
    }
    TextEditingController? controllerToDispose;
    try {
      final initialSettings = _effectiveCalendarImportSettings(
        _appSettings.calendarImportSettings,
      );
      final calendarTitleController = TextEditingController(
        text: initialSettings.effectiveCalendarTitle,
      );
      controllerToDispose = calendarTitleController;
      var selectedSettings = initialSettings;
      final result = await showDialog<_ScheduleIntegrationDialogResult>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              GakujoCalendarImportSettings currentSettings() {
                return selectedSettings.copyWith(
                  calendarTitle: calendarTitleController.text,
                );
              }

              void popWith(_ScheduleIntegrationAction action) {
                if (calendarTitleController.text.trim() ==
                    GakujoCalendarImportSettings.validationCalendarTitle) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('「More Better Gakujo 検証」は検証用の予約名です'),
                    ),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(
                  _ScheduleIntegrationDialogResult(
                    action: action,
                    settings: currentSettings(),
                  ),
                );
              }

              return AlertDialog(
                title: const Text('Googleスケジュール連携'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '追加する授業予定は学務のGoogle連携から取れたものだけを使い、ターム期間と授業なしの日はMore Better Gakujo側で判定します。',
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<GakujoCalendarImportMethod>(
                        initialValue: selectedSettings.method,
                        decoration: const InputDecoration(
                          labelText: '取り込み方法',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final method in _calendarImportMethodChoices())
                            DropdownMenuItem(
                              value: method,
                              child: Text(method.label),
                            ),
                        ],
                        onChanged: (method) {
                          if (method == null) {
                            return;
                          }
                          selectedSettings = selectedSettings.copyWith(
                            method: method,
                          );
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<GakujoCalendarTermSource>(
                        initialValue: selectedSettings.termSource,
                        decoration: const InputDecoration(
                          labelText: 'ターム期間の決め方',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final source in GakujoCalendarTermSource.values)
                            DropdownMenuItem(
                              value: source,
                              child: Text(source.label),
                            ),
                        ],
                        onChanged: (source) {
                          if (source == null) {
                            return;
                          }
                          selectedSettings = selectedSettings.copyWith(
                            termSource: source,
                          );
                          setDialogState(() {});
                        },
                      ),
                      if (selectedSettings.termSource ==
                          GakujoCalendarTermSource
                              .officialAcademicCalendar) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<GakujoCalendarTermTarget>(
                          initialValue: selectedSettings.termTarget,
                          decoration: const InputDecoration(
                            labelText: '追加するターム',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final target
                                in GakujoCalendarTermTarget.values)
                              DropdownMenuItem(
                                value: target,
                                child: Text(target.label),
                              ),
                          ],
                          onChanged: (target) {
                            if (target == null) {
                              return;
                            }
                            selectedSettings = selectedSettings.copyWith(
                              termTarget: target,
                            );
                            setDialogState(() {});
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('授業なしの日を除外する'),
                        subtitle: const Text('公式授業暦から取得できた休講日を予定生成から外します。'),
                        value: selectedSettings.includeNoClassDates,
                        onChanged: (value) {
                          selectedSettings = selectedSettings.copyWith(
                            includeNoClassDates: value ?? true,
                          );
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: calendarTitleController,
                        decoration: const InputDecoration(
                          labelText: '追加先カレンダー名',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (selectedSettings.method ==
                          GakujoCalendarImportMethod.officialGoogle) ...[
                        const SizedBox(height: 8),
                        Text(
                          '本家Google連携を開く場合、日付範囲は学務側の動作に従います。ターム自動判定を使う場合は「自動で選ぶ」か「OSカレンダーへ直接追加」を使ってください。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (!_calendarService.supportsDirectSync) ...[
                        const SizedBox(height: 8),
                        Text(
                          'WindowsではOSカレンダーへ直接書き込めないため、iCalendarファイルを書き出して既定のカレンダーアプリで開きます。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('閉じる'),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        popWith(_ScheduleIntegrationAction.validation),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('検証'),
                  ),
                  TextButton.icon(
                    onPressed: () => popWith(
                      _ScheduleIntegrationAction.deleteDeviceCalendar,
                    ),
                    icon: const Icon(Icons.event_busy_outlined),
                    label: const Text('追加済みを削除'),
                  ),
                  FilledButton.icon(
                    onPressed: () =>
                        popWith(_ScheduleIntegrationAction.syncCalendar),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('適用'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (result == null) {
        return;
      }
      await _saveCalendarImportSettings(result.settings);
      switch (result.action) {
        case _ScheduleIntegrationAction.syncCalendar:
          await _exportCurrentScheduleToCalendar(
            importSettings: result.settings,
          );
          return;
        case _ScheduleIntegrationAction.deleteDeviceCalendar:
          await _deleteAddedCalendarEvents(
            importSettings: result.settings,
          );
          return;
        case _ScheduleIntegrationAction.validation:
          await _showCalendarValidationDialog();
          return;
      }
    } finally {
      controllerToDispose?.dispose();
      await _finishPageNavigationOperation();
    }
  }

  Future<_OfficialGoogleScheduleIntegration>
      _runOfficialGoogleScheduleIntegrationScript({
    required bool activate,
  }) async {
    final result = await _controller.runJavaScriptReturningResult(
      GakujoCalendarExport.officialGoogleScheduleIntegrationScript(
        activate: activate,
      ),
    );
    return _OfficialGoogleScheduleIntegration.fromJson(
      _stringFromJavaScriptResult(result),
    );
  }

  Future<_OfficialGoogleScheduleIntegration>
      _runOfficialScheduleExportExecutionScript({
    required bool activate,
    GakujoCalendarTermRange? termRange,
  }) async {
    final result = await _controller.runJavaScriptReturningResult(
      GakujoCalendarExport.officialScheduleExportExecutionScript(
        activate: activate,
        startDate: termRange == null ? '' : _formatDate(termRange.start),
        endDate: termRange == null ? '' : _formatDate(termRange.end),
      ),
    );
    return _OfficialGoogleScheduleIntegration.fromJson(
      _stringFromJavaScriptResult(result),
    );
  }

  Future<_OfficialScheduleExportFetch> _runOfficialScheduleExportFetchScript({
    GakujoCalendarTermRange? termRange,
  }) async {
    final result = await _controller.runJavaScriptReturningResult(
      GakujoCalendarExport.officialScheduleExportFetchScript(
        startDate: termRange == null ? '' : _formatDate(termRange.start),
        endDate: termRange == null ? '' : _formatDate(termRange.end),
      ),
    );
    return _OfficialScheduleExportFetch.fromJson(
      _stringFromJavaScriptResult(result),
    );
  }

  Future<bool> _openOfficialGoogleScheduleIntegration({
    required bool showMissingMessage,
    String? successMessage,
    bool showSuccessMessage = true,
    bool waitForNavigation = false,
  }) async {
    if (!_canRunPageScripts) {
      if (showMissingMessage) {
        _showSnackBar('スケジュールページを読み込んでから使ってください');
      }
      return false;
    }

    try {
      final pageFinished = waitForNavigation
          ? _waitForNextPageFinished(timeout: const Duration(seconds: 6))
          : Future<String?>.value(null);
      final integration = await _runOfficialGoogleScheduleIntegrationScript(
        activate: true,
      );
      developer.log(
        'Official Google schedule integration status=${integration.status}',
        name: 'MoreBetterGakujo',
      );
      if (integration.status == 'url' && integration.url.isNotEmpty) {
        final uri = Uri.tryParse(integration.url);
        if (uri == null) {
          if (showMissingMessage) {
            _showSnackBar('本家Google連携のURLを開けませんでした');
          }
          return false;
        }
        if (isAllowedGakujoGoogleCalendarUrl(integration.url)) {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (waitForNavigation) {
            _nextPageFinishedCompleter = null;
          }
          if (!launched) {
            _showSnackBar('本家Google連携を外部ブラウザで開けませんでした');
          }
          return launched;
        }
        if (AllowedWebOrigins.canNavigate(
          integration.url,
          debugAllowed: _debugAllowed,
        )) {
          await _controller.loadUrl(integration.url);
          if (waitForNavigation) {
            await pageFinished;
          }
          return true;
        }
        if (showMissingMessage) {
          _showSnackBar('本家Google連携のURLは許可されていません');
        }
        if (waitForNavigation) {
          _nextPageFinishedCompleter = null;
        }
        return false;
      }
      if (integration.status == 'clicked') {
        if (waitForNavigation) {
          await pageFinished;
        }
        if (showSuccessMessage) {
          _showSnackBar(successMessage ?? '本家Googleスケジュール連携を開きました');
        }
        return true;
      }
      if (showMissingMessage) {
        _showSnackBar('本家Googleスケジュール連携が見つかりませんでした。スケジュールタブで実行してください');
      }
      if (waitForNavigation) {
        _nextPageFinishedCompleter = null;
      }
      return false;
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to open official Google schedule integration',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (showMissingMessage) {
        _showSnackBar('本家Googleスケジュール連携を開けませんでした: $error');
      }
      return false;
    }
  }

  String _calendarSyncMessage(GakujoCalendarSyncResult result, String? term) {
    final termText = term == null ? '' : ' ($term)';
    final removedText = result.removed > 0 ? '、古い予定${result.removed}件を更新' : '';
    return '${result.added}件の授業予定をカレンダーに追加$removedTextしました$termText';
  }

  Future<void> _deleteAddedCalendarEvents({
    GakujoCalendarImportSettings? importSettings,
  }) async {
    if (!_calendarService.supportsDirectSync) {
      _showSnackBar(
        'この環境ではOSカレンダーの一括削除に未対応です。取り込んだ予定はカレンダーアプリ側で削除してください',
      );
      return;
    }

    final settings = importSettings ?? _appSettings.calendarImportSettings;
    try {
      final resolvedTerm = await _resolveCalendarTerm(
        settings: settings,
        manualTitle: '削除するターム期間を入力',
        manualDescription: '削除対象にする期間を入力してください。',
        manualActionLabel: '次へ',
      );
      if (resolvedTerm == null) {
        return;
      }
      final termRange = resolvedTerm.termRange;

      final confirmed = await _confirmDeleteCalendarEvents(
        termRange: termRange,
        termName: resolvedTerm.termName,
        calendarTitle: settings.effectiveCalendarTitle,
      );
      if (confirmed != true) {
        return;
      }

      final result = await _calendarService.deleteAddedEvents(
        rangeStart: termRange.start,
        rangeEnd: termRange.end,
        calendarTitle: settings.effectiveCalendarTitle,
      );
      _showSnackBar(_calendarDeleteMessage(result, resolvedTerm.termName));
    } on PlatformException catch (error) {
      developer.log(
        'Failed to delete calendar events',
        name: 'MoreBetterGakujo',
        error: error,
      );
      _showSnackBar('カレンダー予定を削除できませんでした: ${error.message ?? error.code}');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to delete calendar events',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('カレンダー予定を削除できませんでした: $error');
    }
  }

  Future<bool?> _confirmDeleteCalendarEvents({
    required GakujoCalendarTermRange termRange,
    required String? termName,
    required String calendarTitle,
  }) {
    if (!mounted) {
      return Future<bool?>.value(false);
    }
    final termText = termName == null ? '' : ' ($termName)';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('カレンダー追加を取り消し'),
          content: Text(
            'More Better Gakujo が追加した授業予定だけを削除します。\n'
            '対象カレンダー: $calendarTitle\n'
            '対象期間: ${_formatDate(termRange.start)}〜${_formatDate(termRange.end)}$termText\n'
            '手動で作成した予定や他アプリの予定は削除しません。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('削除'),
            ),
          ],
        );
      },
    );
  }

  String _calendarDeleteMessage(
      GakujoCalendarDeleteResult result, String? term) {
    final termText = term == null ? '' : ' ($term)';
    if (result.removed == 0) {
      return '削除対象の授業予定はありませんでした$termText';
    }
    return '${result.removed}件の追加済み授業予定を削除しました$termText';
  }

  Future<void> _showCalendarValidationDialog() async {
    if (!mounted) {
      return;
    }
    final termRange = _calendarValidationTermRange();
    final events = _calendarValidationEvents(termRange);
    final action = await showDialog<_CalendarValidationAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('カレンダー連携を検証'),
          content: Text(
            '専用カレンダー「$_calendarValidationTitle」に検証用予定${events.length}件を追加します。\n'
            '対象期間: ${_formatDate(termRange.start)}〜${_formatDate(termRange.end)}\n'
            '通常の授業予定とは別のカレンダーで検証できます。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_CalendarValidationAction.delete),
              child: const Text('検証予定を削除'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_CalendarValidationAction.add),
              child: const Text('検証予定を追加'),
            ),
          ],
        );
      },
    );

    switch (action) {
      case _CalendarValidationAction.add:
        await _addCalendarValidationEvents(termRange);
        return;
      case _CalendarValidationAction.delete:
        await _deleteCalendarValidationEvents(termRange);
        return;
      case null:
        return;
    }
  }

  Future<void> _addCalendarValidationEvents(
    GakujoCalendarTermRange termRange,
  ) async {
    final courses = _calendarValidationCourses(termRange);
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: courses,
      rangeStart: termRange.start,
      rangeEnd: termRange.end,
      uidNamespace: _calendarValidationUidNamespace,
      termLabel: 'カレンダー連携検証',
    );
    if (_calendarService.supportsDirectSync) {
      try {
        final result = await _calendarService.syncEvents(
          events: events,
          rangeStart: termRange.start,
          rangeEnd: termRange.end,
          calendarTitle: _calendarValidationTitle,
        );
        _showSnackBar(
          '検証用カレンダーに${result.added}件の予定を追加しました'
          '${result.removed > 0 ? '、古い検証予定${result.removed}件を更新しました' : ''}',
        );
        return;
      } on PlatformException catch (error) {
        developer.log(
          'Failed to validate direct calendar sync',
          name: 'MoreBetterGakujo',
          error: error,
        );
        _showSnackBar('検証用予定を追加できませんでした: ${error.message ?? error.code}');
        return;
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to validate direct calendar sync',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
        _showSnackBar('検証用予定を追加できませんでした: $error');
        return;
      }
    }

    await _writeCalendarFallbackFile(
      courses: courses,
      termRange: termRange,
      uidNamespace: _calendarValidationUidNamespace,
      termLabel: 'カレンダー連携検証',
      calendarName: _calendarValidationTitle,
      reason: 'この環境ではOSカレンダー直接連携が未対応のため検証用ICSとして',
      fileName: 'more-better-gakujo-calendar-validation.ics',
    );
  }

  Future<void> _deleteCalendarValidationEvents(
    GakujoCalendarTermRange termRange,
  ) async {
    if (!_calendarService.supportsDirectSync) {
      _showSnackBar(
        'この環境ではOSカレンダーの直接削除に未対応です。取り込んだ検証用ICSはカレンダーアプリ側で削除してください',
      );
      return;
    }

    try {
      final result = await _calendarService.deleteAddedEvents(
        rangeStart: termRange.start,
        rangeEnd: termRange.end,
        calendarTitle: _calendarValidationTitle,
      );
      if (result.removed == 0) {
        _showSnackBar('削除対象の検証予定はありませんでした');
        return;
      }
      _showSnackBar('検証用カレンダーから${result.removed}件の予定を削除しました');
    } on PlatformException catch (error) {
      developer.log(
        'Failed to delete validation calendar events',
        name: 'MoreBetterGakujo',
        error: error,
      );
      _showSnackBar('検証用予定を削除できませんでした: ${error.message ?? error.code}');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to delete validation calendar events',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('検証用予定を削除できませんでした: $error');
    }
  }

  GakujoCalendarTermRange _calendarValidationTermRange() {
    final now = DateTime.now().toLocal();
    final start = gakujoCalendarDateAfterDays(now, 1);
    return GakujoCalendarTermRange(
      start: start,
      end: gakujoCalendarDateAfterDays(start, 1),
      sourceText: 'More Better Gakujo カレンダー検証',
    );
  }

  List<GakujoCalendarCourse> _calendarValidationCourses(
    GakujoCalendarTermRange termRange,
  ) {
    final nextDay = gakujoCalendarDateAfterDays(termRange.start, 1);
    return [
      GakujoCalendarCourse(
        title: '[検証] 1限カレンダー連携',
        weekday: termRange.start.weekday,
        period: 1,
        location: '検証教室 A',
        teacher: 'More Better Gakujo',
      ),
      GakujoCalendarCourse(
        title: '[検証] 2限カレンダー連携',
        weekday: termRange.start.weekday,
        period: 2,
        location: '検証教室 B',
        teacher: 'More Better Gakujo',
      ),
      GakujoCalendarCourse(
        title: '[検証] 翌日3限カレンダー連携',
        weekday: nextDay.weekday,
        period: 3,
        location: '検証教室 C',
        teacher: 'More Better Gakujo',
      ),
    ];
  }

  List<GakujoCalendarEvent> _calendarValidationEvents(
    GakujoCalendarTermRange termRange,
  ) {
    return GakujoCalendarEventBuilder.buildEvents(
      courses: _calendarValidationCourses(termRange),
      rangeStart: termRange.start,
      rangeEnd: termRange.end,
      uidNamespace: _calendarValidationUidNamespace,
      termLabel: 'カレンダー連携検証',
    );
  }

  Future<void> _writeCalendarFallbackFile({
    required List<GakujoCalendarCourse> courses,
    required GakujoCalendarTermRange termRange,
    required String uidNamespace,
    required String termLabel,
    required String calendarName,
    required String? reason,
    String fileName = 'more-better-gakujo-classes.ics',
  }) async {
    final ics = GakujoCalendarExport.buildIcs(
      courses: courses,
      rangeStart: termRange.start,
      rangeEnd: termRange.end,
      noClassDates: termRange.noClassDates,
      uidNamespace: uidNamespace,
      termLabel: termLabel,
      calendarName: calendarName,
    );
    final prefix = reason == null ? '' : '$reason、';
    if (Platform.isIOS) {
      final result = await exportGakujoCalendarWithNativePicker(
        ics: ics,
        fileName: fileName,
      );
      final location = result.location?.trim();
      final destination =
          location == null || location.isEmpty ? result.fileName : location;
      _showSnackBar(
        '$prefix${courses.length}件の授業を${_formatDate(termRange.start)}〜${_formatDate(termRange.end)}で書き出しました: $destination',
      );
      return;
    }
    final file = await _writeCalendarFile(ics, fileName: fileName);
    unawaited(_openSavedDownload(file.path));
    _showSnackBar(
      '$prefix${courses.length}件の授業を${_formatDate(termRange.start)}〜${_formatDate(termRange.end)}で書き出しました。カレンダーアプリで取り込んでください: ${file.path}',
    );
  }

  Future<GakujoCalendarExtraction> _readCalendarScheduleFromPage() async {
    final result = await _controller.runJavaScriptReturningResult(
      GakujoCalendarExport.extractionScript(),
    );
    final raw = _stringFromJavaScriptResult(result);
    final extraction = GakujoCalendarExport.extractionFromJson(raw);
    developer.log(
      'Calendar page extraction courses=${extraction.courses.length} '
      'hasTermRange=${extraction.termRange != null}',
      name: 'MoreBetterGakujo',
    );
    return extraction;
  }

  Future<GakujoCalendarExtraction> _readCalendarScheduleForImport({
    GakujoCalendarTermRange? preferredTermRange,
  }) async {
    var fallbackExtraction = await _readCalendarScheduleFromPage();

    final scheduleReady = await _ensureSchedulePageForCalendarImport(
      forceReload: true,
    );
    if (!scheduleReady) {
      final postLoadExtraction = await _waitForBetterScheduleExtraction(
        fallback: fallbackExtraction,
      );
      if (isUsableGakujoScheduleExtraction(
        postLoadExtraction,
        isOfficial: false,
      )) {
        return postLoadExtraction;
      }
      return const GakujoCalendarExtraction(courses: [], termRange: null);
    }

    await _activateScheduleMonthViewForCalendarImport();
    fallbackExtraction = await _readCalendarScheduleFromPage();

    final waitedExtraction = await _waitForScheduleCoursesOrOfficial(
      termRange: fallbackExtraction.termRange ?? preferredTermRange,
    );
    if (waitedExtraction != null && waitedExtraction.courses.isNotEmpty) {
      return waitedExtraction;
    }

    final officialExtraction = await _readOfficialGoogleScheduleAfterActivation(
      termRange: fallbackExtraction.termRange ?? preferredTermRange,
    );
    if (officialExtraction != null &&
        isUsableGakujoScheduleExtraction(
          officialExtraction,
          isOfficial: true,
        )) {
      return officialExtraction;
    }

    final timetableExtraction = await _readCourseTimetableForCalendarImport(
      preferredTermRange: fallbackExtraction.termRange ?? preferredTermRange,
    );
    if (isBroadGakujoScheduleExtraction(timetableExtraction)) {
      return timetableExtraction;
    }

    return isBroadGakujoScheduleExtraction(fallbackExtraction)
        ? fallbackExtraction
        : const GakujoCalendarExtraction(courses: [], termRange: null);
  }

  Future<void> _activateScheduleMonthViewForCalendarImport() async {
    if (!_canRunPageScripts) {
      return;
    }
    for (var attempt = 1; attempt <= 6; attempt += 1) {
      try {
        final result = await _controller.runJavaScriptReturningResult(
          GakujoCalendarExport.scheduleMonthViewActivationScript(),
        );
        final raw = _stringFromJavaScriptResult(result);
        if (raw.contains('"clicked"') || raw.contains('clicked')) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          return;
        }
        if (raw.contains('"ready"') || raw.contains('ready')) {
          return;
        }
      } catch (error, stackTrace) {
        developer.log(
          'Failed activating schedule month view',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<GakujoCalendarExtraction> _waitForBetterScheduleExtraction({
    required GakujoCalendarExtraction fallback,
  }) async {
    var best = fallback;
    for (var attempt = 1; attempt <= 5; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final extraction = await _readCalendarScheduleFromPage();
      best = mergeGakujoScheduleExtractionEvidence(best, extraction);
      // A term range alone does not prove that the course list is complete.
      if (isBroadGakujoScheduleExtraction(best)) {
        break;
      }
    }
    return best;
  }

  Future<GakujoCalendarExtraction?> _waitForScheduleCoursesOrOfficial({
    GakujoCalendarTermRange? termRange,
  }) async {
    for (var attempt = 1; attempt <= 12; attempt += 1) {
      await Future<void>.delayed(const Duration(seconds: 1));

      final extraction = await _readCalendarScheduleFromPage();

      final integration = await _runOfficialGoogleScheduleIntegrationScript(
        activate: false,
      );
      if (integration.url.isNotEmpty ||
          integration.status == 'clickable' ||
          integration.status == 'clicked') {
        final officialExtraction =
            await _readOfficialGoogleScheduleAfterActivation(
          termRange: extraction.termRange ?? termRange,
        );
        if (officialExtraction != null &&
            isUsableGakujoScheduleExtraction(
              officialExtraction,
              isOfficial: true,
            )) {
          return officialExtraction;
        }
        final timetableExtraction = await _readCourseTimetableForCalendarImport(
          preferredTermRange: extraction.termRange ?? termRange,
        );
        if (isBroadGakujoScheduleExtraction(timetableExtraction)) {
          return timetableExtraction;
        }
        if (isBroadGakujoScheduleExtraction(extraction)) {
          return extraction;
        }
      }
      if (isUsableGakujoScheduleExtraction(
        extraction,
        isOfficial: false,
      )) {
        return extraction;
      }
    }
    return null;
  }

  Future<GakujoCalendarExtraction> _readCourseTimetableForCalendarImport({
    GakujoCalendarTermRange? preferredTermRange,
  }) async {
    if (!_canRunPageScripts) {
      return const GakujoCalendarExtraction(courses: [], termRange: null);
    }

    try {
      final pageFinished = _waitForNextPageFinished(
        timeout: const Duration(seconds: 8),
      );
      final jumped = await _quickJumpTo(
        '履修',
        ownsPageNavigationOperation: true,
      );
      if (!jumped) {
        _nextPageFinishedCompleter = null;
        return const GakujoCalendarExtraction(courses: [], termRange: null);
      }
      await pageFinished;
      await Future<void>.delayed(const Duration(milliseconds: 900));

      var best = const GakujoCalendarExtraction(courses: [], termRange: null);
      for (var attempt = 1; attempt <= 6; attempt += 1) {
        final extraction = await _readCalendarScheduleFromPage();
        best = mergeGakujoScheduleExtractionEvidence(best, extraction);
        if (isBroadGakujoScheduleExtraction(best)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }

      if (best.courses.isEmpty) {
        return const GakujoCalendarExtraction(courses: [], termRange: null);
      }
      return GakujoCalendarExtraction(
        courses: best.courses,
        termRange: best.termRange ?? preferredTermRange,
      );
    } on Object catch (error, stackTrace) {
      _nextPageFinishedCompleter = null;
      developer.log(
        'Failed to read course timetable for calendar import',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return const GakujoCalendarExtraction(courses: [], termRange: null);
    }
  }

  Future<GakujoCalendarExtraction?> _readOfficialGoogleScheduleAfterActivation({
    GakujoCalendarTermRange? termRange,
  }) async {
    if (!_canRunPageScripts) {
      return null;
    }

    try {
      final pageFinished = _waitForNextPageFinished(
        timeout: const Duration(seconds: 6),
      );
      final integration = await _runOfficialGoogleScheduleIntegrationScript(
        activate: true,
      );
      developer.log(
        'Official Google schedule import status=${integration.status}',
        name: 'MoreBetterGakujo',
      );
      if (integration.status == 'url' && integration.url.isNotEmpty) {
        final isGoogleCalendarUrl =
            isAllowedGakujoGoogleCalendarUrl(integration.url);
        final courses = isGoogleCalendarUrl
            ? GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls(
                [integration.url],
              )
            : const <GakujoCalendarCourse>[];
        developer.log(
          'Official Google schedule URL courses=${courses.length}',
          name: 'MoreBetterGakujo',
        );
        if (courses.isNotEmpty) {
          _nextPageFinishedCompleter = null;
          return GakujoCalendarExtraction(
            courses: courses,
            termRange: termRange,
          );
        }

        final uri = Uri.tryParse(integration.url);
        if (uri != null &&
            !isGoogleCalendarUrl &&
            AllowedWebOrigins.canNavigate(
              integration.url,
              debugAllowed: _debugAllowed,
            )) {
          await _controller.loadUrl(integration.url);
          await pageFinished;
          await Future<void>.delayed(const Duration(milliseconds: 700));
          final extraction = await _readCalendarScheduleFromPage();
          return GakujoCalendarExtraction(
            courses: extraction.courses,
            termRange: extraction.termRange ?? termRange,
          );
        }

        _nextPageFinishedCompleter = null;
        return null;
      }

      if (integration.status == 'clicked') {
        await pageFinished;
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final currentUrl = await _controller.currentUrl();
        final courses =
            GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([
          if (currentUrl != null) currentUrl,
        ]);
        if (courses.isNotEmpty) {
          return GakujoCalendarExtraction(
            courses: courses,
            termRange: termRange,
          );
        }
        final extraction = await _readCalendarScheduleFromPage();
        final exportExtraction =
            await _readOfficialScheduleExportAfterExecution(
          termRange: extraction.termRange ?? termRange,
        );
        if (exportExtraction != null && exportExtraction.courses.isNotEmpty) {
          return exportExtraction;
        }
        return null;
      }

      _nextPageFinishedCompleter = null;
      return null;
    } on Object catch (error, stackTrace) {
      _nextPageFinishedCompleter = null;
      developer.log(
        'Failed to read official Google schedule integration',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<GakujoCalendarExtraction?> _readOfficialScheduleExportAfterExecution({
    GakujoCalendarTermRange? termRange,
  }) async {
    if (!_canRunPageScripts) {
      return null;
    }

    final inspect = await _runOfficialScheduleExportExecutionScript(
      activate: false,
      termRange: termRange,
    );
    if (inspect.status != 'clickable') {
      return null;
    }

    final fetched = await _runOfficialScheduleExportFetchScript(
      termRange: termRange,
    );
    final fetchedCourses =
        GakujoCalendarExport.coursesFromOfficialScheduleExportText(
      fetched.text,
    );
    final fetchedGoogleCourses =
        GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([
      fetched.text,
    ]);
    final fetchedUsableCourses =
        fetchedCourses.isNotEmpty ? fetchedCourses : fetchedGoogleCourses;
    if (fetchedUsableCourses.isNotEmpty) {
      return GakujoCalendarExtraction(
        courses: fetchedUsableCourses,
        termRange: termRange,
      );
    }

    final pageFinished = _waitForNextPageFinished(
      timeout: const Duration(seconds: 8),
    );
    final execution = await _runOfficialScheduleExportExecutionScript(
      activate: true,
      termRange: termRange,
    );
    if (execution.status != 'clicked') {
      _nextPageFinishedCompleter = null;
      return null;
    }

    await pageFinished;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final currentUrl = await _controller.currentUrl();
    final courses = GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([
      if (currentUrl != null) currentUrl,
    ]);
    if (courses.isNotEmpty) {
      return GakujoCalendarExtraction(
        courses: courses,
        termRange: termRange,
      );
    }

    final extraction = await _readCalendarScheduleFromPage();
    final integration = await _runOfficialGoogleScheduleIntegrationScript(
      activate: false,
    );
    if (integration.url.isNotEmpty) {
      return _readOfficialGoogleScheduleAfterActivation(
        termRange: extraction.termRange ?? termRange,
      );
    }
    return null;
  }

  Future<bool> _ensureSchedulePageForCalendarImport({
    bool forceReload = false,
  }) async {
    final currentUrl =
        ((await _controller.currentUrl()) ?? _currentPageUrl ?? '')
            .toLowerCase();
    if (!forceReload && currentUrl.contains('tabid=sch')) {
      return true;
    }

    final pageFinished = _waitForNextPageFinished(
      timeout: const Duration(seconds: 8),
    );
    await _loadAllowedPageUrl(
      _schedulePortalUrl,
      ownsPageNavigationOperation: true,
    );
    final finishedUrl = await pageFinished;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final afterUrl = ((await _controller.currentUrl()) ?? _currentPageUrl ?? '')
        .toLowerCase();
    return afterUrl.contains('tabid=sch') ||
        (finishedUrl ?? '').toLowerCase().contains('tabid=sch');
  }

  Future<GakujoAcademicTerm?> _officialAcademicTermFor(
    DateTime date, {
    GakujoCalendarTermTarget target = GakujoCalendarTermTarget.current,
  }) async {
    final academicYear = GakujoAcademicCalendar.academicYearFor(date);
    GakujoAcademicTerm? pickTerm(List<GakujoAcademicTerm> terms) {
      final termName = target.termName;
      if (termName == null) {
        return GakujoAcademicCalendar.termForDateIn(date, terms);
      }
      for (final term in terms) {
        if (term.academicYear == academicYear && term.name == termName) {
          return term;
        }
      }
      return null;
    }

    try {
      final terms = await _academicCalendarResolver
          .fetchTermsForAcademicYear(academicYear);
      final fetched = pickTerm(terms);
      if (fetched != null) {
        return GakujoAcademicCalendar.mergeWithBuiltInDetails(fetched);
      }
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to fetch official academic calendar PDF',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
    final fallback = pickTerm(GakujoAcademicCalendar.officialTerms);
    return fallback == null
        ? null
        : GakujoAcademicCalendar.mergeWithBuiltInDetails(fallback);
  }

  Future<GakujoCalendarTermRange?> _askCalendarTermRange({
    String title = 'ターム期間を入力',
    String description = 'ページからターム期間を読み取れませんでした。書き出す授業期間を入力してください。',
    String actionLabel = '書き出し',
  }) async {
    if (!mounted) {
      return null;
    }
    return showGakujoCalendarTermRangeDialog(
      context: context,
      title: title,
      description: description,
      actionLabel: actionLabel,
    );
  }

  Future<File> _writeCalendarFile(
    String ics, {
    String fileName = 'more-better-gakujo-classes.ics',
  }) async {
    try {
      final location = await getSaveLocation(
        initialDirectory: await _defaultExportDirectoryPath(),
        suggestedName: fileName,
        confirmButtonText: '保存',
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'iCalendar',
            extensions: ['ics'],
            mimeTypes: ['text/calendar'],
          ),
        ],
        canCreateDirectories: true,
      );
      if (location == null) {
        throw PlatformException(
          code: 'cancelled',
          message: '保存をキャンセルしました',
        );
      }
      final file = File(location.path);
      await file.writeAsString(ics, flush: true);
      return file;
    } on MissingPluginException {
      return _writeCalendarFileToDocuments(fileName: fileName, ics: ics);
    } on UnimplementedError {
      return _writeCalendarFileToDocuments(fileName: fileName, ics: ics);
    }
  }

  Future<File> _writeCalendarFileToDocuments({
    required String fileName,
    required String ics,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory =
        Directory(_joinLocalPath(documents.path, 'MoreBetterGakujoCalendar'));
    await directory.create(recursive: true);
    final file = File(_joinLocalPath(directory.path, fileName));
    await file.writeAsString(ics, flush: true);
    return file;
  }

  Future<String?> _defaultExportDirectoryPath() async {
    try {
      return (await getApplicationDocumentsDirectory()).path;
    } on Object {
      return null;
    }
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)}';
  }

  String _calendarRangeLabel(GakujoCalendarTermRange termRange) {
    return '${_formatDate(termRange.start)}〜${_formatDate(termRange.end)}';
  }
}
