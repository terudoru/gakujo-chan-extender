import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_quick_jump_script.dart';
import 'package:test/test.dart';

void main() {
  test('clicks syllabus link rather than the surrounding page container',
      () async {
    expect(
        await evaluate([
          {'id': 'wrapper', 'tag': 'div', 'text': 'HOME シラバス 成績'},
          {'id': 'syllabus', 'tag': 'a', 'text': 'シラバス'},
        ]),
        {
          'result': true,
          'clicked': ['syllabus']
        });
  });

  test('prefers the exact tab label over an earlier partial match', () async {
    expect(
        (await evaluate([
          {'id': 'help', 'tag': 'a', 'text': 'シラバスの使い方'},
          {'id': 'syllabus', 'tag': 'a', 'text': ' シラバス\n'},
        ]))['clicked'],
        ['syllabus']);
  });

  test('clicks plain portal tab cells without inline handlers', () async {
    for (final tab in {'si': '成績', 'rs': '履修'}.entries) {
      expect(
          await evaluate([
            {'id': 'static', 'tag': 'div', 'text': tab.value},
            {
              'id': 'tab-${tab.key}',
              'tag': 'div',
              'class': 'tabcell',
              'text': ' ${tab.value}\n',
            },
          ], label: tab.value),
          {
            'result': true,
            'clicked': ['tab-${tab.key}']
          });
    }
  });

  test('matches the half-width report tab with a full-width label', () async {
    expect(
        (await evaluate([
          {
            'id': 'tab-en',
            'tag': 'div',
            'class': 'tabcell',
            'text': 'ﾚﾎﾟｰﾄ・小ﾃｽﾄ・ｱﾝｹｰﾄ',
          },
        ], label: 'レポート'))['clicked'],
        ['tab-en']);
  });

  test('prefers an exact portal tab cell over an earlier partial link',
      () async {
    expect(
        (await evaluate([
          {'id': 'notification', 'tag': 'a', 'text': '成績登録通知'},
          {
            'id': 'tab-si',
            'tag': 'div',
            'class': 'tabcell',
            'text': '成績',
          },
        ], label: '成績'))['clicked'],
        ['tab-si']);
  });

  test('portal tabs outrank exact content links even with partial tab labels',
      () async {
    for (final tab in {
      'en': ('レポート', 'ﾚﾎﾟｰﾄ・小ﾃｽﾄ・ｱﾝｹｰﾄ'),
      'kj': ('連絡通知', '連絡通知一覧'),
    }.entries) {
      expect(
        (await evaluate([
          {'id': 'content-link', 'tag': 'a', 'text': tab.value.$1},
          {
            'id': 'tab-${tab.key}',
            'tag': 'div',
            'class': 'tabcell',
            'parent': {'id': 'tabmenutable'},
            'text': tab.value.$2,
          },
        ], label: tab.value.$1))['clicked'],
        ['tab-${tab.key}'],
      );
    }
  });

  test('ignores hidden and disabled entries and text inputs', () async {
    expect(
        (await evaluate([
          {'id': 'hidden', 'tag': 'a', 'text': 'シラバス', 'hidden': true},
          {'id': 'disabled', 'tag': 'button', 'text': 'シラバス', 'disabled': true},
          {'id': 'input', 'tag': 'input', 'type': 'text', 'value': 'シラバス'},
          {'id': 'syllabus', 'tag': 'button', 'text': 'シラバス参照'},
        ]))['clicked'],
        ['syllabus']);
  });

  test('never opens a message whose title exactly matches the quick jump',
      () async {
    for (final attribute in ['href', 'onclick']) {
      for (final action in [
        'campussquare.do?seqNo=507762',
        'campussquare.do?_eventId=confirm',
        'campussquare.do?_eventId=displayMidoku',
      ]) {
        final message = {
          'id': 'message',
          'tag': attribute == 'onclick' ? 'div' : 'a',
          'text': 'レポート',
          attribute: action,
        };
        expect(await evaluate([message], label: 'レポート'),
            {'result': false, 'clicked': []});
        expect(
            (await evaluate([
              message,
              {'id': 'reports', 'tag': 'a', 'text': 'レポート・小テスト'},
            ], label: 'レポート'))['clicked'],
            ['reports']);
      }
    }
  });

  test('ignores app controls and actions inside app-owned containers',
      () async {
    for (final ownership in [
      {'id': 'mbg-shortcut'},
      {'class': 'other mbg-shortcut'},
      {'data-mbg-shortcut': 'true'},
    ]) {
      for (final nested in [false, true]) {
        expect(
            await evaluate([
              {
                'id': 'control',
                'tag': 'button',
                'text': 'シラバス',
                if (nested) 'parent': ownership else ...ownership,
              },
            ]),
            {'result': false, 'clicked': []});
      }
    }
  });

  test('uses image labels and searches child frames', () async {
    expect(
        (await evaluate([], frames: [
          [
            {'id': 'syllabus', 'tag': 'a', 'imageAlt': 'シラバス'},
          ]
        ]))['clicked'],
        ['syllabus']);
  });

  test('supports script tabs without treating static labels as actions',
      () async {
    expect(
        (await evaluate([
          {'id': 'static', 'tag': 'span', 'text': 'シラバス'},
          {
            'id': 'syllabus',
            'tag': 'td',
            'text': 'シラバス',
            'onclick': 'openTab()'
          },
        ]))['clicked'],
        ['syllabus']);
    expect(
        await evaluate([
          {'id': 'static', 'tag': 'span', 'text': 'シラバス'},
        ]),
        {'result': false, 'clicked': []});
  });
}

Future<Map<String, dynamic>> evaluate(List<Map<String, dynamic>> nodes,
    {String label = 'シラバス',
    List<List<Map<String, dynamic>>> frames = const []}) async {
  final result = await Process.run(
      'node',
      [
        '-e',
        harness,
        jsonEncode({'nodes': nodes, 'frames': frames}),
        GakujoQuickJumpScript.build(label),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  expect(result.exitCode, 0, reason: result.stderr as String);
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const harness = r'''
const vm = require('node:vm');
const spec = JSON.parse(process.argv[1]);
const clicked = [];
function windowFor(specs) {
  const element = spec => ({
    ...spec, innerText: spec.text || '', textContent: spec.text || '',
    attributes: Object.keys(spec).map(name => ({name})),
    parentElement: spec.parent ? element(spec.parent) : null,
    getAttribute: name => spec[name] || null,
    matches: selector => selector === ':disabled' && !!spec.disabled,
    closest: () => spec.inert || spec.ariaDisabled ? {} : null,
    getClientRects: () => spec.hidden ? [] : [{}],
    querySelectorAll: () => spec.imageAlt ? [{getAttribute: () => spec.imageAlt}] : [],
    click: () => clicked.push(spec.id),
  });
  const nodes = specs.map(element);
  const win = {frames: [], getComputedStyle: node => ({visibility: node.visibility || 'visible'})};
  win.document = {defaultView: win, querySelectorAll: selector => nodes.filter(node =>
    selector.includes('td, div, span') || ['a','button'].includes(node.tag) ||
    selector.includes('div.tabcell') && node.tag === 'div' &&
      (node.class || '').split(/\s+/).includes('tabcell') ||
    node.tag === 'input' && ['button','submit','image'].includes(node.type) ||
    ['tab','button','menuitem'].includes(node.role) || !!node.onclick
  )};
  return win;
}
const window = windowFor(spec.nodes);
window.frames = spec.frames.map(windowFor);
const result = vm.runInNewContext(process.argv[2], {window});
process.stdout.write(JSON.stringify({result, clicked}));
''';
