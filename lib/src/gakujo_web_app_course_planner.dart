part of 'gakujo_web_app.dart';

enum _PlannerDestination { clipboard, registrationClipboard }

extension _CoursePlannerActions on _GakujoWebAppState {
  String? _confirmedPlannerStudentScope() {
    final id = _appSettings.savedLoginId;
    final account = _activeLoginAccount;
    if (!_loginIdentity.pageConfirmed || account == null) return null;
    return _plannerStudentScopes[account] ??
        (starSyncAccountHash(id) == account
            ? plannerStudentScope(id?.trim())
            : null);
  }

  void _retryPlannerSharing() {
    _plannerShareRetry ??= Timer(const Duration(minutes: 5), () {
      _plannerShareRetry = null;
      unawaited(_autoSharePlannerResults());
    });
  }

  Future<void> _loadPlannerSharing() async {
    try {
      final value = await SecureStorageFactory.create().read(
        key: 'planner_drive_sharing_enabled',
      );
      if (!mounted) return;
      _setPlannerSharingLoaded(value != 'false');
      unawaited(_autoSharePlannerResults());
    } on Object {
      developer.log('Planner sharing settings unavailable');
    }
  }

  Future<void> _autoSharePlannerResults() async {
    if (!_plannerShareLoaded ||
        !_plannerShareEnabled ||
        _plannerShareDeleting ||
        !mounted ||
        !_loginIdentity.pageConfirmed ||
        _activeLoginAccount == null ||
        _starSyncGoogleAuth.currentEmail == null) {
      return;
    }
    if (_plannerShareBusy) {
      _plannerSharePending = true;
      return;
    }
    _plannerShareBusy = true;
    final account = _activeLoginAccount!;
    final student = _confirmedPlannerStudentScope();
    final revision = _loginIdentity.revision;
    final epoch = _plannerShareEpoch;
    final navigation = _navigationRevision;
    final starts = _plannerNavigationStarts;
    final session = StarSyncGoogleAuthSession(
      _starSyncGoogleAuth,
      email: _starSyncGoogleAuth.currentEmail,
    );
    bool allowed() =>
        mounted &&
        _plannerShareEnabled &&
        !_plannerShareDeleting &&
        epoch == _plannerShareEpoch &&
        revision == _loginIdentity.revision &&
        account == _activeLoginAccount &&
        _loginIdentity.pageConfirmed &&
        session.generation == _starSyncGoogleAuth.generation &&
        session.email == _starSyncGoogleAuth.currentEmail;
    bool captureAllowed() =>
        allowed() &&
        navigation == _navigationRevision &&
        starts == _plannerNavigationStarts;
    void checkCurrent() {
      session.checkCurrent();
      if (!allowed()) throw const GoogleDriveAccountChanged();
    }

    StarSyncGoogleDriveTransport? transport;
    var retryCapture = false;
    try {
      final storage = SecureStorageFactory.create();
      final googleAccount = starSyncAccountHash(session.email);
      final key = 'planner_drive_capture_v3_${account}_$googleAccount';
      final last = await storage.read(key: key);
      final now = DateTime.now().toUtc();
      final attempt = _plannerShareAttempts[key];
      retryCapture = plannerCaptureDue(last, now);
      final background =
          retryCapture &&
          (attempt == null ||
              now.difference(attempt) >= const Duration(minutes: 5));
      if (!captureAllowed()) return;
      if (background) _plannerShareAttempts[key] = now;
      transport = StarSyncGoogleDriveTransport(
        accessToken: session.accessToken,
        automatic: true,
        checkCurrent: checkCurrent,
      );
      // Publish the account marker before a portal request can stall.
      if (student != null && background &&
          !await shareDrivePlannerTimetable(
            transport: transport,
            student: student,
            captured: const [],
            allowed: allowed,
            capturedAt: now,
          )) {
        return;
      }
      final displayed = await captureCoursePlannerHandoffs(
        _controller,
        captureAllowed,
        background: false,
      );
      final displayedTimetable =
          student != null && displayed.any((entry) => entry.$1 == CoursePlannerImportKind.registration)
          ? await CoursePlannerSource(_controller, captureAllowed).captureTimetable()
          : null;
      var fetched = const <(CoursePlannerImportKind, String)>[];
      var fetchedTimetable = const <Object?>[];
      var complete = false;
      if (background) {
        try {
          (fetched, fetchedTimetable, complete) =
              await fetchCoursePlannerCapture(_controller, captureAllowed);
        } on Object {
          // The displayed inquiry is still available while the portal retries.
        }
      }
      final timetable = {
        for (final term in [...fetchedTimetable, displayedTimetable])
          if (term is Map<String, dynamic>) (term['year'], term['semester']): term,
      }.values.toList();
      // Background registration combines multiple terms. The displayed page can
      // supply a missing kind without replacing the wider registration capture.
      final byKind = <CoursePlannerImportKind, String>{
        for (final (kind, token) in fetched) kind: token,
      };
      for (final (kind, token) in displayed) {
        final backgroundToken = byKind[kind];
        byKind[kind] = switch (kind) {
          CoursePlannerImportKind.profile =>
            reuseCoursePlannerAdmissionYear(token, backgroundToken),
          CoursePlannerImportKind.registration when backgroundToken != null =>
            mergeCoursePlannerRegistration(backgroundToken, token) ??
                backgroundToken,
          _ => token,
        };
      }
      final captured = [
        for (final kind in coursePlannerHandoffOrder)
          if (byKind[kind] case final token?) (kind, token),
      ];
      final capturedAt = DateTime.now().toUtc();
      if (!captureAllowed() || (captured.isEmpty && !background && timetable.isEmpty)) return;
      if (student != null && (timetable.isNotEmpty || !background) &&
          !await shareDrivePlannerTimetable(
            transport: transport,
            student: student,
            captured: timetable,
            allowed: allowed,
            capturedAt: capturedAt,
          )) {
        return;
      }
      final success = captured.isEmpty ||
          await shareDrivePlannerHandoffs(
            transport: transport,
            captured: captured,
            allowed: allowed,
            capturedAt: capturedAt,
            preserveAcademicHistory: student != null,
          );
      if (success && allowed()) {
        if (captured.isNotEmpty && (!background || complete)) {
          await transport.removePlannerDuplicates();
        }
        if (background && allowed() && complete) {
          await storage.write(key: key, value: plannerTimestamp(capturedAt));
          retryCapture = false;
          _plannerShareRetry?.cancel();
          _plannerShareRetry = null;
        }
      }
    } on Object catch (error) {
      retryCapture = error is! PlannerTimetableStudentMismatch;
      developer.log(
        'Planner inquiry sharing skipped',
        name: 'MoreBetterGakujo',
      );
    } finally {
      transport?.close();
      if (retryCapture && allowed()) _retryPlannerSharing();
      _plannerShareBusy = false;
      if (_plannerSharePending) {
        _plannerSharePending = false;
        unawaited(_autoSharePlannerResults());
      }
    }
  }

