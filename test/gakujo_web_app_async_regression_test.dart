import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  group('portal authentication state', () {
    test('detects login fields when name and id repeat the same userId',
        () async {
      final result = await _evaluateAuthProbe([
        {
          'tag': 'input',
          'type': 'text',
          'name': 'userId',
          'id': 'userId',
        },
        {
          'tag': 'input',
          'type': 'password',
          'name': 'password',
          'id': 'password',
        },
      ]);

      expect(result['hasLoginFields'], isTrue, reason: jsonEncode(result));
      expect(
        gakujoPortalAuthStateFromJavaScriptResult(result),
        GakujoPortalAuthState.login,
      );
    });

    test('detects 2FA and authenticated DOM markers', () async {
      final twoFactor = await _evaluateAuthProbe([
        {
          'tag': 'input',
          'type': 'password',
          'name': 'ninshoCode',
          'id': 'ninshoCode',
        },
      ]);
      final authenticated = await _evaluateAuthProbe([
        {'tag': 'button', 'text': 'ログアウト'},
      ]);

      expect(
        gakujoPortalAuthStateFromJavaScriptResult(twoFactor),
        GakujoPortalAuthState.twoFactor,
      );
      expect(
        gakujoPortalAuthStateFromJavaScriptResult(authenticated),
        GakujoPortalAuthState.authenticated,
      );
    });

    test('ignores hidden authenticated controls', () async {
      final hiddenLogout = await _evaluateAuthProbe([
        {'tag': 'button', 'text': 'ログアウト', 'display': 'none'},
      ]);

      expect(hiddenLogout['hasAuthenticatedMarker'], isFalse);
      expect(
        gakujoPortalAuthStateFromJavaScriptResult(hiddenLogout),
        GakujoPortalAuthState.unknown,
      );
    });

    test('restores the protected page once after login and 2FA', () {
      const protectedUrl =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';
      const dynamicLoginUrl =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do';
      const authenticatedLandingUrl =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';

      String? sessionRecoveryUrl = protectedUrl;
      String? pendingRestoreUrl;
      var restoreAttempted = true;
      var loadCount = 0;

      void observeChallenge(GakujoPortalAuthState authState) {
        if (shouldResetGakujoLoginRestoreAttempt(
          authState: authState,
          urlLooksLikeLoginOrTimeout: false,
          hasRecoveryUrl: sessionRecoveryUrl != null,
        )) {
          pendingRestoreUrl = sessionRecoveryUrl;
          restoreAttempted = false;
        }
      }

      // campussmart.do is also an authenticated portal URL, so the DOM probe
      // must identify the dynamically revealed login form.
      expect(dynamicLoginUrl, isNot(contains('login')));
      observeChallenge(GakujoPortalAuthState.login);
      expect(sessionRecoveryUrl, protectedUrl);
      expect(pendingRestoreUrl, protectedUrl);

      observeChallenge(GakujoPortalAuthState.twoFactor);
      expect(sessionRecoveryUrl, protectedUrl);
      expect(pendingRestoreUrl, protectedUrl);

      sessionRecoveryUrl = authenticatedLandingUrl;
      if (shouldRestorePendingGakujoPage(
        authState: GakujoPortalAuthState.authenticated,
        restoreAttempted: restoreAttempted,
        hasRestoreUrl: pendingRestoreUrl != null,
        currentUrlMatchesRestoreUrl:
            pendingRestoreUrl == authenticatedLandingUrl,
      )) {
        loadCount += 1;
        restoreAttempted = true;
        pendingRestoreUrl = null;
      }
      // A duplicate/stale authenticated callback cannot load it again.
      if (shouldRestorePendingGakujoPage(
        authState: GakujoPortalAuthState.authenticated,
        restoreAttempted: restoreAttempted,
        hasRestoreUrl: pendingRestoreUrl != null,
        currentUrlMatchesRestoreUrl:
            pendingRestoreUrl == authenticatedLandingUrl,
      )) {
        loadCount += 1;
      }

      expect(loadCount, 1);
      expect(pendingRestoreUrl, isNull);
    });

    test('preserves a saved page without requiring stored credentials', () {
      const savedUrl =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';

      expect(
        gakujoInitialPendingRestoreUrl(
          pendingNotificationUrl: null,
          savedUrl: savedUrl,
        ),
        savedUrl,
      );
    });

    test('notification target is reserved during an existing login challenge',
        () {
      const target =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?_eventId=reportList';
      expect(
        gakujoNotificationRestoreTarget(target, debugAllowed: false),
        target,
      );
      expect(
        gakujoNotificationRestoreTarget(
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/login.do',
          debugAllowed: false,
        ),
        isNull,
      );
      expect(
        selectGakujoSessionRecoveryUrl(
          navigationCandidateUrl: target,
          authenticatedUrl:
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
          pendingRestoreUrl: target,
        ),
        target,
      );
      expect(
        selectGakujoSessionRecoveryUrl(
          navigationCandidateUrl: null,
          authenticatedUrl:
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/message/list.do',
          pendingRestoreUrl: target,
        ),
        target,
        reason: 'a same-URL login challenge must not discard notification B',
      );
    });

    test('consumes a pending target already reached by authentication', () {
      const target =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';

      expect(
        shouldConsumePendingGakujoPage(
          authState: GakujoPortalAuthState.authenticated,
          currentUrl: target,
          restoreUrl: target,
        ),
        isTrue,
      );
      expect(
        shouldConsumePendingGakujoPage(
          authState: GakujoPortalAuthState.login,
          currentUrl: target,
          restoreUrl: target,
        ),
        isFalse,
      );
    });

    test('freezes protected navigation B ahead of login shell redirects', () {
      const authenticatedA =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/message/list.do';
      const requestedB =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';
      const sharedLoginShell =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do';

      expect(
        isGakujoNavigationRecoveryCandidateUrl(
          requestedB,
          debugAllowed: false,
        ),
        isTrue,
      );
      expect(
        isGakujoNavigationRecoveryCandidateUrl(
          sharedLoginShell,
          debugAllowed: false,
        ),
        isFalse,
      );
      expect(
        selectGakujoSessionRecoveryUrl(
          navigationCandidateUrl: requestedB,
          authenticatedUrl: authenticatedA,
          pendingRestoreUrl: null,
        ),
        requestedB,
      );

      final challengeAtCandidate = usableGakujoNavigationCandidateForChallenge(
        navigationCandidateUrl: requestedB,
        challengeUrl: requestedB,
      );
      expect(challengeAtCandidate, isNull);
      expect(
        selectGakujoSessionRecoveryUrl(
          navigationCandidateUrl: challengeAtCandidate,
          authenticatedUrl: authenticatedA,
          pendingRestoreUrl: null,
        ),
        authenticatedA,
      );
    });

    test('autofill runtime features expose timer teardown scripts', () {
      final login = gakujoRuntimeTeardownScriptForFeature(
        GakujoFeatureFlag.loginAutofill,
      );
      final twoFactor = gakujoRuntimeTeardownScriptForFeature(
        GakujoFeatureFlag.twoFactorAutofill,
      );
      final gpa = gakujoRuntimeTeardownScriptForFeature(
        GakujoFeatureFlag.gpaDisplay,
      );

      expect(login, contains('__MBG_LOGIN_AUTOFILL_DISABLED'));
      expect(login, contains('clearTimeout'));
      expect(twoFactor, contains('__MBG_2FA_AUTOFILL_DISABLED'));
      expect(twoFactor, contains('clearTimeout'));
      expect(gpa, isNotNull);
    });

    test('authenticated reset clears session and document attempt guards',
        () async {
      expect(
        gakujoPortalAuthStateFromSignals(
          hasLoginFields: true,
          hasTwoFactorField: false,
          hasAuthenticatedMarker: false,
        ),
        GakujoPortalAuthState.login,
      );
      expect(gakujoAuthenticatedSessionResetScript, contains('removeItem'));
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_LOGIN_AUTOFILL_ERROR:'),
      );
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_LOGIN_AUTOFILL_SUBMIT_COUNT:'),
      );
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_LOGIN_AUTOFILL_LAST_CREDENTIAL:'),
      );
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_2FA_AUTOFILL_ERROR:'),
      );
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_2FA_AUTOFILL_SUBMIT_COUNT:'),
      );
      expect(gakujoAuthenticatedSessionResetScript, isNot(contains('clear()')));
      final reset = await _evaluateAuthenticatedSessionReset();
      expect(reset['hasLoginDocumentGuard'], isFalse);
      expect(reset['hasTwoFactorDocumentGuard'], isFalse);
      expect(
        reset['keys'],
        ['UNRELATED'],
        reason: jsonEncode(reset),
      );
    });
  });

  group('calendar extraction evidence', () {
    test('generic extraction must be broad but official can be nonempty', () {
      final narrow = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1, 1, 1, 1]),
        termRange: null,
      );
      final broad = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1, 2, 3, 1]),
        termRange: null,
      );

      expect(isBroadGakujoScheduleExtraction(narrow), isFalse);
      expect(
        isUsableGakujoScheduleExtraction(narrow, isOfficial: false),
        isFalse,
      );
      expect(
        isUsableGakujoScheduleExtraction(narrow, isOfficial: true),
        isTrue,
      );
      expect(
        isUsableGakujoScheduleExtraction(broad, isOfficial: false),
        isTrue,
      );
    });

    test('term range and best course list are retained independently', () {
      final range = GakujoCalendarTermRange(
        start: DateTime(2026, 6, 11),
        end: DateTime(2026, 8, 8),
      );
      final rangeWithOneCourse = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1]),
        termRange: range,
      );
      final completeWithoutRange = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1, 2, 3, 4, 5, 1, 2, 3, 4, 5]),
        termRange: null,
      );

      final merged = mergeGakujoScheduleExtractionEvidence(
        rangeWithOneCourse,
        completeWithoutRange,
      );

      expect(merged.courses, hasLength(10));
      expect(merged.termRange, same(range));
      expect(isBroadGakujoScheduleExtraction(merged), isTrue);
    });

    test('winning course evidence keeps its own term range in either order',
        () {
      final firstRange = GakujoCalendarTermRange(
        start: DateTime(2026, 4, 1),
        end: DateTime(2026, 6, 10),
      );
      final secondRange = GakujoCalendarTermRange(
        start: DateTime(2026, 6, 11),
        end: DateTime(2026, 8, 8),
      );
      final narrowFirst = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1]),
        termRange: firstRange,
      );
      final broadSecond = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1, 2, 3, 4, 5, 1, 2, 3, 4, 5]),
        termRange: secondRange,
      );

      final broadFirst = mergeGakujoScheduleExtractionEvidence(
        broadSecond,
        narrowFirst,
      );
      final broadCandidate = mergeGakujoScheduleExtractionEvidence(
        narrowFirst,
        broadSecond,
      );

      expect(broadFirst.courses, hasLength(10));
      expect(broadFirst.termRange, same(secondRange));
      expect(broadCandidate.courses, hasLength(10));
      expect(broadCandidate.termRange, same(secondRange));
    });
  });

  group('calendar integration safety', () {
    test('calendar validation advances by civil dates', () {
      final next = gakujoCalendarDateAfterDays(DateTime(2026, 10, 31), 1);
      expect(next, DateTime(2026, 11, 1));
      expect(next.hour, 0);
    });

    test('manual calendar identity survives small range corrections', () {
      final original = gakujoManualCalendarUidNamespace(
        termRange: GakujoCalendarTermRange(
          start: DateTime(2026, 6, 11),
          end: DateTime(2026, 8, 8),
        ),
      );
      final corrected = gakujoManualCalendarUidNamespace(
        termRange: GakujoCalendarTermRange(
          start: DateTime(2026, 6, 12),
          end: DateTime(2026, 8, 7),
        ),
      );
      final firstTerm = gakujoManualCalendarUidNamespace(
        termRange: GakujoCalendarTermRange(
          start: DateTime(2026, 4, 8),
          end: DateTime(2026, 6, 8),
        ),
      );

      expect(corrected, original);
      expect(firstTerm, isNot(original));
      expect(original, 'niigata-2026-第2ターム');
      expect(
        gakujoLegacyManualIcsUidNamespace(
          GakujoCalendarTermRange(
            start: DateTime(2026, 6, 11),
            end: DateTime(2026, 8, 8),
          ),
        ),
        'manual-20260611-20260808',
      );
    });

    test('accepts only canonical HTTPS Google host boundaries', () {
      expect(
        isAllowedGakujoGoogleCalendarUrl(
          'https://calendar.google.com/calendar/render',
        ),
        isTrue,
      );
      expect(
        isAllowedGakujoGoogleCalendarUrl(
          'https://calendar.google.com:443/calendar/render',
        ),
        isTrue,
      );
      for (final url in [
        'http://calendar.google.com/calendar/render',
        'https://drive.google.com/calendar/render',
        'https://google.com/calendar/render',
        'https://evilgoogle.com/calendar/render',
        'https://google.com.evil.example/calendar/render',
        'https://google.com@evil.example/calendar/render',
        'https://calendar.google.com:444/calendar/render',
      ]) {
        expect(
          isAllowedGakujoGoogleCalendarUrl(url),
          isFalse,
          reason: url,
        );
      }
    });

    test('ambiguous courses initialize from their own hints only', () {
      const withHints = GakujoCalendarCourse(
        title: '複数ターム授業',
        weekday: 1,
        period: 1,
        courseCode: '260A0001',
        termHint: '第1ターム 第3ターム',
      );
      const withoutHints = GakujoCalendarCourse(
        title: '期間不明授業',
        weekday: 2,
        period: 2,
        courseCode: '260B0001',
      );

      expect(initialGakujoAmbiguousCourseTermSelections(withHints), {1, 3});
      expect(initialGakujoAmbiguousCourseTermSelections(withoutHints), isEmpty);
    });

    test('unselected ambiguous courses are omitted instead of reappearing', () {
      const ambiguous = GakujoCalendarCourse(
        title: '期間不明授業',
        weekday: 1,
        period: 1,
        courseCode: '260A0001',
      );
      const regular = GakujoCalendarCourse(
        title: '第1ターム授業',
        weekday: 2,
        period: 2,
        courseCode: '261B0001',
      );
      final key = GakujoCalendarExport.courseIdentityKey(ambiguous);

      expect(
        applyGakujoAmbiguousCourseTermSelections(
          const [ambiguous, regular],
          const {},
        ),
        [regular],
      );
      expect(
        applyGakujoAmbiguousCourseTermSelections(
          const [ambiguous, regular],
          {key: <int>{}},
        ),
        [regular],
      );
      final selected = applyGakujoAmbiguousCourseTermSelections(
        const [ambiguous, regular],
        {
          key: {4, 2},
        },
      );
      expect(selected, hasLength(2));
      expect(selected.first.termHint, '第2ターム 第4ターム');
    });

    test('native calendar export sends ICS bytes to the iOS picker bridge',
        () async {
      const channel = MethodChannel(
        'net.yoshida.morebettergakujo/downloads',
      );
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        capturedCall = call;
        return {
          'fileName': 'classes.ics',
          'courseName': '',
          'location': '/picked/classes.ics',
        };
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final result = await exportGakujoCalendarWithNativePicker(
        ics: 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n',
        fileName: 'classes.ics',
      );

      expect(capturedCall?.method, 'exportDownloadedFile');
      final arguments = capturedCall?.arguments as Map<dynamic, dynamic>;
      expect(arguments['fileName'], 'classes.ics');
      expect(arguments['mimeType'], 'text/calendar');
      expect(arguments['bytes'], isA<Uint8List>());
      expect(
        utf8.decode(arguments['bytes'] as Uint8List),
        'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n',
      );
      expect(result, isA<GakujoDownloadResult>());
      expect(result.location, '/picked/classes.ics');
    });
  });

  test('calendar operation gate rejects a concurrent operation', () {
    final gate = GakujoCalendarOperationGate();

    expect(gate.tryStart(), isTrue);
    expect(gate.isRunning, isTrue);
    expect(gate.tryStart(), isFalse);
    gate.finish();
    expect(gate.tryStart(), isTrue);
  });

  testWidgets('manual term dialog keeps its controllers until route closes',
      (tester) async {
    GakujoCalendarTermRange? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selected = await showGakujoCalendarTermRangeDialog(
                  context: context,
                  title: 'ターム期間を入力',
                  description: '期間を入力してください',
                  actionLabel: '書き出し',
                  initialDate: DateTime(2026, 6, 1),
                );
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).at(0), '2026/06/11');
    await tester.enterText(find.byType(TextField).at(1), '2026/08/08');
    await tester.tap(find.text('書き出し'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(selected?.start, DateTime(2026, 6, 11));
    expect(selected?.end, DateTime(2026, 8, 8));
  });
}

