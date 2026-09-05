import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/windows_webview_authenticated_download.dart';
import 'package:test/test.dart';

void main() {
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
              return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
            }
            if (name === 'content-disposition') {
              return 'attachment; filename=internal.docx';
            }
            return null;
          }
        },
        async arrayBuffer() {
          return Uint8Array.from([1, 2, 3]).buffer;
        }
      };
    },
    btoa(binary) {
      return Buffer.from(binary, 'binary').toString('base64');
    }
  });

  const started = vm.runInContext(startScript, context);
  await new Promise((resolve) => setImmediate(resolve));
  const polled = JSON.parse(vm.runInContext(pollScript, context));
  vm.runInContext(cleanupScript, context);
  const afterCleanup = JSON.parse(vm.runInContext(pollScript, context));

  process.stdout.write(JSON.stringify({
    started,
    requestedUrl,
    requestMethod: requestOptions && requestOptions.method,
    credentials: requestOptions && requestOptions.credentials,
    state: polled && polled.state,
    status: polled && polled.payload && polled.payload.status,
    bodyBase64: polled && polled.payload && polled.payload.bodyBase64,
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
