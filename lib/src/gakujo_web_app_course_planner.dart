part of 'gakujo_web_app.dart';

extension _CoursePlannerActions on _GakujoWebAppState {
  Future<void> _openCoursePlanner({required bool importing}) async {
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
        // The standalone planner also opens while the portal is unavailable.
      }
      if (!mounted) return;
      if (!currentPage()) url = null;
      CoursePlannerSource? source;
      CoursePlannerImportKind? choice;
      if (importing) {
        if (!currentStudent() ||
            !AllowedWebOrigins.canLoad(url, debugAllowed: false)) {
          _showSnackBar('学務にログインし、成績または履修の照会画面を開いてください。');
          return;
        }
        source = CoursePlannerSource(_controller, currentStudent);
        final kinds = await source.choices();
        if (!mounted) return;
        if (kinds.isEmpty || !currentStudent()) {
          _showSnackBar('「単位修得状況照会」または「履修登録・登録状況照会」で対象の表を表示してください。');
          return;
        }
        choice = await showDialog<CoursePlannerImportKind>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: const Text('履修プランナーに渡す内容'),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text('表示中の表から選んだ項目を読み取ります。保存する前にプランナーで内容を確認できます。'),
              ),
              for (final kind in kinds)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, kind),
                  child: Text('${kind.label}を取り込む'),
                ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('キャンセル'),
              ),
            ],
          ),
        );
        if (choice == null || !mounted) return;
        if (!currentStudent()) {
          _showSnackBar('学務の表示またはログイン状態が変わりました。照会画面からやり直してください。');
          return;
        }
      }

      const configured = String.fromEnvironment('MBG_COURSE_PLANNER_URL');
      final target = coursePlannerLink(
        importing ? null : url,
        baseUrl: coursePlannerBase(configured, debug: kDebugMode),
      );
      if (!mounted) return;
      final portal = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (page) => CoursePlannerPage(
            service: _webViewService,
            url: target,
            source: source,
            kind: choice,
            onExternalLink: (link) {
              if (link.host == 'gakujo.iess.niigata-u.ac.jp') {
                // Return to the existing authenticated app. Open only the fixed
                // registration inquiry. No course selection or submission.
                if (ModalRoute.of(page)?.isCurrent == true) {
                  Navigator.pop(page, true);
                }
              } else {
                unawaited(_launchExternalUrl(link));
              }
            },
          ),
        ),
      );
      if (portal == true && mounted) {
        await _loadAllowedPageUrl(coursePlannerRegistrationUrl);
      }
    } on Object {
      if (mounted) _showSnackBar('履修プランナーを開けませんでした。もう一度お試しください。');
    } finally {
      _plannerOpening = false;
    }
  }
}
