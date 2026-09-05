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
    {List<List<Map<String, dynamic>>> frames = const []}) async {
  final result = await Process.run(
      'node',
      [
        '-e',
        harness,
        jsonEncode({'nodes': nodes, 'frames': frames}),
        GakujoQuickJumpScript.build('シラバス'),
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
  const nodes = specs.map(spec => ({
    ...spec, innerText: spec.text || '', textContent: spec.text || '',
    getAttribute: name => spec[name] || null,
    matches: selector => selector === ':disabled' && !!spec.disabled,
    closest: () => spec.inert || spec.ariaDisabled ? {} : null,
    getClientRects: () => spec.hidden ? [] : [{}],
    querySelectorAll: () => spec.imageAlt ? [{getAttribute: () => spec.imageAlt}] : [],
    click: () => clicked.push(spec.id),
  }));
  const win = {frames: [], getComputedStyle: node => ({visibility: node.visibility || 'visible'})};
  win.document = {defaultView: win, querySelectorAll: selector => nodes.filter(node =>
    selector.includes('td, div, span') || ['a','button'].includes(node.tag) ||
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
