part of 'gakujo_web_app.dart';

enum _RegistrationPhase {
  grid,
  semester,
  adding,
  searching,
  results,
  back,
  reviewed,
}

class _RegistrationPage {
  _RegistrationPage(this.url, this.data);

  final String url;
  final Map<String, dynamic> data;

  String get kind => data['page'] as String;
  num get documentId => data['documentId'] as num;
  int? get year => data['year'] as int?;
  int? get semester => data['semester'] as int?;
  String get message => data['message'] as String? ?? '';
  Set<String> get registered =>
      (data['registered'] as List? ?? []).cast<String>().toSet();
  Map<int, Set<String>> get slots => {
    for (final entry in (data['slots'] as Map<String, dynamic>? ?? {}).entries)
      int.parse(entry.key): (entry.value as List).cast<String>().toSet(),
  };

  bool sameDocument(_RegistrationPage other) =>
      url == other.url && documentId == other.documentId;
}

class _RegistrationSession {
  _RegistrationSession(this.run, this.page, this.course, this.navigation);

  final RegistrationRun run;
  _RegistrationPage page;
  RegistrationCourse course;
  int navigation;
  _RegistrationPhase phase = _RegistrationPhase.grid;
  String status = '登録画面を確認しています…';
  String? choiceTicket;
  bool userChose = false;
  bool busy = false;
  DateTime deadline = DateTime.now();
  Timer? timer;
}

bool _isRegistrationServlet(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'gakujo.iess.niigata-u.ac.jp' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      RegExp(r'^/campusweb/(?:[^/]+/)*campussquare\.do(?:;jsessionid=[^/;]+)?$')
          .hasMatch(uri.path);
}

extension _RegistrationAssistActions on _GakujoWebAppState {
  bool get _hasRegistrationIdentity =>
      _activeLoginAccount != null && _loginIdentity.pageConfirmed;

  Future<_RegistrationPage?> _inspectRegistration({String? code}) async {
    final revision = _navigationRevision;
    final starts = _plannerNavigationStarts;
    final url = await _controller.currentUrl();
    if (!mounted ||
        !_hasRegistrationIdentity ||
        !_isRegistrationServlet(url) ||
        revision != _navigationRevision ||
        starts != _plannerNavigationStarts) {
      return null;
    }
    final result = await _controller.runJavaScriptReturningResult(
      registrationAssistJs({'command': 'inspect', 'href': url, 'code': code}),
    );
    if (!mounted ||
        revision != _navigationRevision ||
        starts != _plannerNavigationStarts) {
      return null;
    }
    final data = jsonDecode(_stringFromJavaScriptResult(result));
    if (data is! Map<String, dynamic> ||
        !const {'grid', 'condition', 'results'}.contains(data['page']) ||
        data['documentId'] is! num) {
      return null;
    }
    return _RegistrationPage(url!, data);
  }

  Future<void> _refreshRegistrationAvailability() async {
    if (_registrationSession != null ||
        !_hasRegistrationIdentity ||
        !_isRegistrationServlet(_currentPageUrl)) {
      return;
    }
    final revision = _navigationRevision;
    final account = _activeLoginAccount;
    final identityRevision = _loginIdentity.revision;
    try {
      final page = await _inspectRegistration();
      if (mounted &&
          revision == _navigationRevision &&
          _hasRegistrationIdentity &&
          account == _activeLoginAccount &&
          identityRevision == _loginIdentity.revision) {
        _setRegistrationAvailable(page?.kind == 'grid');
      }
    } on Object {
      // An unavailable WebView cannot provide a registration grid.
    }
  }