  Future<void> _deleteSharedPlannerResults() async {
    if (_plannerShareDeleting) return;
    if (_starSyncGoogleAuth.currentEmail == null) {
      if (mounted) _showSnackBar('削除できませんでした。通信を確認してください');
      return;
    }
    _plannerShareEpoch++;
    _plannerShareDeleting = true;
    _plannerSharePending = false;
    _plannerShareRetry?.cancel();
    _plannerShareRetry = null;
    StarSyncGoogleDriveTransport? transport;
    try {
      final session = StarSyncGoogleAuthSession(
        _starSyncGoogleAuth,
        email: _starSyncGoogleAuth.currentEmail,
      );
      transport = StarSyncGoogleDriveTransport(
        accessToken: session.accessToken,
        checkCurrent: session.checkCurrent,
      );
      await transport.delete(drivePlannerHandoffName);
      await transport.delete(drivePlannerTimetableName);
      if (mounted) {
        _showSnackBar('共有した照会結果を削除しました。自動共有がオンの場合は次の照会で再び共有されます');
      }
    } on Object {
      developer.log(
        'Planner shared inquiry deletion failed',
        name: 'MoreBetterGakujo',
      );
      if (mounted) _showSnackBar('削除できませんでした。通信を確認してください');
    } finally {
      transport?.close();
      _plannerShareDeleting = false;
    }
  }

