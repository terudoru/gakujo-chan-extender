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
  inputs: [username, password],
  querySelectorAll: function(selector) {
    return selector === 'input' ? this.inputs :
      this.inputs.filter(input => input.getAttribute('type') === 'password');
  }
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
form.inputs = [{value: 'id-by-name', getAttribute: name =>
  ({type: 'email', name: 'Login_ID'})[name] || null}, password];
for (const callback of listeners.submit) callback({target: form});
form.inputs = [{value: 'id-by-id', getAttribute: name =>
  ({type: 'text', id: 'J-Username'})[name] || null}, password];
for (const callback of listeners.submit) callback({target: form});
form.inputs = [username, password, password];
for (const callback of listeners.submit) callback({target: form});
for (const callback of listeners.click) callback({target: button});
form.inputs = [{value: 'other', getAttribute: name =>
  ({type: 'text', name: 'email'})[name] || null}, password];
for (const callback of listeners.submit) callback({target: form});
for (const callback of listeners.click) callback({target: button});
form.inputs = [{value: 'other', getAttribute: name =>
  ({type: 'text', name: 'notuserid'})[name] || null}, password];
for (const callback of listeners.submit) callback({target: form});
form.inputs = [username, password];
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
      {'type': 'gakujoLoginSubmitted', 'loginId': 'id-by-name'},
      {'type': 'gakujoLoginSubmitted', 'loginId': 'id-by-id'},
    ]);
  });
}
