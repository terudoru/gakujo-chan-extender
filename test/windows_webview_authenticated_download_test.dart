import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/windows_webview_authenticated_download.dart';
import 'package:test/test.dart';

void main() {
  test('an HTTP 200 HTML page fails an attachment fetch with the login message',
      () async {
    const id = 'expired-session';
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/file',
      method: 'GET',
      fileName: 'attachment.pdf',
      courseName: '',
      formFields: {},
    );
    final result = await Process.run(
        'node',
        [
          '-e',
          _webViewDownloadHarness,
          WindowsWebViewAuthenticatedDownloadScript.start(
              requestId: id, request: request),
          WindowsWebViewAuthenticatedDownloadScript.poll(id),
          WindowsWebViewAuthenticatedDownloadScript.cleanup(id),
          'Text/HTML; charset=UTF-8',
          '<html>login required</html>',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['state'], 'error');
    expect(behavior['code'], 'page_response');
    expect(
        behavior['message'], 'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください');
    expect(behavior['bodyBase64'], isEmpty);
    expect(behavior['afterCleanup'], isNull);
  });

  for (final (name, mimeType, body, disposition, rejected) in [
    ('attachment.pdf', 'text/html', '%PDF-1.7', '', false),
    ('notes.txt', 'text/plain', '<html> is an HTML tag', '', false),
    ('attachment.pdf', 'application/pdf', '<html>literal</html>', '', false),
    (
      'Download',
      'text/html',
      '<html>attachment</html>',
      'attachment; filename="page.HTM"',
      false,
    ),
    (
      'Download',
      'text/html',
      '<html>attachment</html>',
      "attachment; filename*=UTF-8''page%2Ehtm",
      false,
    ),
    ('page.HTML', 'text/html', '<html>attachment</html>', '', false),
    (
      'Download',
      'application/octet-stream',
      '\uFEFF \n<HtMl>login</HtMl>',
      '',
      true,
    ),
    (
      '',
      'application/xhtml+xml',
      '<!DoCtYpE hTmL><html>login</html>',
      '',
      true
    ),
    ('attachment.pdf', '', '<html lang="en">login</html>', '', true),
    ('attachment.pdf', 'text/html', '<htmlish>literal bytes', '', false),
    (
      'attachment.pdf',
      'text/html',
      '<!doctype htmlish>literal bytes',
      '',
      false
    ),
    ('attachment.pdf', 'text/html', '<html', '', false),
    (
      'attachment.pdf',
      'text/html',
      '\uFEFF\uFEFF<html>literal</html>',
      '',
      false
    ),
  ]) {
    test('Windows page policy: $name / $mimeType / $body / $disposition',
        () async {
      const id = 'response-policy';
      final request = GakujoDownloadRequest(
        url: 'https://gakujo.iess.niigata-u.ac.jp/file',
        method: 'GET',
        fileName: name,
        courseName: '',
        formFields: const {},
      );
      final result = await Process.run(
        'node',
        [
          '-e',
          _webViewDownloadHarness,
          WindowsWebViewAuthenticatedDownloadScript.start(
              requestId: id, request: request),
          WindowsWebViewAuthenticatedDownloadScript.poll(id),
          WindowsWebViewAuthenticatedDownloadScript.cleanup(id),
          mimeType,
          body,
          disposition,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final behavior =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(behavior['state'], rejected ? 'error' : 'done');
      if (rejected) {
        expect(behavior['code'], 'page_response');
        expect(behavior['bodyBase64'], isEmpty);
      } else {
        expect(behavior['bodyBase64'], base64Encode(utf8.encode(body)));
      }
      expect(behavior['afterCleanup'], isNull);
    });
  }

  test('large responses use bounded messages and pause for the receiver',
      () async {
    const requestId = 'large-download';
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/file',
      method: 'GET',
      fileName: 'fixture.bin',
      courseName: '',
      formFields: {},
    );
    final result = await Process.run(
        'node',
        [
          '-e',
          _largeDownloadHarness,
          WindowsWebViewAuthenticatedDownloadScript.start(
              requestId: requestId, request: request),
          WindowsWebViewAuthenticatedDownloadScript.poll(requestId),
          WindowsWebViewAuthenticatedDownloadScript.cleanup(requestId),
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['receivedBytes'], 8 * 1024 * 1024 + 13);
    expect(behavior['validBytes'], isTrue);
    expect(behavior['maximumMessageBytes'], lessThan(400 * 1024));
    expect(behavior['readBeforePolling'], lessThanOrEqualTo(2 * 1024 * 1024));
    expect(behavior['afterCleanup'], isNull);
  });

  test('cleanup aborts a pending fetch and discards a late result', () async {
    const requestId = 'cancelled-download';
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/file',
      method: 'GET',
      fileName: 'fixture.pdf',
      courseName: '',
      formFields: {},
    );
    final result = await Process.run(
        'node',
        [
          '-e',
          _cancellationHarness,
          WindowsWebViewAuthenticatedDownloadScript.start(
              requestId: requestId, request: request),
          WindowsWebViewAuthenticatedDownloadScript.poll(requestId),
          WindowsWebViewAuthenticatedDownloadScript.cleanup(requestId),
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['aborted'], isTrue);
    expect(behavior['afterCleanup'], isNull);
    expect(behavior['restarted'], isTrue);
    expect(behavior['lateResultIgnored'], isTrue);
  });

  test('starts fetch synchronously and exposes its result through polling',
      () async {
    const requestId = 'download-1';
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
          'campussquare.do?_flowId=SDW-filerefer-flow&fileId=41475',
      method: 'GET',
      courseName: '',
      fileName: '大学等への修学支援の措置に係る学修計画書.docx',
      formFields: {},
    );
    final result = await Process.run(
      'node',
      [
        '-e',
        _webViewDownloadHarness,
        WindowsWebViewAuthenticatedDownloadScript.start(
          requestId: requestId,
          request: request,
        ),
        WindowsWebViewAuthenticatedDownloadScript.poll(requestId),
        WindowsWebViewAuthenticatedDownloadScript.cleanup(requestId),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    expect(
      result.exitCode,
      0,
      reason: 'Node JavaScript evaluation failed: ${result.stderr}',
    );
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['started'], isTrue);
    expect(behavior['requestedUrl'], request.url);
    expect(behavior['requestMethod'], 'GET');
    expect(behavior['credentials'], 'include');
    expect(behavior['state'], 'done');
    expect(behavior['status'], 200);
    expect(behavior['bodyBase64'], 'AQID');
    expect(
        behavior['contentDisposition'], 'attachment; filename=internal.docx');
    expect(behavior['afterCleanup'], isNull);
  });
}

const _webViewDownloadHarness = r'''
const vm = require('node:vm');
const startScript = process.argv[1];
const pollScript = process.argv[2];
const cleanupScript = process.argv[3];

(async function() {
  let requestedUrl = '';
  let requestOptions = null;
  const window = {
    location: {
      href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do'
    }
  };
  const context = vm.createContext({
    window,
    URL,
    URLSearchParams,
    Uint8Array,
    AbortController,
    fetch: async function(url, options) {
      requestedUrl = url;
      requestOptions = options;
      return {
        status: 200,
        ok: true,
        url,
        headers: {
          get(name) {
            if (name === 'content-type') {
              return process.argv[4] ?? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
            }
            if (name === 'content-disposition') {
              return process.argv[6] ?? 'attachment; filename=internal.docx';
            }
            return null;
          }
        },
        body: {
          getReader() {
            const bytes = process.argv[5] === undefined ? Buffer.from([1, 2, 3]) :
              Buffer.from(process.argv[5], 'utf8');
            let offset = 0;
            return {
              async read() {
                if (offset === bytes.length) return {done: true};
                // Fragment even the BOM and tag across reader results.
                return {done: false, value: Uint8Array.from([bytes[offset++]])};
              },
              releaseLock() {}
            };
          }
        }
      };
    },
    btoa(binary) {
      return Buffer.from(binary, 'binary').toString('base64');
    }
  });

  const started = vm.runInContext(startScript, context);
  await new Promise((resolve) => setImmediate(resolve));
  let polled;
  const chunks = [];
  do {
    polled = JSON.parse(vm.runInContext(pollScript, context));
    if (polled.state === 'chunk') chunks.push(Buffer.from(polled.bodyBase64, 'base64'));
  } while (polled.state === 'chunk');
  vm.runInContext(cleanupScript, context);
  const afterCleanup = JSON.parse(vm.runInContext(pollScript, context));

  process.stdout.write(JSON.stringify({
    started,
    requestedUrl,
    requestMethod: requestOptions && requestOptions.method,
    credentials: requestOptions && requestOptions.credentials,
    state: polled && polled.state,
    code: polled && polled.code,
    message: polled && polled.message,
    status: polled && polled.payload && polled.payload.status,
    bodyBase64: Buffer.concat(chunks).toString('base64'),
    contentDisposition:
      polled && polled.payload && polled.payload.contentDisposition,
    afterCleanup
  }));
})();
''';

const _cancellationHarness = r'''
const vm = require('node:vm');
(async function() {
  const [start, poll, cleanup] = process.argv.slice(1);
  const pending = [];
  const context = vm.createContext({
    window: { location: { href: 'https://gakujo.iess.niigata-u.ac.jp/' } },
    URL, URLSearchParams, Uint8Array, AbortController,
    fetch(url, options) {
      return new Promise(resolve => pending.push({ url, options, resolve }));
    },
    btoa: binary => Buffer.from(binary, 'binary').toString('base64')
  });
  vm.runInContext(start, context);
  vm.runInContext(cleanup, context);
  const aborted = !!(pending[0].options.signal && pending[0].options.signal.aborted);
  const afterCleanup = JSON.parse(vm.runInContext(poll, context));
  const restarted = vm.runInContext(start, context);
  // Simulate a fetch that resolves despite cancellation; it must not overwrite
  // a later request that reuses the same identifier.
  pending[0].resolve({url: pending[0].url, ok: true, status: 200,
    headers: { get: () => '' }, arrayBuffer: async () => Uint8Array.from([1]).buffer});
  await new Promise(resolve => setImmediate(resolve));
  const afterLateResult = JSON.parse(vm.runInContext(poll, context));
  vm.runInContext(cleanup, context);
  process.stdout.write(JSON.stringify({aborted, afterCleanup, restarted,
    lateResultIgnored: afterLateResult && afterLateResult.state === 'pending'}));
})();
''';

const _largeDownloadHarness = r'''
const vm = require('node:vm');
(async function() {
  const [start, poll, cleanup] = process.argv.slice(1);
  const length = 8 * 1024 * 1024 + 13;
  let sourceOffset = 0, receivedBytes = 0, maximumMessageBytes = 0, validBytes = true;
  function makeBytes(size, offset) {
    const bytes = new Uint8Array(size);
    for (let i=0;i<size;i++) bytes[i] = (offset + i) % 251;
    return bytes;
  }
  const context = vm.createContext({
    window: {location: {href: 'https://gakujo.iess.niigata-u.ac.jp/'}},
    URL, URLSearchParams, Uint8Array, AbortController,
    fetch: async url => ({url, status: 200, ok: true, headers: {get: () => ''},
      arrayBuffer: async () => { sourceOffset=length; return makeBytes(length, 0).buffer; },
      body: { getReader: () => ({
        async read() {
          if (sourceOffset===length) return {done:true};
          const size=Math.min(65537, length-sourceOffset);
          const value=makeBytes(size, sourceOffset); sourceOffset+=size;
          return {value, done:false};
        },
        releaseLock() {}, async cancel() {}
      })}
    }),
    btoa: binary => Buffer.from(binary, 'binary').toString('base64')
  });
  vm.runInContext(start, context);
  await new Promise(resolve=>setImmediate(resolve));
  const readBeforePolling=sourceOffset;
  for (let attempts=0; attempts<1000; attempts++) {
    const raw=vm.runInContext(poll, context);
    maximumMessageBytes=Math.max(maximumMessageBytes, Buffer.byteLength(raw));
    const state=JSON.parse(raw);
    if (state.state==='error') throw Error(state.message);
    const encoded=state.state==='chunk' ? state.bodyBase64 : state.payload && state.payload.bodyBase64;
    if (encoded) {
      const bytes=Buffer.from(encoded,'base64');
      for(let i=0;i<bytes.length;i++) if(bytes[i] !== (receivedBytes+i)%251) validBytes=false;
      receivedBytes+=bytes.length;
    }
    if(state.state==='done') break;
    await new Promise(resolve=>setImmediate(resolve));
  }
  vm.runInContext(cleanup,context);
  process.stdout.write(JSON.stringify({receivedBytes,validBytes,maximumMessageBytes,
    readBeforePolling,afterCleanup:JSON.parse(vm.runInContext(poll,context))}));
})();
''';