  Future<void> _openCoursePlanner(_PlannerDestination destination) async {
    if (_plannerOpening) return;
    _plannerOpening = true;
    try {
      final nav = _navigationRevision;
      final starts = _plannerNavigationStarts;
      final revision = _loginIdentity.revision;
      final account = _activeLoginAccount;
      bool currentPage() =>
          mounted &&
          nav == _navigationRevision &&
          starts == _plannerNavigationStarts;
      bool currentStudent() =>
          currentPage() &&
          _loginIdentity.pageConfirmed &&
          account != null &&
          _activeLoginAccount == account &&
          revision == _loginIdentity.revision;
      String? url;
      try {
        url = await _controller.currentUrl();
      } on Object {
        // Failure to read the portal URL cannot authorize a capture.
      }
      if (!mounted) return;
      if (!currentPage()) url = null;
      CoursePlannerSource? source;
      CoursePlannerImportKind? choice;
      if (!currentStudent() ||
          !AllowedWebOrigins.canLoad(url, debugAllowed: false)) {
        _showSnackBar(
          destination == _PlannerDestination.clipboard
              ? '学務にログインしてから、もう一度お試しください。'
              : '学務にログインし、成績または履修の照会画面を開いてください。',
        );
        return;
      }
      if (destination == _PlannerDestination.clipboard) {
        var handoffs = await captureCoursePlannerHandoffs(
          _controller,
          currentStudent,
          displayedFallback: false,
        );
        if (!mounted) return;
        if (!currentStudent()) {
          _showSnackBar('学務の表示またはログイン状態が変わりました。もう一度お試しください。');
          return;
        }
        if (handoffs.isNotEmpty) {
          handoffs = await supplementCoursePlannerHandoffs(
            _controller,
            currentStudent,
            handoffs,
          );
          if (!mounted) return;
          if (!currentStudent()) {
            _showSnackBar('学務の表示またはログイン状態が変わりました。もう一度お試しください。');
            return;
          }
          if (handoffs.isNotEmpty) {
            await _copyCoursePlannerHandoffs(handoffs, currentStudent);
            return;
          }
        }
      }
      source = CoursePlannerSource(_controller, currentStudent);
      final kinds = await source.choices(includeProfile: true);
      if (!mounted) return;
      if (kinds.isEmpty || !currentStudent()) {
        _showSnackBar('「単位修得状況照会」または「履修登録・登録状況照会」で対象の表を表示してください。');
        return;
      }
      if (destination == _PlannerDestination.registrationClipboard) {
        if (!kinds.contains(CoursePlannerImportKind.registration)) {
          _showSnackBar('コピーできる履修登録状況が表示されていません。');
          return;
        }
        choice = CoursePlannerImportKind.registration;
      } else {
        choice = await showDialog<CoursePlannerImportKind>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: const Text('履修手帖に渡す内容'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('表示中の表からコピーする項目を選んでください。'),
              ),
              for (final kind in kinds)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, kind),
                  child: Text('${kind.label}をコピー'),
                ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('キャンセル'),
              ),
            ],
          ),
        );
      }
      if (choice == null || !mounted) return;
      if (!currentStudent()) {
        _showSnackBar('学務の表示またはログイン状態が変わりました。照会画面からやり直してください。');
        return;
      }
      await _copyCoursePlannerPacket(source, choice);
    } on Object {
      if (mounted) {
        _showSnackBar('学務の照会結果をコピーできませんでした。もう一度お試しください。');
      }
    } finally {
      _plannerOpening = false;
    }
  }

  Future<void> _copyCoursePlannerPacket(
    CoursePlannerSource source,
    CoursePlannerImportKind kind,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('${kind.label}を履修手帖用にコピー'),
        content: const Text('成績などの個人情報を含みます。履修手帖に貼り付けたら、ほかの場所には貼らないでください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('コピー'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    if (!source.stillCurrent()) {
      _showSnackBar('学務の表示またはログイン状態が変わりました。照会画面からやり直してください。');
      return;
    }
    final packet = await source.capture(kind);
    if (!mounted) return;
    final token = encodeCoursePlannerHandoff(packet, kind);
    if (token == null || !source.stillCurrent()) {
      _showSnackBar('表示中の照会結果を読み取れませんでした。画面を確認してください。');
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) {
      _showCoursePlannerCopied(
        'コピーしました。履修手帖の設定 →「More Better Gakujo から貼り付け」で貼り付けてください。',
      );
    }
  }

  Future<void> _copyCoursePlannerHandoffs(
    List<(CoursePlannerImportKind, String)> handoffs,
    bool Function() stillCurrent,
  ) async {
    final labels = handoffs.map((handoff) => handoff.$1.label).join('、');
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('$labelsを履修手帖用にコピー'),
        content: const Text('成績などの個人情報を含みます。履修手帖に貼り付けたら、ほかの場所には貼らないでください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('コピー'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    if (!stillCurrent()) {
      _showSnackBar('学務の表示またはログイン状態が変わりました。もう一度お試しください。');
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: joinCoursePlannerHandoffs(handoffs)),
    );
    if (mounted) {
      _showCoursePlannerCopied(
        '${handoffs.length}件をコピーしました。履修手帖の設定 →「More Better Gakujo から貼り付け」で貼り付けてください。',
      );
    }
  }

  void _showCoursePlannerCopied(String message) {
    _showSnackBar(
      message,
      action: SnackBarAction(
        label: '履修手帖を開く',
        onPressed: () =>
            unawaited(_handleToolbarAction(_ToolbarAction.coursePlanner)),
      ),
    );
  }
}
