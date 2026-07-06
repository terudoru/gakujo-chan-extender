class GakujoActivityClassifier {
  const GakujoActivityClassifier._();

  static const _genericTitles = {
    '',
    'Gakujo',
    'CampusSquare',
    'CampusSquare for WEB [CampusSquare]',
  };

  static String categoryFor({
    required String url,
    required String title,
    required String text,
  }) {
    final normalizedUrl = url.toLowerCase();
    final normalizedTitle = _compact(title);
    final normalizedText = _compact(text);

    if (_looksLikeGrades(normalizedUrl, normalizedTitle)) {
      return '成績';
    }
    if (_looksLikeReports(normalizedUrl, normalizedTitle)) {
      return 'レポート・小テスト';
    }
    if (_looksLikeMessages(normalizedUrl, normalizedTitle)) {
      return '連絡通知';
    }
    if (_looksLikeSchedule(normalizedUrl, normalizedTitle)) {
      return 'スケジュール';
    }

    final firstContent = normalizedText.length > 400
        ? normalizedText.substring(0, 400)
        : normalizedText;
    if (firstContent.contains('単位修得状況照会') || firstContent.contains('成績確認')) {
      return '成績';
    }
    if (firstContent.contains('レポート提出') ||
        firstContent.contains('小テスト') ||
        firstContent.contains('アンケート提出')) {
      return 'レポート・小テスト';
    }
    if (firstContent.contains('掲示一覧') || firstContent.contains('新着の掲示')) {
      return '連絡通知';
    }
    if (normalizedText.contains('お知らせ') && normalizedText.contains('【')) {
      return '連絡通知';
    }
    if (firstContent.contains('MYスケジュール') ||
        firstContent.contains('週間スケジュール')) {
      if (_isGenericMainPortal(normalizedUrl, normalizedTitle)) {
        return 'Gakujo';
      }
      return 'スケジュール';
    }
    return 'Gakujo';
  }

  static String displayTitleFor({
    required String url,
    required String title,
    required String text,
    required String category,
  }) {
    final trimmedTitle = title.trim();
    if (!_isGenericTitle(trimmedTitle)) {
      return trimmedTitle;
    }

    final lines = stableLinesFor(text);
    if (lines.any((line) => line.contains('単位修得状況照会'))) {
      return '単位修得状況照会';
    }
    if (lines.any((line) => line.contains('レポート') || line.contains('小テスト'))) {
      return 'レポート・小テスト';
    }
    if (lines.any((line) => line.contains('掲示') || line.contains('お知らせ'))) {
      return 'お知らせ';
    }
    if (lines.any((line) => line.contains('新着情報') || line.startsWith('新着の'))) {
      return '新着情報';
    }
    if (lines.any((line) => line.contains('週間スケジュール'))) {
      return '週間スケジュール';
    }
    if (lines.any((line) => line.contains('MYスケジュール'))) {
      return 'MYスケジュール';
    }
    if (category != 'Gakujo') {
      return category;
    }
    return trimmedTitle.isEmpty ? 'Gakujo' : trimmedTitle;
  }

  static String stableContentFor({
    required String url,
    required String title,
    required String text,
    required String category,
  }) {
    final normalizedUrl = url.toLowerCase();
    final normalizedTitle = _compact(title);
    final lines = stableLinesFor(text);
    if (lines.isEmpty) {
      return '';
    }
    if (_looksLikeTransientPage(lines)) {
      return '';
    }

    if (_isGenericMainPortal(normalizedUrl, normalizedTitle)) {
      final noticeLines = _sectionUntil(
        lines,
        (line) => line.contains('お知らせ') || line.contains('新着情報'),
        (line) =>
            line.contains('MYスケジュール') ||
            line == 'リンク' ||
            line == '学生共通リンク' ||
            line.startsWith('Copyright'),
      );
      final concreteNoticeLines = noticeLines.where(_isConcreteNoticeLine);
      return concreteNoticeLines.take(30).join('\n');
    }

    if (category == 'スケジュール') {
      final scheduleLines = _sectionFrom(
        lines,
        (line) => line.contains('週間スケジュール') || line.contains('MYスケジュール'),
      );
      if (scheduleLines.isNotEmpty) {
        return scheduleLines.take(80).join('\n');
      }
    }

    if (category == '連絡通知') {
      final messageLines = _sectionUntil(
        lines,
        (line) =>
            line.contains('お知らせ') ||
            line.contains('新着情報') ||
            line.contains('掲示一覧') ||
            line.contains('連絡通知'),
        (line) =>
            line.contains('MYスケジュール') ||
            line == 'リンク' ||
            line == '学生共通リンク' ||
            line.startsWith('Copyright'),
      );
      if (messageLines.isNotEmpty) {
        final concreteMessageLines = messageLines.where(
          (line) => _isConcreteNoticeLine(line) || line.contains('掲示一覧'),
        );
        return concreteMessageLines.take(100).join('\n');
      }
    }

    return lines.take(120).join('\n');
  }

  static List<String> stableLinesFor(String text) {
    return text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty && !_isBoilerplateLine(line))
        .toList();
  }

  static bool _looksLikeGrades(String url, String title) {
    return url.contains('tabid=si') ||
        title.contains('単位修得状況照会') ||
        title.contains('成績確認');
  }

  static bool _looksLikeReports(String url, String title) {
    return url.contains('report') ||
        url.contains('enq') ||
        title.contains('レポート') ||
        title.contains('小テスト') ||
        title.contains('アンケート');
  }

  static bool _looksLikeMessages(String url, String title) {
    return url.contains('keiji') ||
        url.contains('message') ||
        title.contains('連絡通知') ||
        title.contains('掲示');
  }

  static bool _looksLikeSchedule(String url, String title) {
    return url.contains('schedule') ||
        title.contains('スケジュール') ||
        title.contains('時間割');
  }

  static String _compact(String value) {
    return value.replaceAll(RegExp(r'\s+'), '');
  }

  static bool _isGenericTitle(String title) {
    final normalized = title.trim();
    return _genericTitles.contains(normalized) ||
        normalized.startsWith('CampusSquare for WEB');
  }

  static bool _isGenericMainPortal(String normalizedUrl, String compactTitle) {
    final normalizedTitle = compactTitle.toLowerCase();
    return normalizedUrl.contains('campusportal.do') &&
        normalizedUrl.contains('page=main') &&
        !normalizedUrl.contains('tabid=') &&
        (normalizedTitle.isEmpty ||
            normalizedTitle == 'gakujo' ||
            normalizedTitle.contains('campussquare'));
  }

  static Iterable<String> _sectionFrom(
    List<String> lines,
    bool Function(String line) startAt,
  ) {
    final start = lines.indexWhere(startAt);
    if (start < 0) {
      return const [];
    }
    return lines.skip(start);
  }

  static Iterable<String> _sectionUntil(
    List<String> lines,
    bool Function(String line) startAt,
    bool Function(String line) stopAt,
  ) {
    final start = lines.indexWhere(startAt);
    if (start < 0) {
      return const [];
    }
    final result = <String>[];
    for (final line in lines.skip(start)) {
      if (result.isNotEmpty && stopAt(line)) {
        break;
      }
      result.add(line);
    }
    return result;
  }

  static bool _looksLikeTransientPage(List<String> lines) {
    final joined = lines.take(12).join(' ');
    return joined == 'now loading...' ||
        joined.contains('Google Authenticatorで発行された6桁の認証コード') ||
        (joined.contains('ID ※小文字で入力してください') &&
            joined.contains('パスワード') &&
            joined.contains('ログイン'));
  }

  static bool _isConcreteNoticeLine(String line) {
    if (line == 'お知らせ' || line == '新着情報') {
      return false;
    }
    if (line == 'あなた宛の新着情報があります。') {
      return false;
    }
    if (line == '登録されていません') {
      return false;
    }
    if (line.startsWith('[image]')) {
      return false;
    }
    return line.contains('【') ||
        line.startsWith('[') ||
        line.startsWith('新着の') ||
        line.contains('登録されました') ||
        line.contains('提出') ||
        line.contains('締切') ||
        line.contains('期限');
  }

  static bool _isBoilerplateLine(String line) {
    const exact = {
      '[image]',
      'スマホ版',
      'English',
      'カスタマイズ',
      'ログアウト',
      'HOME',
      '連絡通知',
      'スケジュール',
      '休講補講',
      'シラバス',
      '履修',
      '成績',
      'ダウンロード',
      'リンク',
      '各種情報',
      'NBAS',
      'Gmail',
      'CANチェック',
      '学生生活支援',
      '就職キャリア支援',
      '海外渡航登録',
      'その他',
    };
    if (exact.contains(line)) {
      return true;
    }
    return line.startsWith('Copyright') ||
        line.startsWith('残り約') ||
        line.startsWith('前回ログイン日時') ||
        line.startsWith('表示中:') ||
        line.startsWith('ブロック:') ||
        line.contains('学務情報システム') ||
        line.contains('スマホ版 English カスタマイズ') ||
        line.contains('お知らせ Gmail CANチェック') ||
        RegExp(r'^.+さん$').hasMatch(line) ||
        RegExp(r'^[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日 [0-9]{1,2}時[0-9]{1,2}分$')
            .hasMatch(line) ||
        RegExp(r'^[0-9]{4}年[0-9]{1,2}月$').hasMatch(line) ||
        RegExp(r'^([0-9]{1,2}\s+){2,}[0-9]{1,2}$').hasMatch(line) ||
        RegExp(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)(\s|$)').hasMatch(line);
  }
}
