import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_message_list_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_message_star_script.dart';
import 'package:test/test.dart';

const _title = '情報セキュリティ概論 第4回 授業資料';
const _period = '2026/10/22 13:57から 2026/11/05 13:57まで';
const _rowText = '2026/10/22 14:00:54 $_title - 授業連絡 (工) 落合 博幸 $_period';

void main() {
  test('desktop fetch and page scan retain the desktop row text and URLs',
      () async {
    final fetched =
        await _evaluate('fetch', 'desktop', [gakujoMessageListFetchScript]);
    final scanned = await _evaluate('scan', 'desktop', [
      GakujoMessageStarScript.build(),
      _pageScanScript(),
      _pageScanScript(),
    ]);
    expect(fetched['result']['status'], 'ok');
    expect((fetched['result']['items'] as List).length, 60);
    final items = scanned['scans'][0]['messageItems'] as List;
    expect(items.length, 160);
    expect(fetched['result']['items'][0], items.first);
    expect(items.first['title'], _title);
    expect(items.first['text'],
        '2026/10/22 14:00:54 $_title - 授業連絡 工学部 落合 博幸 2026/10/22 13:57～2026/11/05 13:57');
    expect(
        Uri.parse(items.first['url'] as String)
            .queryParameters['_flowExecutionKey'],
        'desktop key');
  });

  for (final scenario in [
    'unread',
    'genre',
    'singleDigitDate',
    'officeSender'
  ]) {
    test('smartphone $scenario fetch keeps title, flow key and posted time',
        () async {
      final result =
          await _evaluate('fetch', scenario, [gakujoMessageListFetchScript]);
      expect(result['result']['status'], 'ok');
      final items = result['result']['items'] as List;
      expect(items.length, 60);
      final item = items.first as Map;
      expect(item.keys, unorderedEquals(['title', 'url', 'text']));
      expect(item['title'], _title);
      expect(
          item['text'],
          scenario == 'singleDigitDate'
              ? _rowText.replaceFirst(
                  '2026/10/22 14:00:54', '2026/01/02 14:00:54')
              : scenario == 'officeSender'
                  ? _rowText.replaceFirst('(工) 落合 博幸', '学務部 教務課')
                  : _rowText);
      expect(
          RegExp(r'^([0-9]{4})/([0-9]{1,2})/([0-9]{1,2})\s+([0-9]{1,2}):([0-9]{2})')
              .hasMatch(item['text'] as String),
          isTrue);
      expect(Uri.parse(item['url'] as String).queryParameters, {
        '_flowExecutionKey': 'mobile key',
        '_eventId': scenario == 'genre' ? 'confirm' : 'displayMidoku',
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '508182',
      });
      expect(
          item['url'],
          startsWith(
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?'));
      expect(result['requests'], [
        {
          'method': 'GET',
          'url': '/campusweb/campussquare.do?_flowId=KJW0001100-flow',
          'async': false
        }
      ]);
    });
  }

  for (final scenario in [
    'missing',
    'noMessageLabel',
    'httpError',
    'networkError'
  ]) {
    test('smartphone fetch rejects $scenario', () async {
      final result =
          await _evaluate('fetch', scenario, [gakujoMessageListFetchScript]);
      expect(result['result'], {
        'status': scenario.endsWith('Error') ? 'error' : 'missing',
        'items': []
      });
    });
  }

  test(
      'smartphone page scan uses p titles with stars installed, including frames',
      () async {
    for (final scenario in ['unread', 'iframe', 'topWithIframe']) {
      final result = await _evaluate('scan', scenario, [
        GakujoMessageStarScript.build(),
        _pageScanScript(),
        _pageScanScript(),
      ]);
      expect(result['scans'][0], result['scans'][1]);
      final items = result['scans'][0]['messageItems'] as List;
      expect(items.length, 160);
      expect(items.first['title'], _title);
      expect(items.first['text'], _rowText);
      expect(Uri.parse(items.first['url'] as String).queryParameters['seqNo'],
          '508182');
      expect(items.map((item) => item['url']).toSet().length, 160);
    }
  });

  for (final scenario in [
    'unread',
    'genre',
    'officeSender',
    'iframe',
    'topWithIframe',
    'sameDocument',
    'inaccessibleIframe',
  ]) {
    test('smartphone $scenario stars stay inside actions and stop navigation',
        () async {
      final result = await _evaluate('list', scenario, [
        GakujoMessageStarScript.build(),
        GakujoMessageStarScript.buildRefresh(['1|40|508182']),
        GakujoMessageStarScript.build(starredIds: ['1|40|508182']),
        GakujoMessageStarScript.buildTeardown(),
        GakujoMessageStarScript.build(),
      ]);
      expect(result['counts'], [160, 160, 160, 0, 160]);
      expect(result['pressed'], ['false', 'true', 'true', null, 'false']);
      expect(result['inside'], isTrue);
      expect(result['beforeTitle'], isTrue);
      expect(result['prevented'], isTrue);
      expect(result['stopped'], isTrue);
      expect(result['navigations'], 0);
      expect(result['timerReadsUnchanged'], isTrue);
      expect(result['rowTextUnchanged'], isTrue);
      expect(result['intervalCounts'], [1, 1, 1, 0, 1]);
      expect(result['listenerCounts'], [1, 1, 1, 0, 1]);
      expect(result['styleCounts'], [1, 1, 1, 0, 1]);
      expect(result['listenerAddCounts'], [1, 1, 1, 1, 2]);
      if (scenario == 'topWithIframe' || scenario == 'iframe') {
        expect(result['otherListenerCounts'], [1, 1, 1, 0, 1]);
        expect(result['otherButtonCounts'], [0, 0, 0, 0, 0]);
      }
      expect((result['messages'] as List).single, {
        'action': 'toggle',
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '508182',
        'title': _title,
        'genre': '授業連絡',
        'sender': scenario == 'officeSender' ? '学務部 教務課' : '(工) 落合 博幸',
        'period': _period,
        'postedAt': '2026/10/22 14:00:54',
        'body': '',
      });
    });
  }

  for (final scenario in [
    'attachment',
    'remembered',
    'longBody',
    'topWithIframe',
    'iframe',
  ]) {
    test('smartphone $scenario detail extracts fields and stable identity',
        () async {
      final result = await _evaluate('detail', scenario, [
        GakujoMessageStarScript.build(starredIds: ['1|40|508182']),
        GakujoMessageStarScript.build(starredIds: ['1|40|508182']),
      ]);
      expect(result['counts'], [1, 1]);
      expect(result['messages'].length, 2);
      final detail = result['messages'][0];
      expect(detail, {
        'action': 'detail',
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '508182',
        'title': _title,
        'genre': '',
        'sender': '工学部 ／ 落合 博幸',
        'period': '',
        'postedAt': '2026/10/20 10:14:19',
        'body': scenario == 'longBody' ? '文' * 4000 : '本文の一行目\n二行目',
      });
      expect(result['messages'][1]['action'], 'toggle');
    });
  }

  test('both documents keep their own list buttons, data and listeners',
      () async {
    final result = await _evaluate('documents', 'bothDocuments', [
      GakujoMessageStarScript.build(),
      GakujoMessageStarScript.buildRefresh(['1|40|508182']),
      GakujoMessageStarScript.buildTeardown(),
      GakujoMessageStarScript.build(),
    ]);
    expect(result['counts'], [160, 160, 0, 160]);
    expect(result['otherButtonCounts'], [160, 160, 0, 160]);
    expect(result['listenerCounts'], [1, 1, 0, 1]);
    expect(result['otherListenerCounts'], [1, 1, 0, 1]);
    expect(result['styleCounts'], [1, 1, 0, 1]);
    expect(result['otherStyleCounts'], [1, 1, 0, 1]);
    expect(result['timerReadsUnchanged'], isTrue);
    expect(result['messages'][0]['title'], _title);
    expect(result['messages'][1]['title'], 'フレームの連絡通知');
    expect(result['rememberedTitles'], [_title, 'フレームの連絡通知']);
    expect(result['removedFrameListener'], isTrue);
    expect(result['removedFrameButtons'], 0);
    expect(result['remainingTopButtons'], 160);
  });

  test('both documents report each starred detail only once', () async {
    final result = await _evaluate('detail', 'bothDocuments', [
      GakujoMessageStarScript.build(starredIds: ['1|40|508182']),
      GakujoMessageStarScript.build(starredIds: ['1|40|508182']),
    ]);
    expect(result['counts'], [1, 1]);
    expect(result['otherButtonCounts'], [1, 1]);
    final details = (result['messages'] as List)
        .where((message) => message['action'] == 'detail')
        .toList();
    expect(details.map((message) => message['title']), ['フレームの連絡通知', _title]);
  });

  for (final scenario in ['unread', 'genre', 'topWithIframe']) {
    test(
        'smartphone $scenario title click remembers attachment-free detail on reload',
        () async {
      final result = await _evaluate('remember', scenario, [
        GakujoMessageStarScript.build(starredIds: ['1|40|508182'])
      ]);
      expect(result['capture'], isTrue);
      expect(result['remembered'], {
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '508182',
        'title': _title,
      });
      expect(result['navigations'], 1);
      expect(result['detailCounts'], [1, 1]);
      expect(result['oldListenerRemoved'], isTrue);
      expect(result['oldButtonCount'], 0);
      expect(
          (result['messages'] as List)
              .where((m) => m['action'] == 'detail')
              .length,
          2);
    });
  }

  for (final scenario in ['mismatch', 'storageDenied']) {
    test('smartphone detail does not guess identity with $scenario', () async {
      final result = await _evaluate(
          'detail', scenario, [GakujoMessageStarScript.build()]);
      expect(result['counts'], [0]);
      expect(result['messages'], isEmpty);
    });
  }
}

// Exercise the actual private page-scan script, including its shared helpers.
String _pageScanScript() {
  final source = File('lib/src/gakujo_web_app.dart').readAsStringSync();
  final start =
      source.indexOf('Future<_PageTextSnapshot?> _readPageTextForActivity()');
  final end = source.indexOf("''');", start);
  final parts = RegExp(r"r'''([\s\S]*?)'''")
      .allMatches(source.substring(start, end + 3))
      .map((match) => match.group(1)!)
      .toList();
  expect(parts.length, 3);
  return parts[0] +
      gakujoSmartphoneMessageRowsScript +
      parts[1] +
      gakujoAssignmentRowsScript +
      parts[2];
}

Future<Map<String, dynamic>> _evaluate(
    String mode, String scenario, List<String> scripts) async {
  final directory =
      Directory.systemTemp.createTempSync('gakujo_message_mobile_');
  try {
    final harness = File.fromUri(directory.uri.resolve('harness.cjs'))
      ..writeAsStringSync(
          File('test/support/gakujo_message_smartphone_harness.cjs')
              .readAsStringSync(),
          encoding: utf8);
    final input = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
          jsonEncode({'mode': mode, 'scenario': scenario, 'scripts': scripts}),
          encoding: utf8);
    final result = await Process.run('node', [harness.path, input.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: 'Node failed: ${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}
