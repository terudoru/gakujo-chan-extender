part of 'gakujo_web_app.dart';

enum _PlannerDestination { clipboard, registrationClipboard }

extension _CoursePlannerActions on _GakujoWebAppState {
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
        var handoffs = const <(CoursePlannerImportKind, String)>[];
        try {
          handoffs = await fetchCoursePlannerHandoffs(
            _controller,
            currentStudent,
          );
        } on Object {
          // The displayed page remains a source when the fetch fails.
        }
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
