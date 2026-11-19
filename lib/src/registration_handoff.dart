import 'dart:convert';

final registrationCodePattern = RegExp(r'^\d{3}[A-Z][A-Z0-9]{4,5}$');
final registrationSlotPattern = RegExp(r'^[月火水木金土日][1-7]$');
final _tokenPattern = RegExp(r'MBGREG1\.[A-Za-z0-9_-]+');

const registrationSafetyText =
    'アプリは「選択」「削除」を押しません。検索結果で科目を確認し、ご自身で「選択」を押してください。';

class RegistrationCourse {
  const RegistrationCourse({
    required this.code,
    required this.title,
    required this.semester,
    required this.quarters,
    required this.slots,
    required this.credits,
  });

  final String code;
  final String title;
  final int? semester;
  final List<int> quarters;
  final List<String> slots;
  final num? credits;

  String get label => '$code $title';

  Map<String, Object?> toJson() => {
    'code': code,
    'title': title,
    'semester': semester,
    'quarters': quarters,
    'slots': slots,
    'credits': credits,
  };
}

class RegistrationHandoff {
  const RegistrationHandoff(this.year, this.courses);

  final int year;
  final List<RegistrationCourse> courses;

  Map<String, Object?> toJson() => {
    'v': 1,
    'kind': 'gakujo-registration-plan',
    'year': year,
    'courses': courses.map((course) => course.toJson()).toList(),
  };

  static RegistrationHandoff decode(String text) {
    final match = _tokenPattern.firstMatch(text);
    if (match == null) {
      throw const FormatException('MBGREG1. で始まる引き継ぎテキストを貼り付けてください。');
    }
    if (match.end - match.start > 64 * 1024) {
      throw const FormatException('引き継ぎテキストは64 KiBまでです。');
    }
    final payload = text.substring(match.start + 'MBGREG1.'.length, match.end);
    final Object? json;
    try {
      final bytes = base64Url.decode(base64Url.normalize(payload));
      if (base64Url.encode(bytes).replaceAll('=', '') != payload ||
          (match.end < text.length && text[match.end] == '=')) {
        throw const FormatException();
      }
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException('引き継ぎテキストの形式が正しくありません。');
    }

    if (!_hasKeys(json, const {'v', 'kind', 'year', 'courses'})) {
      throw const FormatException('引き継ぎデータの項目が正しくありません。');
    }
    final root = json as Map<String, dynamic>;
    final year = root['year'];
    final courses = root['courses'];
    if (root['v'] is! int ||
        root['v'] != 1 ||
        root['kind'] != 'gakujo-registration-plan' ||
        year is! int ||
        year < 2000 ||
        year > 2099) {
      throw const FormatException('引き継ぎデータの種類、バージョン、または年度が正しくありません。');
    }
    if (courses is! List || courses.isEmpty || courses.length > 60) {
      throw const FormatException('科目数は1〜60件である必要があります。');
    }
    final codes = <String>{};
    return RegistrationHandoff(
      year,
      List.unmodifiable([
        for (final (index, item) in courses.indexed)
          _course(item, index + 1, codes),
      ]),
    );
  }

  static RegistrationCourse _course(
    Object? item,
    int index,
    Set<String> codes,
  ) {
    if (!_hasKeys(item, const {
      'code',
      'title',
      'semester',
      'quarters',
      'slots',
      'credits',
    })) {
      throw FormatException('$index件目の科目の項目が正しくありません。');
    }
    final course = item as Map<String, dynamic>;
    final code = course['code'];
    final title = course['title'];
    final semester = course['semester'];
    final quarters = course['quarters'];
    final slots = course['slots'];
    final credits = course['credits'];
    if (code is! String ||
        !registrationCodePattern.hasMatch(code) ||
        title is! String ||
        title.isEmpty ||
        title.runes.length > 120 ||
        (semester != null &&
            (semester is! int || (semester != 1 && semester != 2))) ||
        quarters is! List ||
        quarters.length > 4 ||
        !quarters.every((q) => q is int && q >= 1 && q <= 4) ||
        quarters.toSet().length != quarters.length ||
        slots is! List ||
        slots.length > 14 ||
        !slots.every(
          (s) => s is String && registrationSlotPattern.hasMatch(s),
        ) ||
        slots.toSet().length != slots.length ||
        (credits != null &&
            (credits is! num ||
                !credits.isFinite ||
                credits < 0 ||
                credits > 30))) {
      throw FormatException('$index件目の科目の入力値が正しくありません。');
    }
    if (!codes.add(code)) throw const FormatException('開講番号が重複しています。');
    return RegistrationCourse(
      code: code,
      title: title,
      semester: semester as int?,
      quarters: List.unmodifiable(quarters.cast<int>()),
      slots: List.unmodifiable(slots.cast<String>()),
      credits: credits as num?,
    );
  }

  static bool _hasKeys(Object? value, Set<String> keys) =>
      value is Map<String, dynamic> &&
      value.length == keys.length &&
      value.keys.every(keys.contains);
}

enum RegistrationDisposition { registered, guided, manual, checkOtherSemester }

RegistrationDisposition classifyRegistrationCourse(
  RegistrationCourse course,
  Set<String> registered,
  Map<int, Set<String>> availableSlots,
) {
  if (registered.contains(course.code)) {
    return RegistrationDisposition.registered;
  }
  if (course.semester == null ||
      course.slots.isEmpty ||
      course.slots.first.startsWith('日')) {
    return RegistrationDisposition.manual;
  }
  final semesterSlots = availableSlots[course.semester];
  if (semesterSlots == null) return RegistrationDisposition.checkOtherSemester;
  return semesterSlots.contains(course.slots.first)
      ? RegistrationDisposition.guided
      : RegistrationDisposition.manual;
}

enum RegistrationOutcome { completed, skipped, manual, registered, incomplete }

class RegistrationRun {
  RegistrationRun(
    this.account,
    this.identityRevision,
    this.plan,
    this.outcomes,
  );

  final String account;
  final int identityRevision;
  final RegistrationHandoff plan;
  final Map<String, RegistrationOutcome> outcomes;
  bool ended = false;

  bool checkIdentity(
    String? currentAccount,
    int revision, {
    required bool confirmed,
  }) {
    if (!confirmed ||
        account != currentAccount ||
        identityRevision != revision) {
      ended = true;
    }
    return !ended;
  }

  RegistrationCourse? get next => ended
      ? null
      : plan.courses
            .where((course) => !outcomes.containsKey(course.code))
            .firstOrNull;

  String get summary {
    int count(RegistrationOutcome outcome) =>
        outcomes.values.where((v) => v == outcome).length;
    return '完了 ${count(RegistrationOutcome.completed)}件、飛ばした ${count(RegistrationOutcome.skipped)}件、'
        '手動 ${count(RegistrationOutcome.manual)}件、登録済み ${count(RegistrationOutcome.registered)}件、'
        '未完了 ${count(RegistrationOutcome.incomplete)}件、残り ${plan.courses.length - outcomes.length}件';
  }
}
