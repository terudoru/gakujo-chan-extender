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
