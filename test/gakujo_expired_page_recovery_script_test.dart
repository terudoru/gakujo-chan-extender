import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_expired_page_recovery_script.dart';
import 'package:test/test.dart';

const _origin = 'https://gakujo.iess.niigata-u.ac.jp';
const _flowStart = '$_origin/campusweb/campussquare.do?_flowId=KJW0001100-flow';
const _portal = '$_origin/campusweb/campusportal.do?page=main';

void main() {
  test('expired iframe replaces its location with the absolute flow start',
      () async {
    final result = await _evaluate('iframeExpired');
    expect(result['frameReplacements'], [_flowStart]);
    expect(result['topReplacements'], isEmpty);
    expect(result['stored'], {
      _recoveryKey('iframe', _flowStart): _recovery(_flowStart, [100000])
    });
  });

  test('expiry text never navigates away from nonempty student edits',
      () async {
    for (final scenario in ['iframeExpired', 'topExpired']) {
      for (final field in [
        {'tagName': 'TEXTAREA', 'value': 'draft', 'defaultValue': 'draft'},
        {'tagName': 'DIV', 'textContent': 'draft'},
        {'tagName': 'DIV', 'innerText': 'draft'},
        for (final type in [
          'text',
          'search',
          'email',
          'url',
          'tel',
          'password',
          'number',
        ])
          {'tagName': 'INPUT', 'type': type, 'value': '42', 'defaultValue': ''},
      ]) {
        final result = await _evaluate(scenario, field: field);
        expect(result['frameReplacements'], isEmpty,
            reason: '$scenario $field');
        expect(result['topReplacements'], isEmpty, reason: '$scenario $field');
        expect(result['stored'], isNull);
      }
      for (final field in [
        {'tagName': 'TEXTAREA', 'value': ''},
        {'tagName': 'DIV', 'textContent': ''},
        {
          'tagName': 'INPUT',
          'type': 'text',
          'value': 'default',
          'defaultValue': 'default',
        },
        {
          'tagName': 'INPUT',
          'type': 'hidden',
          'value': 'token',
          'defaultValue': '',
        },
      ]) {
        final result = await _evaluate(scenario, field: field);
        final replacements = scenario == 'iframeExpired'
            ? 'frameReplacements'
            : 'topReplacements';
        expect(result[replacements], hasLength(1));
      }
    }
  });

  test(
      'recovery guards survive storage errors and cap each target for two minutes',
      () async {
    for (final scope in ['iframe', 'top']) {
      for (final storageMode in [
        'available',
        'readDenied',
        'writeDenied',
        'denied',
        'deniedTop',
      ]) {
        final result = await _evaluate('${scope}RecoveryLimit',
            injections: 2, storageMode: storageMode);
        expect(result['recoveryCounts'], [1, 1, 2, 3, 3, 4],
            reason: '$scope $storageMode');
        expect(result['otherTargetRecoveries'], 1,
            reason: '$scope $storageMode');
        expect(result['listenerCount'], 1);
      }
    }
  });

  test('a normal load resets the budget so repeated Back keeps recovering',
      () async {
    final result = await _evaluate('repeatedBack');
    expect(result['repeatedBackCounts'], [2, 3, 4, 5, 6]);
  });

  test('different pages have independent budgets and old targets are pruned',
      () async {
    for (final storageMode in [
      'available',
      'readDenied',
      'writeDenied',
      'denied',
      'deniedTop',
    ]) {
      final result =
          await _evaluate('multipleTargets', storageMode: storageMode);
      expect(result['multiTargetCounts'], [4, 4, 5, 6, 6], reason: storageMode);
      expect(result['boundedTargetCount'], 20, reason: storageMode);
      expect(result['prunedTargetCount'], 1, reason: storageMode);
    }
  });

  for (final scenario in [
    'iframeNormal',
    'executionKey',
    'encodedExecutionKey',
    'otherOrigin',
    'missingSrc',
    'invalidSrc',
    'frameDenied',
    'topExpiredWithFrame',
  ]) {
    test('$scenario does not navigate or record a recovery', () async {
      final result = await _evaluate(scenario);
      expect(result['frameReplacements'], isEmpty);
      expect(result['topReplacements'], isEmpty);
      expect(result['stored'], isNull);
    });
  }

  test('reinjection attaches one listener and later iframe loads recover',
      () async {
    final result = await _evaluate('laterLoad', injections: 2);
    expect(result['listenerCount'], 1);
    expect(result['beforeLoad'], isEmpty);
    expect(result['frameReplacements'], [_flowStart]);
    expect(result['topReplacements'], isEmpty);
  });

  test('same target is recovered only once within ten seconds', () async {
    final result = await _evaluate('iframeExpired', injections: 2);
    expect(result['listenerCount'], 1);
    expect(result['frameReplacements'], [_flowStart]);
    expect(result['stored'], {
      _recoveryKey('iframe', _flowStart): _recovery(_flowStart, [100000])
    });
  });

  test('loop guard allows recovery again after ten seconds', () async {
    final result = await _evaluate('guardElapsed', injections: 2);
    expect(result['beforeLoad'], [_flowStart]);
    expect(result['frameReplacements'], [_flowStart, _flowStart]);
    expect(result['stored'], {
      _recoveryKey('iframe', _flowStart):
          _recovery(_flowStart, [100000, 110000])
    });
  });

  test('loop guard allows a different flow start immediately', () async {
    final result = await _evaluate('differentTarget');
    const otherFlow =
        '$_origin/campusweb/campussquare.do?_flowId=KJW0001200-flow';
    expect(result['frameReplacements'], [_flowStart, otherFlow]);
    expect(result['stored'], {
      _recoveryKey('iframe', _flowStart): _recovery(_flowStart, [100000]),
      _recoveryKey('iframe', otherFlow): _recovery(otherFlow, [100000]),
    });
  });

  for (final scenario in ['storageReadDenied', 'storageWriteDenied']) {
    test('$scenario still recovers the expired iframe', () async {
      final result = await _evaluate(scenario);
      expect(result['frameReplacements'], [_flowStart]);
      expect(result['topReplacements'], isEmpty);
    });
  }

  test('malformed stored recovery is replaced with a working loop guard',
      () async {
    final result = await _evaluate('malformedStorage', injections: 2);
    expect(result['frameReplacements'], [_flowStart]);
    expect(result['stored'], {
      _recoveryKey('iframe', _flowStart): _recovery(_flowStart, [100000])
    });
  });

  for (final scenario in [
    'topExpired',
    'topKanjiExpired',
    'topTitleOnly',
    'topInnerTextExpired',
    'topTextContentExpired',
    'topShortExpiryBody',
  ]) {
    test('$scenario without an iframe replaces the location with the portal',
        () async {
      final result = await _evaluate(scenario);
      expect(result['topReplacements'], [_portal]);
      expect(result['frameReplacements'], isEmpty);
      expect(result['stored'], {
        _recoveryKey('top', _portal): _recovery(_portal, [100000])
      });
    });
  }

  test('top-level recovery uses the same loop guard', () async {
    final result = await _evaluate('topExpired', injections: 2);
    expect(result['topReplacements'], [_portal]);
  });

  for (final scenario in [
    'topNormal',
    'topBodyBeyondLimit',
    'topExpiryNotice',
    'topLongExpiryBody',
  ]) {
    test('$scenario does not navigate', () async {
      final result = await _evaluate(scenario);
      expect(result['topReplacements'], isEmpty);
      expect(result['frameReplacements'], isEmpty);
      expect(result['stored'], isNull);
    });
  }
}

String _recoveryKey(String scope, String target) => jsonEncode([scope, target]);

Map<String, dynamic> _recovery(String target, List<int> attempts) => {
      'target': target,
      'at': attempts.last,
      'attempts': attempts,
    };

Future<Map<String, dynamic>> _evaluate(String scenario,
    {int injections = 1,
    Map<String, String>? field,
    String? storageMode}) async {
  final directory =
      Directory.systemTemp.createTempSync('gakujo_expired_page_recovery_');
  try {
    final inputFile = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
          jsonEncode({
            'scripts': List.filled(
                injections, GakujoExpiredPageRecoveryScript.build()),
            'scenario': scenario,
            'field': field,
            'storageMode': storageMode,
          }),
          encoding: utf8);
    final result = await Process.run(
      'node',
      ['test/support/gakujo_expired_page_recovery_script_dom_harness.cts', inputFile.path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: 'Node failed: ${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}
