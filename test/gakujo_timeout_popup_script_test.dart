import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_timeout_popup_script.dart';
import 'package:test/test.dart';

const _origin = 'https://gakujo.iess.niigata-u.ac.jp';
const _warning = '学務のセッションは残り約5分で切れます。';
const _expired = '学務のセッションが切れました。入力中のレポートは下書きに保存されています。もう一度開くと復元されます。';

void main() {
  for (final page in ['TimeoutAlert', 'Timeout']) {
    for (final url in [
      '/campusweb/theme/default/$page.html',
      '$_origin/campusweb/theme/default/$page.html',
      '/campusweb/theme/default/$page.html?remaining=5',
      '$_origin/campusweb/theme/default/$page.html?remaining=5#timer',
      '/campusweb/theme/default/$page.html#timer',
    ]) {
      test('$url is intercepted with a harmless popup stub', () async {
        final result = await _evaluate('popup', url: url);
        expect(result['openCalls'], isEmpty);
        expect(result['stub'], {
          'closedBefore': false,
          'closedAfter': false,
          'focusResult': null,
          'blurResult': null,
          'document': null,
          'location': null,
        });
        expect(result['bannerCount'], 1);
        expect(result['message'], page == 'TimeoutAlert' ? _warning : _expired);
        expect(result['buttons'],
            page == 'TimeoutAlert' ? ['延長する', '閉じる'] : ['閉じる']);
        expect(result['alertUnchanged'], isTrue);
      });
    }
  }

  test('relative timeout URLs are resolved before interception', () async {
    for (final page in ['TimeoutAlert', 'Timeout']) {
      for (final prefix in ['theme/default/', './theme/default/']) {
        final result = await _evaluate('popup', url: '$prefix$page.html');
        expect(result['openCalls'], isEmpty);
        expect(result['bannerCount'], 1);
        expect(result['message'], page == 'TimeoutAlert' ? _warning : _expired);
      }
    }
  });

  test('extend uses the intercepted iframe before the top window', () async {
    for (final scenario in ['iframeOwnExtend', 'iframeOwnExtendWithTop']) {
      final result = await _evaluate(scenario);
      expect(result['extendCalls'], 1);
      expect(result['extendThisIsFrame'], isTrue);
      expect(result['bannerCount'], 0);
      expect(result['openCalls'], isEmpty);
    }
  });

  test(
      'blank iframe bases use the top URL and failed resolution matches raw URLs',
      () async {
    for (final scenario in ['iframeBlank', 'iframeInvalidBase']) {
      for (final page in ['TimeoutAlert', 'Timeout']) {
        final url = scenario == 'iframeBlank'
            ? './theme/default/$page.html'
            : '/campusweb/theme/default/$page.html?timer=5';
        final result = await _evaluate(scenario, url: url);
        expect(result['openCalls'], isEmpty, reason: '$scenario $page');
        expect(result['bannerCount'], 1);
        expect(result['message'], page == 'TimeoutAlert' ? _warning : _expired);
      }
    }
  });

  test('closing the fake popup removes its timeout banner', () async {
    for (final scenario in ['popupClose', 'iframePopupClose']) {
      final result = await _evaluate(scenario);
      expect(result['bannerBeforeClose'], isTrue);
      expect(result['stub']['closedBefore'], isFalse);
      expect(result['stub']['closedAfter'], isTrue);
      expect(result['bannerCount'], 0);
      expect(result['extendCalls'], 0);
    }
  });

  test('closing an older popup keeps a newer timeout message', () async {
    final result = await _evaluate('staleClose');
    expect(result['bannerCount'], 1);
    expect(result['message'], _expired);
  });

  test('extend button calls the portal function and removes the banner',
      () async {
    final result = await _evaluate('extend');
    expect(result['extendCalls'], 1);
    expect(result['extendThisIsWindow'], isTrue);
    expect(result['bannerCount'], 0);
    expect(result['openCalls'], isEmpty);
  });

  for (final scenario in ['extendMissing', 'extendNotFunction']) {
    test('$scenario keeps the warning without throwing', () async {
      final result = await _evaluate(scenario);
      expect(result['extendCalls'], 0);
      expect(result['message'], _warning);
      expect(result['bannerCount'], 1);
    });
  }

  for (final scenario in ['closeWarning', 'closeExpired']) {
    test('$scenario dismisses the banner', () async {
      final result = await _evaluate(scenario);
      expect(result['bannerCount'], 0);
      expect(result['extendCalls'], 0);
    });
  }

  for (final scenario in ['warningThenExpired', 'expiredThenWarning']) {
    test('$scenario replaces the existing message and buttons', () async {
      final result = await _evaluate(scenario);
      final isWarning = scenario == 'expiredThenWarning';
      expect(result['sameBanner'], isTrue);
      expect(result['bannerCount'], 1);
      expect(result['message'], isWarning ? _warning : _expired);
      expect(result['buttons'], isWarning ? ['延長する', '閉じる'] : ['閉じる']);
    });
  }

  for (final url in [
    '/campusweb/report.do',
    '$_origin/campusweb/theme/default/Help.html',
    '/campusweb/theme/default/Timeout.html.bak',
    '/campusweb/theme/default/TimeoutAlert.html/extra',
    '/campusweb/theme/other/Timeout.html',
    '',
  ]) {
    test('$url preserves the original open arguments and return value',
        () async {
      final result = await _evaluate('passthrough', url: url);
      expect(result['openCalls'], [
        {
          'window': 'top',
          'args': [url, 'report-window', 'width=750,height=240', true],
        },
      ]);
      expect(result['sameReturnValue'], isTrue);
      expect(result['sameArguments'], isTrue);
      expect(result['sameReceiver'], isTrue);
      expect(result['bannerCount'], 0);
    });
  }

  test('reinjection preserves both wrappers and attaches one load listener',
      () async {
    final result = await _evaluate('popup', injections: 2);
    expect(result['sameTopWrapper'], isTrue);
    expect(result['sameFrameWrapper'], isTrue);
    expect(result['listenerCount'], 1);
    expect(result['bannerCount'], 1);
    expect(result['openCalls'], isEmpty);
  });

  for (final scenario in ['iframePopup', 'iframeReload', 'iframeExtend']) {
    test('$scenario intercepts iframe popups in the top document', () async {
      final result = await _evaluate(scenario, injections: 2);
      expect(result['openCalls'], isEmpty);
      expect(result['frameBannerCount'], 0);
      expect(result['listenerCount'], 1);
      if (scenario == 'iframeExtend') {
        expect(result['extendCalls'], 1);
        expect(result['extendThisIsWindow'], isTrue);
        expect(result['bannerCount'], 0);
      } else {
        expect(result['message'], _warning);
        expect(result['bannerCount'], 1);
      }
    });
  }

  test('other iframe popups preserve arguments, receiver and return value',
      () async {
    final result = await _evaluate('iframePassthrough');
    expect(result['openCalls'], [
      {
        'window': 'frame',
        'args': [
          '/campusweb/report.do',
          'report-window',
          'width=750,height=240',
          true,
        ],
      },
    ]);
    expect(result['sameArguments'], isTrue);
    expect(result['sameReceiver'], isTrue);
    expect(result['sameReturnValue'], isTrue);
    expect(result['bannerCount'], 0);
  });

  for (final scenario in ['noFrame', 'frameDenied', 'frameDeniedOnLoad']) {
    test('$scenario still intercepts top document popups', () async {
      final result = await _evaluate(scenario);
      expect(result['openCalls'], isEmpty);
      expect(result['message'], _warning);
      expect(result['bannerCount'], 1);
    });
  }
}

Future<Map<String, dynamic>> _evaluate(String scenario,
    {String? url, int injections = 1}) async {
  final directory =
      Directory.systemTemp.createTempSync('gakujo_timeout_popup_');
  try {
    final inputFile = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
          jsonEncode({
            'scripts':
                List.filled(injections, GakujoTimeoutPopupScript.build()),
            'scenario': scenario,
            'url': url,
          }),
          encoding: utf8);
    final result = await Process.run(
      'node',
      ['test/support/gakujo_timeout_popup_script_dom_harness.cts', inputFile.path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: 'Node failed: ${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}
