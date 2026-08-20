import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<Map<String, dynamic>> evaluateAutofillScriptLifecycle({
  required String markerPrefix,
  required String buildScript,
  required String teardownScript,
}) async {
  final result = await Process.run('node', [
    '-e',
    _nodeHarness,
    markerPrefix,
    buildScript,
    teardownScript,
  ]);

  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const _nodeHarness = r'''
const vm = require('node:vm');
const markerPrefix = process.argv[1];
const buildScript = process.argv[2];
const teardownScript = process.argv[3];

function createPage() {
  let nextTimeoutId = 1;
  const activeTimeouts = new Map();
  const sessionValues = new Map();
  const document = {
    body: {innerText: '', textContent: ''},
    defaultView: null,
    querySelector() { return null; },
    querySelectorAll(selector) {
      if (selector === 'iframe, frame' || selector === 'input') {
        return [];
      }
      return [];
    }
  };
  const window = {
    document,
    sessionStorage: {
      getItem(key) { return sessionValues.get(key) || null; },
      setItem(key, value) { sessionValues.set(key, String(value)); }
    },
    setTimeout(callback) {
      const id = nextTimeoutId++;
      activeTimeouts.set(id, callback);
      return id;
    },
    clearTimeout(id) { activeTimeouts.delete(id); }
  };
  window.window = window;
  document.defaultView = window;
  const context = {
    window,
    document,
    location: {
      href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do',
      origin: 'https://gakujo.iess.niigata-u.ac.jp',
      pathname: '/campusweb/campussmart.do'
    },
    console: {log() {}}
  };

  function snapshot() {
    return {
      activeTimeoutCount: activeTimeouts.size,
      globalMarkers: Object.keys(window)
        .filter((key) => key.startsWith(markerPrefix))
        .sort()
    };
  }

  function flushTimeouts() {
    const callbacks = [...activeTimeouts.values()];
    activeTimeouts.clear();
    for (const callback of callbacks) callback();
  }

  return {context, snapshot, flushTimeouts};
}

function run(script, page) {
  vm.runInNewContext(script, page.context);
}

const page = createPage();
run(buildScript, page);
const afterBuild = page.snapshot();
run(teardownScript, page);
const afterTeardown = page.snapshot();
page.flushTimeouts();
const afterFlush = page.snapshot();
run(buildScript, page);
const afterRebuild = page.snapshot();

const freshPage = createPage();
run(teardownScript, freshPage);
const teardownWithoutBuild = freshPage.snapshot();

process.stdout.write(JSON.stringify({
  afterBuild,
  afterTeardown,
  afterFlush,
  afterRebuild,
  teardownWithoutBuild
}));
''';