  Future<void> _openRegistrationAssist() async {
    if (_registrationOpening ||
        _registrationSession != null ||
        !_hasRegistrationIdentity) {
      return;
    }
    _registrationOpening = true;
    final revision = _navigationRevision;
    final starts = _plannerNavigationStarts;
    final account = _activeLoginAccount!;
    final identityRevision = _loginIdentity.revision;
    bool stillOwned() =>
        mounted &&
        revision == _navigationRevision &&
        starts == _plannerNavigationStarts &&
        _hasRegistrationIdentity &&
        account == _activeLoginAccount &&
        identityRevision == _loginIdentity.revision;
    try {
      final initial = await _inspectRegistration();
      if (!mounted || !stillOwned()) return;
      if (initial?.kind != 'grid') {
        _showSnackBar('学務で「履修登録・登録状況照会」の時間割を表示してください。');
        return;
      }
      final plan = await showDialog<RegistrationHandoff>(
        context: context,
        builder: (_) => const _RegistrationPasteDialog(),
      );
      if (plan == null || !stillOwned()) return;
      final grid = await _inspectRegistration();
      if (grid == null ||
          grid.kind != 'grid' ||
          !grid.sameDocument(initial!) ||
          !stillOwned()) {
        return;
      }
      if (grid.year != plan.year) {
        _showSnackBar('引き継ぎの年度と学務の時間割の年度が一致しません。');
        return;
      }
      final groups = <RegistrationDisposition, List<RegistrationCourse>>{
        for (final disposition in RegistrationDisposition.values)
          disposition: [],
      };
      final outcomes = <String, RegistrationOutcome>{};
      for (final course in plan.courses) {
        final disposition = classifyRegistrationCourse(
          course,
          grid.registered,
          grid.slots,
        );
        groups[disposition]!.add(course);
        if (disposition == RegistrationDisposition.registered) {
          outcomes[course.code] = RegistrationOutcome.registered;
        } else if (disposition == RegistrationDisposition.manual) {
          outcomes[course.code] = RegistrationOutcome.manual;
        }
      }
      final run = RegistrationRun(account, identityRevision, plan, outcomes);
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('${plan.year}年度の履修登録'),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(registrationSafetyText),
              for (final (disposition, label) in const [
                (RegistrationDisposition.registered, '登録済み'),
                (RegistrationDisposition.guided, '入力する'),
                (RegistrationDisposition.manual, '手動で登録'),
                (RegistrationDisposition.checkOtherSemester, '入力する（学期を開いて確認）'),
              ]) ...[
                const SizedBox(height: 12),
                Text(
                  '$label ${groups[disposition]!.length}件',
                  style: Theme.of(dialog).textTheme.titleSmall,
                ),
                for (final course in groups[disposition]!) Text(course.label),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('閉じる'),
            ),
            if (run.next != null)
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('入力を開始'),
              ),
          ],
        ),
      );
      if (accepted != true || !stillOwned()) return;
      final session = _RegistrationSession(run, grid, run.next!, revision);
      _setRegistrationSession(session, summary: null);
      session.timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        unawaited(_stepRegistration(session));
      });
      await _stepRegistration(session);
    } on Object {
      if (mounted) _showSnackBar('学務の登録画面を確認できませんでした。');
    } finally {
      _registrationOpening = false;
    }
  }

  bool _ownsRegistration(_RegistrationSession session) =>
      mounted &&
      identical(session, _registrationSession) &&
      session.run.checkIdentity(
        _activeLoginAccount,
        _loginIdentity.revision,
        confirmed: _loginIdentity.pageConfirmed,
      );

  void _finishRegistration(String reason) {
    final session = _registrationSession;
    if (session == null || !mounted) return;
    final ticket = session.choiceTicket;
    session.run.ended = true;
    session.timer?.cancel();
    _setRegistrationSession(null, summary: '$reason\n${session.run.summary}');
    if (ticket != null &&
        _hasRegistrationIdentity &&
        session.run.account == _activeLoginAccount &&
        session.run.identityRevision == _loginIdentity.revision) {
      unawaited(
        _registrationCommand(
          session.page,
          'clear',
          ticket: ticket,
        ).then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  Future<bool> _registrationCommand(
    _RegistrationPage page,
    String command, {
    RegistrationCourse? course,
    int? year,
    String? ticket,
  }) async {
    final result = await _controller.runJavaScriptReturningResult(
      registrationAssistJs({
        'command': command,
        'href': page.url,
        'documentId': page.documentId,
        'code': course?.code,
        'semester': course?.semester,
        'slot': course?.slots.firstOrNull,
        'year': year,
        'ticket': ticket,
      }),
    );
    return _stringFromJavaScriptResult(result) == 'true';
  }

  Future<void> _advanceRegistrationPage(
    _RegistrationSession session,
    _RegistrationPhase phase,
    String command,
  ) async {
    if (!_ownsRegistration(session)) return;
    session.phase = phase;
    session.deadline = DateTime.now().add(const Duration(seconds: 25));
    session.status = '${session.course.label} の画面を開いています…';
    _redrawRegistration();
    final moved = await _registrationCommand(
      session.page,
      command,
      course: session.course,
      year: session.run.plan.year,
    );
    if (!moved && _ownsRegistration(session)) {
      _finishRegistration('学務の操作ボタンを確認できませんでした。');
    }
  }

  void _reviewRegistration(
    _RegistrationSession session,
    RegistrationOutcome outcome,
    String status,
  ) {
    session.run.outcomes[session.course.code] = outcome;
    session.choiceTicket = null;
    session.phase = _RegistrationPhase.reviewed;
    session.status = '${session.course.label} — $status';
    _redrawRegistration();
  }

  void _registrationChoice(String ticket) {
    final session = _registrationSession;
    if (session != null &&
        _ownsRegistration(session) &&
        session.phase == _RegistrationPhase.results &&
        session.choiceTicket == ticket) {
      session.userChose = true;
      _redrawRegistration();
    }
  }

  Future<void> _stepRegistration(_RegistrationSession session) async {
    if (!mounted || !identical(_registrationSession, session) || session.busy) {
      return;
    }
    if (!_ownsRegistration(session)) {
      _finishRegistration('ログイン状態が変わったため終了しました。');
      return;
    }
    session.busy = true;
    final revision = _navigationRevision;
    final starts = _plannerNavigationStarts;
    try {
      if (_pendingPageFinishedNavigationRevision == null) {
        final page = await _inspectRegistration(code: session.course.code);
        if (!_ownsRegistration(session) ||
            revision != _navigationRevision ||
            starts != _plannerNavigationStarts) {
          return;
        }
        if (page == null ||
            (page.kind == 'grid' && page.year != session.run.plan.year)) {
          _finishRegistration('履修登録画面が変わったため終了しました。');
          return;
        }
        await _handleRegistrationPage(session, page);
      }
      if (_ownsRegistration(session) &&
          const {
            _RegistrationPhase.semester,
            _RegistrationPhase.adding,
            _RegistrationPhase.searching,
            _RegistrationPhase.back,
          }.contains(session.phase) &&
          DateTime.now().isAfter(session.deadline)) {
        _finishRegistration('学務の画面切り替えを確認できませんでした。');
      }
    } on Object {
      if (_ownsRegistration(session)) _finishRegistration('学務の画面を確認できませんでした。');
    } finally {
      session.busy = false;
    }
  }

  Future<void> _handleRegistrationPage(
    _RegistrationSession session,
    _RegistrationPage page,
  ) async {
    final previous = session.page;
    final samePage =
        previous.sameDocument(page) &&
        session.navigation == _navigationRevision;
    final course = session.course;
    void adopt() {
      session.page = page;
      session.navigation = _navigationRevision;
    }

    switch (session.phase) {
      case _RegistrationPhase.semester:
        if (page.kind == 'grid' && page.semester == course.semester) {
          session.phase = _RegistrationPhase.grid;
          adopt();
          return;
        }
      case _RegistrationPhase.grid:
        if (!samePage ||
            page.kind != 'grid' ||
            page.semester != previous.semester) {
          break;
        }
        adopt();
        final disposition = classifyRegistrationCourse(
          course,
          page.registered,
          page.slots,
        );
        if (disposition == RegistrationDisposition.registered) {
          _reviewRegistration(session, RegistrationOutcome.registered, '登録済み');
        } else if (page.semester != course.semester) {
          await _advanceRegistrationPage(
            session,
            _RegistrationPhase.semester,
            'semester',
          );
        } else if (disposition == RegistrationDisposition.manual) {
          _reviewRegistration(
            session,
            RegistrationOutcome.manual,
            '「追加」が表示されていないため手動で登録',
          );
        } else {
          await _advanceRegistrationPage(
            session,
            _RegistrationPhase.adding,
            'add',
          );
        }
        return;
      case _RegistrationPhase.adding:
        if (page.kind == 'condition') {
          adopt();
          await _advanceRegistrationPage(
            session,
            _RegistrationPhase.searching,
            'search',
          );
          return;
        }
      case _RegistrationPhase.searching:
        if (page.kind == 'results') {
          adopt();
          session.phase = _RegistrationPhase.results;
          final count = page.data['count'];
          session.status = switch (count) {
            0 => '${course.label} — 開講番号が一致する科目はありません。',
            1 => '${course.label} — 学務の「選択」リンクを確認できません。',
            _ => '${course.label} — 開講番号が一致する科目が複数あります。',
          };
          if (page.data['selectable'] == true) {
            final random = Random.secure();
            final ticket = base64Url.encode(
              List.generate(18, (_) => random.nextInt(256)),
            );
            session.choiceTicket = ticket;
            if (await _registrationCommand(
                  page,
                  'highlight',
                  course: course,
                  ticket: ticket,
                ) &&
                _ownsRegistration(session)) {
              session.status =
                  '${course.label} を確認し、学務の「選択」を押してください（優先度は変更していません）';
            }
          }
          if (_ownsRegistration(session)) _redrawRegistration();
          return;
        }
      case _RegistrationPhase.results:
        if (page.kind == 'grid' &&
            page.semester == course.semester &&
            session.userChose) {
          if (samePage && session.choiceTicket != null) {
            await _registrationCommand(
              page,
              'clear',
              ticket: session.choiceTicket,
            );
            if (!_ownsRegistration(session)) return;
          }
          adopt();
          if (page.registered.contains(course.code)) {
            _reviewRegistration(session, RegistrationOutcome.completed, '完了');
          } else {
            _reviewRegistration(
              session,
              RegistrationOutcome.incomplete,
              page.message.isEmpty
                  ? '未完了。学務の画面を確認してください。'
                  : '未完了。 ${page.message}',
            );
          }
          return;
        }
        if (samePage &&
            page.kind == 'results' &&
            page.data['count'] == previous.data['count'] &&
            page.data['selectable'] == previous.data['selectable']) {
          return;
        }
        break;
      case _RegistrationPhase.back:
        if (page.kind == 'condition' && previous.kind != 'condition') {
          adopt();
          await _advanceRegistrationPage(
            session,
            _RegistrationPhase.back,
            'back',
          );
          return;
        }
        if (page.kind == 'grid' && page.semester == course.semester) {
          adopt();
          _reviewRegistration(session, RegistrationOutcome.skipped, '飛ばしました');
          return;
        }
      case _RegistrationPhase.reviewed:
        if (samePage &&
            page.kind == 'grid' &&
            page.semester == previous.semester) {
          return;
        }
        break;
    }
    // A permitted transition may still be on its source document.
    if (samePage &&
        page.kind == previous.kind &&
        page.semester == previous.semester &&
        const {
          _RegistrationPhase.semester,
          _RegistrationPhase.adding,
          _RegistrationPhase.searching,
          _RegistrationPhase.back,
        }.contains(session.phase)) {
      return;
    }
    _finishRegistration('履修登録画面が変わったため終了しました。');
  }

  Future<void> _skipRegistration(_RegistrationSession session) async {
    if (!_ownsRegistration(session) ||
        session.phase != _RegistrationPhase.results ||
        session.navigation != _navigationRevision ||
        session.busy ||
        session.userChose) {
      return;
    }
    session.busy = true;
    try {
      if (session.choiceTicket != null) {
        await _registrationCommand(
          session.page,
          'clear',
          ticket: session.choiceTicket,
        );
      }
      if (!_ownsRegistration(session) ||
          session.navigation != _navigationRevision) {
        return;
      }
      session.choiceTicket = null;
      session.run.outcomes[session.course.code] = RegistrationOutcome.skipped;
      await _advanceRegistrationPage(session, _RegistrationPhase.back, 'back');
    } on Object {
      if (_ownsRegistration(session)) _finishRegistration('学務の画面を確認できませんでした。');
    } finally {
      session.busy = false;
    }
  }

  void _nextRegistration(_RegistrationSession session) {
    if (!_ownsRegistration(session) ||
        session.phase != _RegistrationPhase.reviewed ||
        session.busy) {
      return;
    }
    final next = session.run.next;
    if (next == null) {
      _finishRegistration('履修登録の入力補助を終了しました。');
      return;
    }
    session.userChose = false;
    session.course = next;
    session.phase = _RegistrationPhase.grid;
    session.status = '登録画面を確認しています…';
    _redrawRegistration();
    unawaited(_stepRegistration(session));
  }

  Widget? _buildRegistrationPanel() {
    final session = _registrationSession;
    if (session != null) {
      return RegistrationAssistPanel(
        status: session.status,
        onCancel: () => _finishRegistration('入力補助を中止しました。'),
        onSkip:
            session.phase == _RegistrationPhase.results && !session.userChose
            ? () => unawaited(_skipRegistration(session))
            : null,
        onNext: session.phase == _RegistrationPhase.reviewed
            ? () => _nextRegistration(session)
            : null,
      );
    }
    final summary = _registrationSummary;
    return summary == null
        ? null
        : RegistrationAssistPanel(
            status: summary,
            onClose: () => _setRegistrationSession(null, summary: null),
          );
  }
}

class _RegistrationPasteDialog extends StatefulWidget {
  const _RegistrationPasteDialog();

  @override
  State<_RegistrationPasteDialog> createState() =>
      _RegistrationPasteDialogState();
}

class _RegistrationPasteDialogState extends State<_RegistrationPasteDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      _controller.text = clipboard?.text ?? '';
      setState(() => _error = null);
    } on Object {
      if (mounted) setState(() => _error = 'クリップボードを読み取れませんでした。');
    }
  }

  void _decode() {
    try {
      Navigator.pop(context, RegistrationHandoff.decode(_controller.text));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('履修手帖の時間割を履修登録に入力'),
    scrollable: true,
    content: Column(
      children: [
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '引き継ぎテキスト'),
          autocorrect: false,
          enableSuggestions: false,
        ),
        TextButton(onPressed: _paste, child: const Text('クリップボードから貼り付け')),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(onPressed: _decode, child: const Text('内容を確認')),
    ],
  );
}