List<GakujoCalendarCourse> _coursesForWeekdays(List<int> weekdays) {
  return [
    for (var index = 0; index < weekdays.length; index += 1)
      GakujoCalendarCourse(
        title: '授業${index + 1}',
        weekday: weekdays[index],
        period: (index % 5) + 1,
        courseCode: 'COURSE${index + 1}',
      ),
  ];
}

Future<Map<String, dynamic>> _evaluateAuthProbe(
  List<Map<String, String>> elements,
) async {
  final result = await Process.run('node', [
    '-e',
    _authProbeDomHarness,
    gakujoPortalAuthStateProbeScript,
    jsonEncode(elements),
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _evaluateAuthenticatedSessionReset() async {
  final result = await Process.run('node', [
    '-e',
    _authenticatedSessionResetHarness,
    gakujoAuthenticatedSessionResetScript,
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const _authProbeDomHarness = r'''
const vm = require('node:vm');
const generatedScript = process.argv[1];
const specs = JSON.parse(process.argv[2]);

class FakeElement {
  constructor(spec) {
    this.attributes = {...spec};
    this.innerText = spec.text || '';
    this.textContent = this.innerText;
    this.value = spec.value || '';
    this.ownerDocument = null;
  }
  getAttribute(name) { return this.attributes[name] ?? null; }
  getClientRects() { return this.attributes.display === 'none' ? [] : [{}]; }
}

const elements = specs.map((spec) => new FakeElement(spec));
const inputs = elements.filter((element) =>
  (element.getAttribute('tag') || '').toLowerCase() === 'input'
);
const document = {
  body: new FakeElement({tag: 'body', text: ''}),
  defaultView: null,
  querySelectorAll(selector) {
    if (selector === 'input') return inputs;
    if (selector === 'a, button, input, [role="button"], img') return elements;
    return [];
  }
};
const window = {
  document,
  frames: [],
  getComputedStyle(element) {
    return {
      display: element.attributes.display || 'block',
      visibility: 'visible',
      opacity: '1'
    };
  }
};
window.window = window;
document.defaultView = window;
document.body.ownerDocument = document;
for (const element of elements) element.ownerDocument = document;

const output = vm.runInNewContext(generatedScript, {window, document});
process.stdout.write(output);
''';

const _authenticatedSessionResetHarness = r'''
const vm = require('node:vm');
const generatedScript = process.argv[1];
const values = new Map([
  ['MBG_LOGIN_AUTOFILL_ERROR:/login:key', '1'],
  ['MBG_LOGIN_AUTOFILL_SUBMIT_COUNT:/login:key', '1'],
  ['MBG_LOGIN_AUTOFILL_LAST_CREDENTIAL:/login', 'key'],
  ['MBG_2FA_AUTOFILL_ERROR:/2fa:key', '1'],
  ['MBG_2FA_AUTOFILL_SUBMIT_COUNT:/2fa:key', '1'],
  ['UNRELATED', 'keep']
]);
const window = {
  __MBG_LOGIN_AUTOFILL_SUBMITTED_KEY: 'credentials',
  __MBG_2FA_AUTO_SUBMITTED_KEY: 'secret',
  sessionStorage: {
    get length() { return values.size; },
    key(index) { return Array.from(values.keys())[index] || null; },
    removeItem(key) { values.delete(key); }
  }
};
window.window = window;
vm.runInNewContext(generatedScript, {window});
process.stdout.write(JSON.stringify({
  hasLoginDocumentGuard:
    Object.prototype.hasOwnProperty.call(window, '__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY'),
  hasTwoFactorDocumentGuard:
    Object.prototype.hasOwnProperty.call(window, '__MBG_2FA_AUTO_SUBMITTED_KEY'),
  keys: Array.from(values.keys())
}));
''';
