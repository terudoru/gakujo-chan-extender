class GakujoDatedActivity {
  const GakujoDatedActivity._();

  static final RegExp _datePattern = RegExp(
    r'((?:令和[0-9]{1,2}年|(?:20)?[0-9]{2}(?:[\/.\-]|年))[0-9]{1,2}(?:[\/.\-]|月)[0-9]{1,2}日?(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?|[0-9]{1,2}[\/.][0-9]{1,2}(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?|[0-9]{1,2}月[0-9]{1,2}日(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?)',
  );

  static bool containsDate(String text) {
    return _datePattern.hasMatch(normalizeDateText(text));
  }

  static String normalizeDateText(String text) {
    const fullWidthDigits = '０１２３４５６７８９';
    const asciiDigits = '0123456789';
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final digitIndex = fullWidthDigits.indexOf(char);
      if (digitIndex >= 0) {
        buffer.write(asciiDigits[digitIndex]);
        continue;
      }
      buffer.write(
        switch (char) {
          '：' => ':',
          '／' => '/',
          '．' => '.',
          '－' || '−' => '-',
          _ => char,
        },
      );
    }
    return buffer.toString();
  }

  /// Coursework deadlines on Gakujo's schedule page, one per assignment.
  ///
  /// The month view packs a whole week into one row, so reading it line by
  /// line turned rows like "12 [休日]祝日 13 14 1限:…" into deadlines.
  /// Assignments appear there as `[小テスト][開講番号 科目名]題名【日付まで】`,
  /// and in the 提出物情報 list as `レポート "題名" 開始日 ～ 終了日`.
  static List<
      ({
        String title,
        String dueText,
        String course,
        String courseCode,
        String name,
      })> scheduleCourseworkItems(
    String text,
  ) {
    final items = <({
      String title,
      String dueText,
      String course,
      String courseCode,
      String name,
    })>[];
    final seen = <String>{};
    String key(String name, String due) {
      final date = RegExp(r'([0-9]{4})\D+([0-9]{1,2})\D+([0-9]{1,2})')
          .firstMatch(normalizeDateText(due));
      final day = date == null
          ? due
          : '${date.group(1)}-${int.parse(date.group(2)!)}-'
              '${int.parse(date.group(3)!)}';
      return '$name|$day';
    }

    final listed = RegExp(
      r'\[(レポート|小テスト|アンケート)\]\[(?:([0-9]{3}[A-Z][0-9]{4})\s*)?([^\]]*)\]'
      // A title may carry its own 【…〆切】 before the 【…まで】 date.
      r'\s*([^\[\n\t]+?)\s*【([^】]*まで)】',
    );
    for (final match in listed.allMatches(text)) {
      final name = match.group(4)!.trim();
      if (!seen.add(key(name, match.group(5)!))) {
        continue;
      }
      items.add((
        title: compactText(
          '${match.group(1)} ${match.group(3)!.trim()} $name',
          maxLength: 80,
        ),
        dueText: match.group(5)!.trim(),
        course: match.group(3)!.trim(),
        courseCode: match.group(2) ?? '',
        name: name,
      ));
    }
    final submissions = RegExp(
      r'(レポート|小テスト|アンケート)\s*"([^"]+)"\s*'
      r'([0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日)\s*[～〜~]\s*'
      r'([0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日)',
    );
    for (final match in submissions.allMatches(text)) {
      final name = match.group(2)!.trim();
      // The month view already named this one together with its course.
      if (!seen.add(key(name, match.group(4)!))) {
        continue;
      }
      items.add((
        title: compactText('${match.group(1)} $name', maxLength: 80),
        dueText: '${match.group(4)}まで',
        course: '',
        courseCode: '',
        name: name,
      ));
    }
    return items;
  }

  /// A row of the schedule month view read as one line, as earlier versions
  /// stored it: several periods or a holiday label, not one deadline.
  static bool isScheduleCalendarRow(String text) {
    return text.contains('[休日]') ||
        RegExp(r'[1-7]\s*限\s*[:：]').allMatches(text).length >= 2;
  }

  static bool isNoiseText(String text) {
    final compacted = normalizeDateText(compactText(text));
    if (compacted.isEmpty) {
      return true;
    }
    if (compacted.contains('MYスケジュール') ||
        compacted.contains('前回ログイン日時') ||
        compacted.contains('ログアウト') ||
        compacted.contains('残り約') ||
        compacted.startsWith('Copyright')) {
      return true;
    }
    if (RegExp(r'^[0-9]{4}/[0-9]{1,2}/[0-9]{1,2}\([A-Za-z]+\)$')
        .hasMatch(compacted)) {
      return true;
    }
    if (RegExp(r'^[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日\s*[0-9]{1,2}時[0-9]{1,2}分$')
        .hasMatch(compacted)) {
      return true;
    }
    if (RegExp(
      r'^[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日\s*[0-9]{1,2}時[0-9]{1,2}分\s*(から|まで)$',
    ).hasMatch(compacted.replaceAll('　', ' '))) {
      return true;
    }
    return false;
  }

  static String kindFor({
    required String text,
    required String category,
  }) {
    if (text.contains('期限') ||
        text.contains('締切') ||
        text.contains('締め切') ||
        text.contains('提出') ||
        text.contains('レポート') ||
        text.contains('課題')) {
      return 'deadline';
    }
    if (category == 'スケジュール' ||
        text.contains('予定') ||
        text.contains('日程') ||
        text.contains('開催') ||
        text.contains('説明会') ||
        text.contains('ガイダンス')) {
      return 'schedule';
    }
    return 'notice';
  }

  static String compactText(String text, {int maxLength = 180}) {
    final compacted = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compacted.length <= maxLength) {
      return compacted;
    }
    return '${compacted.substring(0, maxLength)}...';
  }

  static String titleFor(String text) {
    final compacted = compactText(text);
    final normalized = normalizeDateText(compacted);
    final dateMatch = _datePattern.firstMatch(normalized);
    if (dateMatch == null || dateMatch.start > 36) {
      return compactText(compacted, maxLength: 80);
    }
    final prefix = compacted.substring(0, dateMatch.start).trim();
    if (prefix.isNotEmpty) {
      return compactText(prefix, maxLength: 80);
    }
    return compactText(compacted, maxLength: 80);
  }
}
