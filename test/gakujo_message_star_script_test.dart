import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_message_star_script.dart';
import 'package:test/test.dart';

void main() {
  for (final scenario in [
    'unread',
    'genre',
    'allGenre',
    'missingHeaders',
    'iframe',
  ]) {
    test('$scenario list stars precede titles and do not open messages',
        () async {
      final result = await _evaluate(
          'test/support/gakujo_message_star_script_star_dom_harness.cts',
          [
            GakujoMessageStarScript.build(),
            GakujoMessageStarScript.buildRefresh(['1|40|507762']),
            GakujoMessageStarScript.build(starredIds: ['1|40|507762']),
            GakujoMessageStarScript.buildTeardown(),
            GakujoMessageStarScript.build(),
          ],
          scenario);
      expect(result['beforeTitle'], isTrue);
      expect(result['prevented'], isTrue);
      expect(result['stopped'], isTrue);
      expect(result['label'], 'スター: 授業のお知らせ');
      expect(result['buttonTitle'], 'スター: 授業のお知らせ');
      expect(result['counts'], [1, 1, 1, 0, 1]);
      expect(result['buttonTexts'], ['', '', '', null, '']);
      expect(result['pressedStates'], ['false', 'true', 'true', null, 'false']);
      expect(result['styleCounts'], [1, 1, 1, 0, 1]);
      expect(result['outerStyleCounts'],
          scenario == 'iframe' ? [0, 0, 0, 0, 0] : [1, 1, 1, 0, 1]);
      expect(
        (result['styleTexts'] as List).whereType<String>(),
        everyElement(allOf(
          contains('button[data-mbg-message-star]::before { content: "☆"; }'),
          contains(
              'button[data-mbg-message-star][aria-pressed="true"]::before { content: "★"; }'),
        )),
      );
      expect(result['rowTexts'], everyElement(result['originalRowText']));
      expect(result['originalRowText'], isNot(contains(RegExp('[☆★]'))));
      expect(result['intervalCounts'], [1, 1, 1, 0, 1]);
      expect(result['listenerCounts'], [1, 1, 1, 0, 1]);
      final payload = (result['messages'] as List).first as Map;
      expect(payload, {
        'action': 'toggle',
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '507762',
        'title': '授業のお知らせ',
        'genre': scenario == 'missingHeaders' ? '' : '授業連絡',
        'sender': scenario == 'allGenre' || scenario == 'missingHeaders'
            ? ''
            : scenario == 'genre'
                ? '担当教員'
                : '工学部 ／ 担当教員',
        'period': scenario == 'missingHeaders' ? '' : '2026/10/01～2026/11/01',
        'postedAt': scenario == 'missingHeaders' ? '' : '2026/10/01 09:00',
        'body': '',
      });
      expect(jsonEncode(payload), isNot(contains('_flowExecutionKey')));
      expect((result['messages'] as List).length, 1);
    });
  }

  test('unchanged list updates skip URL, row and header reads', () async {
    final result = await _evaluate(
        'test/support/gakujo_message_star_script_star_dom_harness.cts',
        [
          GakujoMessageStarScript.build(),
          GakujoMessageStarScript.buildRefresh(['1|40|507762']),
          GakujoMessageStarScript.build(starredIds: ['1|40|507762']),
        ],
        'largeList');
    expect(result['counts'], [160, 160, 160]);
    expect(result['pressedStates'], ['false', 'true', 'true']);
    expect(result['headerQueryCounts'], [1, 1, 1]);
    final urlReads = result['urlParseCounts'] as List;
    final cellReads = result['rowCellReadCounts'] as List;
    expect(urlReads.first, greaterThan(0));
    expect(urlReads, everyElement(urlReads.first));
    expect(cellReads.first, greaterThan(0));
    expect(cellReads, everyElement(cellReads.first));
    expect(result['timerReadsUnchanged'], isTrue);
    expect(result['headersAfterClick'], 2);
    expect((result['messages'] as List).single['title'], '更新された表題');
  });

  test('new rows use fresh table headers on the next update', () async {
    final result = await _evaluate(
        'test/support/gakujo_message_star_script_star_dom_harness.cts',
        [
          GakujoMessageStarScript.build(),
          GakujoMessageStarScript.buildRefresh([]),
        ],
        'growingList');
    expect(result['counts'], [1, 2]);
    expect(result['headerQueryCounts'], [1, 2]);
    expect(result['timerReadsUnchanged'], isTrue);
    expect((result['messages'] as List).single['seqNo'], '507763');
    expect((result['messages'] as List).single['sender'], '工学部');
  });

  test('reused message links refresh star identity, label and click payload',
      () async {
    final result = await _evaluate(
      'test/support/gakujo_message_star_script_star_dom_harness.cts',
      [
        GakujoMessageStarScript.build(starredIds: ['1|40|507762']),
        GakujoMessageStarScript.buildRefresh(['1|40|507762']),
        GakujoMessageStarScript.buildRefresh(['1|40|507763']),
      ],
      'reusedLink',
    );
    expect(result['counts'], [1, 1, 1]);
    expect(result['pressedStates'], ['true', 'false', 'true']);
    expect(result['reusedLabel'], 'スター: 別のお知らせ');
    expect(result['reusedButtonTitle'], 'スター: 別のお知らせ');
    expect(result['clickedPressed'], 'false');
    final toggles = (result['messages'] as List)
        .where((message) => message['action'] == 'toggle')
        .toList();
    expect(toggles.last['seqNo'], '507764');
    expect(toggles.last['title'], 'クリック直前のお知らせ');
    expect(result['clickedLabel'], 'スター: クリック直前のお知らせ');
  });

  for (final scenario in ['detail', 'detailAttachment']) {
    test('$scenario extracts saved text and stable identity', () async {
      final result = await _evaluate(
          'test/support/gakujo_message_star_script_star_dom_harness.cts',
          [
            GakujoMessageStarScript.build(starredIds: ['1|40|507762']),
            GakujoMessageStarScript.build(starredIds: ['1|40|507762']),
          ],
          scenario);
      expect(result['beforeTitle'], isTrue);
      expect(result['label'], 'スター: 授業のお知らせ');
      expect(result['buttonTitle'], 'スター: 授業のお知らせ');
      expect(result['buttonTexts'], ['', '']);
      expect(result['pressedStates'], ['true', 'true']);
      expect(result['styleCounts'], [1, 1]);
      final messages = result['messages'] as List;
      expect(messages.length, 2); // one silent refresh and one explicit toggle
      final detail = messages.first as Map;
      expect(detail['action'], 'detail');
      expect(detail['keijitype'], '1');
      expect(detail['genrecd'], '40');
      expect(detail['seqNo'], '507762');
      expect(detail['title'], '授業のお知らせ');
      expect(detail['genre'], '授業連絡通知 授業連絡');
      expect(detail['sender'], '担当教員');
      expect(detail['period'], '2026/10/01～2026/11/01');
      expect(detail['postedAt'], '2026/10/01 09:00');
      expect(detail['body'], '本文の一行目\n二行目');
      expect((messages.last as Map)['action'], 'toggle');
      final duplicateGenre = await _evaluate(
          'test/support/gakujo_message_star_script_star_dom_harness.cts',
          [
            GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
          ],
          'detailDuplicateGenre');
      expect((duplicateGenre['messages'] as List).first['genre'], '全学連絡通知');
    });
  }

  test('unstarred detail is not saved and long detail bodies are capped',
      () async {
    final unstarred = await _evaluate(
        'test/support/gakujo_message_star_script_star_dom_harness.cts', [GakujoMessageStarScript.build()], 'detail');
    expect((unstarred['messages'] as List).length, 1);
    expect((unstarred['messages'] as List).single['action'], 'toggle');
    final long = await _evaluate(
        'test/support/gakujo_message_star_script_star_dom_harness.cts',
        [
          GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
        ],
        'detailLong');
    expect(((long['messages'] as List).first['body'] as String).length, 4000);
  });

  test('iframe navigation discovers detail and releases old document styles',
      () async {
    final result = await _evaluate(
        'test/support/gakujo_message_star_script_star_dom_harness.cts',
        [
          GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
        ],
        'navigate');
    expect(result['navigatedTitle'], '授業のお知らせ [新着]');
    expect(result['navigatedButtonText'], '');
    expect(result['navigatedPressed'], 'true');
    expect(result['navigatedStyleCount'], 1);
    expect(result['oldListButtonCount'], 0);
    expect(result['oldListStyleCount'], 0);
    expect((result['messages'] as List).last['action'], 'detail');
    expect((result['messages'] as List).last['title'], '授業のお知らせ');
  });

  for (final scenario in ['rememberedUnread', 'rememberedGenre']) {
    test('$scenario title click resolves attachment-free detail and reload',
        () async {
      final result = await _evaluate(
          'test/support/gakujo_message_star_script_star_dom_harness.cts',
          [
            GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
          ],
          scenario);
      expect(result['capture'], isTrue);
      expect(result['rememberedBeforeClick'], isNull);
      expect(result['remembered'], {
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '507762',
        'title': '授業のお知らせ',
      });
      expect(result['oldListListenerRemoved'], isTrue);
      expect(result['navigatedButtonText'], '');
      expect(result['navigatedPressed'], 'true');
      expect(result['navigatedStyleCount'], 1);
      expect(result['reloadedButtonText'], '');
      expect(result['reloadedPressed'], 'true');
      expect(result['reloadedStyleCount'], 1);
      expect(result['oldDetailStyleCount'], 0);
      expect(result['rememberedAfterReload'], result['remembered']);
      final details = (result['messages'] as List)
          .where((message) => message['action'] == 'detail')
          .toList();
      expect(details.length, 2);
      for (final detail in details) {
        expect(detail['keijitype'], '1');
        expect(detail['genrecd'], '40');
        expect(detail['seqNo'], '507762');
        expect(detail['title'], '授業のお知らせ');
        expect(detail['body'], '本文の一行目\n二行目');
      }
    });
  }

  for (final scenario in ['rememberedMismatch', 'rememberedStorageDenied']) {
    test('$scenario does not resolve attachment-free detail', () async {
      final result = await _evaluate(
          'test/support/gakujo_message_star_script_star_dom_harness.cts',
          [
            GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
          ],
          scenario);
      expect(result['navigatedButtonText'], isNull);
      expect(result['navigatedPressed'], isNull);
      expect(result['navigatedStyleCount'], 0);
      expect(result['reloadedButtonText'], isNull);
      expect(result['reloadedPressed'], isNull);
      expect(result['reloadedStyleCount'], 0);
      expect((result['messages'] as List).length, 1);
      expect((result['messages'] as List).single['action'], 'toggle');
    });
  }

  for (final scenario in ['ok', 'smartphone', 'smartphoneMixedKeys']) {
    test('$scenario reopen rotates keys and checks the 500-row genre list',
        () async {
      final result = await _open(scenario);
      expect(result['result']['status'], 'ok');
      expect(result['beforeNavigationCount'], 3);
      final requests = (result['requests'] as List).cast<String>();
      expect(
          Uri.parse(requests[0]).queryParameters['_flowId'], 'KJW0001100-flow');
      expect(Uri.parse(requests[1]).queryParameters, {
        '_flowExecutionKey': 'first key',
        '_eventId': 'dispKeijiListGenre',
        'keijitype': '1',
        'genrecd': '40',
      });
      expect(Uri.parse(requests[2]).queryParameters, {
        '_flowExecutionKey': 'second-key',
        '_eventId': 'paging',
        '_displayCount': '500',
      });
      expect(Uri.parse(requests[3]).queryParameters, {
        '_flowExecutionKey': 'third-key',
        '_eventId': 'confirm',
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '507762',
      });
      expect(result['navigatedResponse'], 'detail response');
      expect(result['remembered'], {
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '507762',
        'title': '授業のお知らせ',
      });
    });
  }

  test('reopen still navigates when session storage is unavailable', () async {
    final result = await _open('storageDenied');
    expect(result['result']['status'], 'ok');
    expect(result['navigatedResponse'], 'detail response');
    expect(result['remembered'], isNull);
  });

  for (final scenario in ['laterPage', 'smartphoneLaterPage', 'offsetPage']) {
    test('reopen $scenario finds a star beyond the first 500 rows', () async {
      final result = await _open(scenario);
      expect(result['result']['status'], 'ok');
      expect(result['beforeNavigationCount'], 4);
      final requests = (result['requests'] as List).cast<String>();
      expect(Uri.parse(requests[3]).queryParameters, {
        '_flowExecutionKey': 'third-key',
        '_eventId': 'paging',
        '_displayOffset': '500',
        '_displayCount': '500',
      });
      expect(Uri.parse(requests[4]).queryParameters['_flowExecutionKey'],
          'page-3-key');
      expect(Uri.parse(requests[4]).queryParameters['_eventId'], 'confirm');
      expect(result['navigatedResponse'], 'detail response');
      expect(result['remembered']['seqNo'], '507762');
      expect(result['remembered']['title'], '授業のお知らせ');
    });
  }

  test('reopen reports gone only after exhausting the genre pages', () async {
    final result = await _open('pagedGone');
    expect(result['result']['status'], 'gone');
    expect(result['beforeNavigationCount'], 4);
    expect(result['remembered'], isNull);
    expect(
        (result['requests'] as List).any((request) =>
            Uri.parse(request as String).queryParameters['_eventId'] ==
            'confirm'),
        isFalse);
  });

  for (final scenario in [
    'pageLoop',
    'pageCap',
    'pageHttpError',
    'pageMissing'
  ]) {
    test('reopen $scenario stops without declaring the star gone', () async {
      final result = await _open(scenario);
      expect(result['result']['status'],
          scenario == 'pageMissing' ? 'missing' : 'error');
      expect(result['beforeNavigationCount'], scenario == 'pageCap' ? 22 : 4);
      expect(result['remembered'], isNull);
    });
  }

  for (final scenario in [
    'gone',
    'wrongGenre',
    'smartphoneGone',
    'smartphoneWrongGenre'
  ]) {
    test('reopen $scenario preserves saved text without opening a detail',
        () async {
      final result = await _open(scenario);
      expect(result['result']['status'], 'gone');
      expect((result['requests'] as List).length, 3);
      expect(result['remembered'], isNull);
    });
  }

  for (final scenario in ['missing0', 'missing1', 'missing2', 'otherOrigin']) {
    test('reopen $scenario asks for sign in', () async {
      final result = await _open(scenario);
      expect(result['result']['status'], 'missing');
      expect((result['requests'] as List).length,
          scenario == 'otherOrigin' ? 0 : int.parse(scenario.substring(7)) + 1);
    });
  }

  for (final scenario in ['httpError', 'systemError', 'noKey']) {
    test('reopen $scenario returns error without navigation', () async {
      final result = await _open(scenario);
      expect(result['result']['status'], 'error');
      expect((result['requests'] as List).length, 1);
    });
  }
}

Future<Map<String, dynamic>> _open(String scenario) => _evaluate(
    'test/support/gakujo_message_star_script_open_harness.cts',
    [
      GakujoMessageStarScript.buildOpen(
        keijitype: '1',
        genrecd: '40',
        seqNo: '507762',
      )
    ],
    scenario);

Future<Map<String, dynamic>> _evaluate(
    String harness, List<String> scripts, String scenario) async {
  final directory = Directory.systemTemp.createTempSync('gakujo_message_star_');
  try {
    final inputFile = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
          jsonEncode({'scripts': scripts, 'scenario': scenario}),
          encoding: utf8);
    final result = await Process.run('node', [harness, inputFile.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: 'Node failed: ${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}
