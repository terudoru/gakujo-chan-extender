import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_message_reader_script.dart';
import 'package:test/test.dart';

import 'support/page_script_dom_harness.dart';

void main() {
  test('builds bulk message read controls', () {
    final script = GakujoMessageReaderScript.build();

    expect(script, contains('__MBG_MESSAGE_READER_VERSION'));
    expect(script, contains("document.getElementById('main-frame-if')"));
    expect(script, contains('|| document'));
    expect(script, contains("doc.querySelector('table.normal:nth-child(9)')"));
    expect(script, contains('指定した個数を既読にする'));
    expect(script, contains('既読にする数(半角数字)'));
    expect(script, contains("credentials: 'include'"));
    expect(script, contains('if (response.ok)'));
    expect(script, contains('markReadWithFrame(url)'));
    expect(script, contains('location.reload()'));
  });

  test('matches original extension by reading the first requested rows', () {
    final script = GakujoMessageReaderScript.build();

    expect(
      script,
      contains('for (var i = 1; i < table.rows.length && urls.length < limit'),
    );
    expect(
      script,
      contains("var link = table.rows[i].querySelector('a[href]')"),
    );
    expect(script, isNot(contains('classList')));
    expect(script, isNot(contains('fontWeight')));
  });

  test('reloads after all requested messages are marked read', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 200, 200],
    );

    expect(result['fetchCallCount'], 3);
    expect(result['frameCallCount'], 0);
    expect(result['statusText'], '3件を既読にしました（失敗0件）');
    expect(result['reloadCount'], 1);
  });

  test('reports a non-2xx fetch without treating iframe load as success',
      () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 403],
      iframeOutcomes: [true],
    );

    expect(result['fetchCallCount'], 2);
    expect(result['frameCallCount'], 0);
    expect(result['statusText'], '1件を既読にしました（失敗1件）');
    expect(result['reloadCount'], 0);
  });

  test('an expired page answered with 200 is not counted as read', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 200],
      fetchBodies: [
        '<html><body>連絡通知</body></html>',
        '<html><head><title>ページの有効期限ぎれ</title></head>'
            '<body>ページの有効期限が過ぎています。</body></html>',
      ],
    );

    expect(result['statusText'], '1件を既読にしました（失敗1件）');
    expect(result['reloadCount'], 0);
  });

  test('a stalled response body times out and re-enables the read button',
      () async {
    for (final supportsAbortController in [true, false]) {
      final result = await evaluateMessageReaderScript(
        buildScript: GakujoMessageReaderScript.build(),
        fetchStatuses: [200],
        fetchBodies: [null],
        supportsAbortController: supportsAbortController,
      );

      expect(result['beforeTimeout']['buttonDisabled'], isTrue);
      expect(result['buttonDisabled'], isFalse);
      expect(result['statusText'], '0件を既読にしました（失敗1件）');
      expect(result['abortedFetchCount'], supportsAbortController ? 1 : 0);
      expect(result['frameCallCount'], 0);
      expect(result['reloadCount'], 0);
      expect(result['timeoutIds'], isEmpty);
    }
  });

  test('does not count the iframe initial about:blank load as success',
      () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [null],
      iframeOutcomes: [false],
    );

    expect(result['fetchCallCount'], 1);
    expect(result['frameCallCount'], 1);
    expect(result['statusText'], '0件を既読にしました（失敗1件）');
    expect(result['reloadCount'], 0);
  });

  test('owns the visible result status for teardown', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200],
    );

    expect(result['statusOwned'], 'true');
    expect(result['controlIds'], contains('mbg-read-status'));
  });

  test('does not reload or fetch for an empty or invalid count', () async {
    for (final input in ['', '0', '-1', 'invalid', '0.5']) {
      final result = await evaluateMessageReaderScript(
        buildScript: GakujoMessageReaderScript.build(),
        fetchStatuses: [200],
        inputValue: input,
      );
      expect(result['fetchCallCount'], 0, reason: input);
      expect(result['reloadCount'], 0, reason: input);
    }
  });

  test('resolves query-only links against the owning document', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200],
      messageUrls: ['?_flowId=notice-flow&_eventId=detail'],
    );

    expect(result['fetchUrls'], [
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do'
          '?_flowId=notice-flow&_eventId=detail',
    ]);
  });

  test('resolves document-relative links against the owning document',
      () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200],
      messageUrls: ['message/1'],
      owningDocument: {
        'baseURI':
            'https://gakujo.iess.niigata-u.ac.jp/campusweb/notices/list.do',
        'locationHref':
            'https://gakujo.iess.niigata-u.ac.jp/campusweb/ignored.do',
      },
    );

    expect(result['fetchUrls'], [
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/notices/message/1',
    ]);
  });

  test('keeps root-relative and absolute allowed links unchanged', () async {
    const absoluteUrl =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/message/2';
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 200],
      messageUrls: [
        '/campusweb/message/1',
        absoluteUrl,
      ],
    );

    expect(result['fetchUrls'], [
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/message/1',
      absoluteUrl,
    ]);
  });

  test('falls back to the fixed base when the owning document has no base',
      () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200],
      messageUrls: ['message/1'],
      owningDocument: {
        'baseURI': null,
        'locationHref': 'not a usable URL',
      },
    );

    expect(result['fetchUrls'], [
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/message/1',
    ]);
  });

  test('ignores links that cannot identify an allowed notification page',
      () async {
    for (final url in [
      'https://example.com/message',
      'javascript:alert(1)',
      'https://[invalid',
      '#',
      'https://gakujo.iess.niigata-u.ac.jp:8443/message',
      'https://user:pass@gakujo.iess.niigata-u.ac.jp/message',
    ]) {
      final result = await evaluateMessageReaderScript(
        buildScript: GakujoMessageReaderScript.build(),
        fetchStatuses: [200],
        messageUrls: [url],
      );
      expect(result['fetchCallCount'], 0, reason: url);
      expect(result['fetchUrls'], isEmpty, reason: url);
      expect(result['frameCallCount'], 0, reason: url);
      expect(result['reloadCount'], 0, reason: url);
    }

    final disallowedBaseResult = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200],
      messageUrls: ['message/1'],
      owningDocument: {
        'baseURI': 'https://example.com/notifications/list.do',
      },
    );
    expect(disallowedBaseResult['fetchCallCount'], 0);
    expect(disallowedBaseResult['fetchUrls'], isEmpty);
    expect(disallowedBaseResult['frameCallCount'], 0);
    expect(disallowedBaseResult['reloadCount'], 0);
  });

  test('a single tap only asks for confirmation', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 200],
      clickCount: 0,
    );
    expect(result['fetchCallCount'], 0);
    expect(result['reloadCount'], 0);
  });

  test('coalesces repeated clicks while a read is pending', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 200],
      clickCount: 2,
    );
    expect(result['fetchCallCount'], 2);
    expect(result['reloadCount'], 1);
    expect(result['statusText'], '2件を既読にしました（失敗0件）');
  });

  test('changing the count requires confirmation of the new count', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 200, 200],
      inputValue: '1',
      inputValueAfterArming: '3',
    );

    expect(result['afterArming']['buttonText'], startsWith('1件'));
    final rearmed = result['afterCountChange'] as Map;
    expect(rearmed['fetchCallCount'], 0);
    expect(rearmed['frameCallCount'], 0);
    expect(rearmed['buttonText'], '3件を既読にする（もう一度押して確定）');
    expect(rearmed['timeoutIds'], hasLength(1));
    expect(rearmed['timeoutIds'], isNot(result['afterArming']['timeoutIds']));
    expect(result['fetchCallCount'], 3);
    expect(result['statusText'], '3件を既読にしました（失敗0件）');
    expect(result['reloadCount'], 1);
  });

  for (final frame in ['empty', 'list', 'none', 'inaccessible']) {
    test('reads the first three smartphone unread messages (frame: $frame)',
        () async {
      final result = await _evaluateSmartphoneReader(frame: frame);

      expect(result['wrapperIsPreviousSibling'], isTrue);
      expect(result['wrapperCount'], 1);
      expect(result['controlIdsInWrapper'], [
        'mbg-read-button',
        'mbg-read-num-input',
        'mbg-read-status',
      ]);
      expect(result['controlsOutsideMessageRows'], isTrue);
      expect(result['controlsVisibleAfterFirstRowHidden'], isTrue);
      expect(result['buttonText'], '指定した個数を既読にする');
      expect(result['inputType'], 'number');
      expect(result['defaultValue'], '5');
      expect(result['statusLive'], 'polite');
      expect(result['frameUrls'], [
        for (var index = 1; index <= 3; index += 1)
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/mobile/'
              'campussquare.do?_flowExecutionKey=mobile%20key'
              '&_eventId=displayMidoku&keijitype=1&genrecd=40&seqNo=$index',
      ]);
      expect(result['statusText'], '3件を既読にしました（失敗0件）');
      expect(result['reloadCount'], 1);
      expect(result['ownedElementCount'], 4);
      expect(result['ownedAfterTeardown'], 0);
    });

    test('does not add controls to a smartphone genre list (frame: $frame)',
        () async {
      final result =
          await _evaluateSmartphoneReader(frame: frame, unread: false);

      expect(result['wrapperCount'], 0);
      expect(result['controlIdsInWrapper'], isEmpty);
      expect(result['frameUrls'], isEmpty);
      expect(result['ownedElementCount'], 0);
      expect(result['reloadCount'], 0);
    });
  }

  test('smartphone controls stay outside the only unread message row',
      () async {
    final result = await _evaluateSmartphoneReader(messageUrls: ['?seqNo=1']);

    expect(result['wrapperIsPreviousSibling'], isTrue);
    expect(result['controlsOutsideMessageRows'], isTrue);
    expect(result['controlsVisibleAfterFirstRowHidden'], isTrue);
    expect(result['frameUrls'], [
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/mobile/list.do?seqNo=1',
    ]);
  });

  test('smartphone onclick URLs retain the Gakujo origin restrictions',
      () async {
    final result = await _evaluateSmartphoneReader(messageUrls: [
      'https://example.com/message?seqNo=1',
      'javascript:alert(1)?seqNo=2',
      'https://gakujo.iess.niigata-u.ac.jp:8443/message?seqNo=3',
      'https://user:pass@gakujo.iess.niigata-u.ac.jp/message?seqNo=4',
      '?seqNo=5',
      '/campusweb/message?seqNo=6',
    ]);

    expect(result['frameUrls'], [
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/mobile/list.do?seqNo=5',
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/message?seqNo=6',
    ]);
    expect(result['statusText'], '2件を既読にしました（失敗0件）');
  });

  test('disabling during a read prevents further requests and late controls',
      () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 200, 200],
      teardownScript: GakujoMessageReaderScript.buildTeardown(),
      teardownDuringRead: true,
    );
    expect(result['fetchCallCount'], 1);
    expect(result['reloadCount'], 0);
    expect(result['ownedElementCount'], 0);
  });

  test('disabling after reading cancels the delayed page reload', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200],
      teardownScript: GakujoMessageReaderScript.buildTeardown(),
      teardownAfterRead: true,
    );
    expect(result['reloadCount'], 0);
    expect(result['ownedElementCount'], 0);
  });

  test('teardown stops polling, removes controls, and is idempotent', () async {
    final result = await evaluatePageScriptLifecycle(
      feature: 'message',
      buildScript: GakujoMessageReaderScript.build(),
      teardownScript: GakujoMessageReaderScript.buildTeardown(),
    );
    final afterBuild = result['afterBuild'] as Map<String, dynamic>;
    final afterTeardown = result['afterTeardown'] as Map<String, dynamic>;
    final afterRebuild = result['afterRebuild'] as Map<String, dynamic>;
    final teardownWithoutBuild =
        result['teardownWithoutBuild'] as Map<String, dynamic>;

    expect(afterBuild['activeIntervalCount'], 1);
    expect(afterBuild['ownedElementCount'], 3);
    expect(afterBuild['controlIds'], [
      'mbg-read-button',
      'mbg-read-num-input',
      'mbg-read-status',
    ]);
    expect(afterTeardown['activeIntervalCount'], 0);
    expect(afterTeardown['ownedElementCount'], 0);
    expect(afterTeardown['controlIds'], isEmpty);
    expect(afterTeardown['globalMarkers'], isEmpty);
    expect(afterRebuild['activeIntervalCount'], 1);
    expect(afterRebuild['ownedElementCount'], 3);
    expect(teardownWithoutBuild['activeIntervalCount'], 0);
    expect(teardownWithoutBuild['ownedElementCount'], 0);
  });
}

