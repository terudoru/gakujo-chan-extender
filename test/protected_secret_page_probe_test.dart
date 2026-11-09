import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/protected_secret_page_probe.dart';
import 'package:test/test.dart';

void main() {
  test('login probe finds visible passwords in accessible frames only', () async {
    expect(await probe(ProtectedSecretPageProbe.login(), {}), isFalse);
    expect(await probe(ProtectedSecretPageProbe.login(), {'type': 'password'}), isTrue);
    expect(await probe(ProtectedSecretPageProbe.login(), {'type': 'password', 'hidden': true}), isFalse);
    expect(await probe(ProtectedSecretPageProbe.login(), {'type': 'password', 'name': 'ninshocode'}), isFalse);
    expect(await probe(ProtectedSecretPageProbe.login(), {'frame': {'type': 'password'}}), isTrue);
  });

  test('two factor probe finds the code field', () async {
    expect(await probe(ProtectedSecretPageProbe.twoFactor(), {}), isFalse);
    expect(await probe(ProtectedSecretPageProbe.twoFactor(), {'name': 'ninshoCode'}), isTrue);
    expect(await probe(ProtectedSecretPageProbe.twoFactor(), {'frame': {'name': 'ninshoCode'}}), isTrue);
  });
}

Future<bool> probe(String script, Map<String, Object> fixture) async {
  const harness = r'''
const fixture = JSON.parse(process.argv[2]);
function makeWindow(data) {
  const win = {getComputedStyle: () => ({display: data.hidden ? 'none' : 'block', visibility: 'visible', opacity: '1'})};
  const input = {ownerDocument: null, getClientRects: () => [1], getAttribute: (key) => data[key] || null};
  const doc = {defaultView: win, querySelectorAll: (selector) => {
    if (selector === 'input') return data.type || data.name ? [input] : [];
    if (selector.startsWith('input[name=')) return data.name === 'ninshoCode' ? [input] : [];
    if (selector === 'iframe, frame') return data.frame ? [{contentWindow: makeWindow(data.frame)}] : [];
    return [];
  }};
  input.ownerDocument = doc;
  win.document = doc;
  return win;
}
global.window = makeWindow(fixture);
console.log(JSON.stringify(eval(process.argv[1])));
''';
  final result = await Process.run('node', ['-e', harness, script, jsonEncode(fixture)]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return jsonDecode(result.stdout as String) as bool;
}
