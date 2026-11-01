import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_login_observer_script.dart';
import 'package:test/test.dart';

void main() {
  test('reports only a nonempty login ID on submit and button click', () async {
    final result = await Process.run('node', [
      '-e',
      r'''
const vm = require('vm');
const listeners = {};
const messages = [];
const username = {
  value: '  student-123  ',
  getAttribute: name => ({type: 'text', name: 'userid'})[name] || null
};
const password = {
  get value() { throw new Error('password was read'); },
  getAttribute: name => name === 'type' ? 'password' : null
};
const form = {
  querySelector: () => password,
  querySelectorAll: () => [username, password]
};
const button = {
  tagName: 'BUTTON', form,
  getAttribute: () => null,
  closest: () => button
};
const context = {
  window: {GakujoMessageStars: {postMessage: value => messages.push(JSON.parse(value))}},
  document: {addEventListener: (type, callback) => {
    (listeners[type] ||= []).push(callback);
  }}
};
vm.createContext(context);
vm.runInContext(process.argv[1], context);
vm.runInContext(process.argv[1], context);
for (const callback of listeners.submit) callback({target: form});
for (const callback of listeners.click) callback({target: button});
username.value = '   ';
for (const callback of listeners.submit) callback({target: form});
for (const callback of listeners.click) callback({target: button});
process.stdout.write(JSON.stringify(messages));
''',
      GakujoLoginObserverScript.build(),
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(jsonDecode(result.stdout as String), [
      {'type': 'gakujoLoginSubmitted', 'loginId': 'student-123'},
      {'type': 'gakujoLoginSubmitted', 'loginId': 'student-123'},
    ]);
  });
}