Future<Map<String, dynamic>> _evaluateSmartphoneReader({
  String frame = 'empty',
  bool unread = true,
  List<String>? messageUrls,
}) async {
  final directory =
      Directory.systemTemp.createTempSync('gakujo_message_reader_mobile_');
  try {
    final harness = File.fromUri(directory.uri.resolve('harness.cjs'))
      ..writeAsStringSync(_smartphoneReaderHarness, encoding: utf8);
    final input = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
        jsonEncode({
          'script': GakujoMessageReaderScript.build(),
          'teardown': GakujoMessageReaderScript.buildTeardown(),
          'frame': frame,
          'unread': unread,
          'messageUrls': messageUrls,
        }),
        encoding: utf8,
      );
    final result = await Process.run('node', [harness.path, input.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: 'Node failed: ${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}

const _smartphoneReaderHarness = r'''
const vm = require('node:vm');
const options = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const owned = '[data-mbg-message-reader-owned="true"]';
const frameUrls = [], timers = new Map(), intervals = new Map();
let timerId = 0, reloadCount = 0;

class Element {
  constructor(tag, doc) {
    this.tagName = tag.toUpperCase(); this.ownerDocument = doc;
    this.children = []; this.attributes = {}; this.listeners = {}; this.style = {};
  }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  getAttribute(name) { return this.attributes[name] ?? null; }
  addEventListener(name, callback) { this.listeners[name] = callback; }
  appendChild(node) { return this.insertBefore(node, null); }
  insertBefore(node, before) {
    if (node.parentNode) node.remove();
    const index = before ? this.children.indexOf(before) : this.children.length;
    if (index < 0) throw new Error('Reference node is not a child');
    this.children.splice(index, 0, node); node.parentNode = this;
    if (node.tagName === 'IFRAME' && node.src) {
      frameUrls.push(node.src); node.onload();
    }
    return node;
  }
  remove() {
    if (this.parentNode) this.parentNode.children.splice(this.parentNode.children.indexOf(this), 1);
    this.parentNode = null;
  }
  closest(selector) {
    for (let node = this; node; node = node.parentNode) {
      if (node.tagName.toLowerCase() === selector) return node;
    }
    return null;
  }
  contains(node) { return node === this || elements(this).includes(node); }
}

function elements(root) {
  return root.children.flatMap(child => [child, ...elements(child)]);
}
function add(parent, tag) { return parent.appendChild(new Element(tag, parent.ownerDocument)); }
function makeDocument(hasList) {
  const doc = {
    baseURI: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/' +
      (hasList ? 'mobile/list.do' : 'empty/frame.do'),
    location: {href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/ignored.do'},
    createElement(tag) { return new Element(tag, doc); },
    getElementById(id) {
      if (id === 'main-frame-if') return doc.frame || null;
      return elements(doc.body).find(node => node.id === id) || null;
    },
    querySelector() { return null; }, // No desktop table or tab menu.
    querySelectorAll(selector) {
      if (selector === 'div.button[onclick*="seqNo="]') {
        return elements(doc.body).filter(node => node.tagName === 'DIV' &&
          node.getAttribute('class') === 'button' && node.getAttribute('onclick').includes('seqNo='));
      }
      if (selector === owned) return elements(doc.body).filter(node =>
        node.getAttribute('data-mbg-message-reader-owned') === 'true');
      throw new Error('Unexpected selector: ' + selector);
    }
  };
  doc.body = new Element('body', doc);
  doc.body.textContent = hasList ? (options.unread ? '連絡通知 未読一覧' : '連絡通知 授業連絡') : '';
  if (hasList) {
    const navigation = add(doc.body, 'table');
    add(navigation, 'tr');
    const urls = options.messageUrls || [1, 2, 3, 4].map(seqNo =>
      'campussquare.do?_flowExecutionKey=mobile%20key&_eventId=' +
      (options.unread ? 'displayMidoku' : 'confirm') + '&keijitype=1&genrecd=40&seqNo=' + seqNo);
    doc.listTable = add(doc.body, 'table');
    const listBody = add(doc.listTable, 'tbody');
    doc.messageRows = [];
    for (const [index, url] of urls.entries()) {
      const row = add(listBody, 'tr');
      doc.messageRows.push(row);
      add(row, 'td').setAttribute('class', 'category-frame');
      const itemTable = add(add(row, 'td'), 'table');
      itemTable.setAttribute('class', 'bgnone');
      const button = add(add(add(add(itemTable, 'tbody'), 'tr'), 'td'), 'div');
      button.setAttribute('class', 'button');
      const quote = index % 2 ? '"' : "'";
      button.setAttribute('onclick', 'location.href=' + quote + url.replace(/&/g, '&amp;') + quote);
    }
  }
  return doc;
}

const document = makeDocument(options.frame !== 'list');
let frameDocument;
if (options.frame === 'empty' || options.frame === 'list') {
  frameDocument = makeDocument(options.frame === 'list');
  document.frame = {contentWindow: {document: frameDocument}};
} else if (options.frame === 'inaccessible') {
  document.frame = {get contentWindow() { throw new Error('Cross-origin frame'); }};
}
const docs = frameDocument ? [document, frameDocument] : [document];
const listDoc = options.frame === 'list' ? frameDocument : document;
const context = {
  document, URL, location: {reload() { reloadCount += 1; }},
  fetch: async () => { throw new Error('Use the fake iframe fallback'); },
  setInterval(fn) { intervals.set(++timerId, fn); return timerId; },
  clearInterval(id) { intervals.delete(id); },
  setTimeout(fn) { timers.set(++timerId, fn); return timerId; },
  clearTimeout(id) { timers.delete(id); }
};
context.window = context;
vm.createContext(context);

async function main() {
  vm.runInContext(options.script, context);
  vm.runInContext(options.script, context);
  for (const callback of intervals.values()) callback();
  listDoc.messageRows[0].style.display = 'none'; // The exclude filter hides this message.
  const input = listDoc.getElementById('mbg-read-num-input');
  const button = listDoc.getElementById('mbg-read-button');
  if (input) input.value = '3';
  if (button) {
    // The first tap only asks for confirmation.
    await button.listeners.click();
    await button.listeners.click();
  }
  for (const callback of [...timers.values()]) callback();
  const status = listDoc.getElementById('mbg-read-status');
  const table = listDoc.listTable;
  const wrapper = listDoc.getElementById('mbg-read-controls');
  const controls = listDoc.querySelectorAll(owned);
  const result = {
    wrapperIsPreviousSibling: !!wrapper &&
      table.parentNode.children[table.parentNode.children.indexOf(table) - 1] === wrapper,
    wrapperCount: controls.filter(node => node.id === 'mbg-read-controls').length,
    controlIdsInWrapper: wrapper ? wrapper.children.map(node => node.id) : [],
    controlsOutsideMessageRows: controls.every(node =>
      !listDoc.messageRows.some(row => row.contains(node))),
    controlsVisibleAfterFirstRowHidden: controls.length > 0 && controls.every(node => {
      for (let current = node; current; current = current.parentNode) {
        if (current.style.display === 'none') return false;
      }
      return true;
    }),
    buttonText: button?.textContent, inputType: input?.type, defaultValue: input?.defaultValue,
    statusLive: status?.getAttribute('aria-live'), statusText: status?.textContent,
    frameUrls, reloadCount, ownedElementCount: docs.reduce((sum, doc) => sum + doc.querySelectorAll(owned).length, 0)
  };
  vm.runInContext(options.teardown, context);
  result.ownedAfterTeardown = docs.reduce((sum, doc) => sum + doc.querySelectorAll(owned).length, 0);
  process.stdout.write(JSON.stringify(result));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
''';
