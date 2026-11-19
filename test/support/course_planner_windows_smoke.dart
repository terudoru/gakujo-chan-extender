// Run test/support/course_planner_windows_smoke.ps1 from Windows.
// The fixture has no account, external requests, or production app storage.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:morebettergakujo_flutter/src/course_planner_page.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

import 'course_planner_windows_react_smoke.dart';

const fixturePacket = {
  'v': 1,
  'kind': 'grades',
  'tables': [
    {
      'heading': '単位修得状況照会',
      'rows': [
        ['開講番号', '科目名', '単位数', '評価'],
        ['261G7011', '合成科目', '1', '認定'],
      ],
    },
  ],
};

class _FixturePortal implements GakujoWebViewController {
  @override
  Future<Object?> runJavaScriptReturningResult(String script) async =>
      jsonEncode(fixturePacket);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Directory(Platform.environment['MBG_PLANNER_SMOKE_DIR']!);
  if (root.listSync().isNotEmpty) {
    throw StateError('A fresh fixture directory is required.');
  }
  final result = File('${root.path}/result.txt');
  final dist = Platform.environment['MBG_PLANNER_SMOKE_DIST'];
  if (dist != null && dist.isNotEmpty) {
    await runReactPlannerSmoke(root, Directory(dist), result);
    return;
  }
  final timer = Timer(const Duration(seconds: 45), () {
    result.writeAsStringSync('timeout');
    exit(1);
  });
  await windows.WebviewController.initializeEnvironment(
    userDataPath: '${root.path}/profile',
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (req.uri.path == '/planner/' && req.uri.query.isEmpty) {
      req.response.headers.contentType = ContentType.html;
      req.response.write(
        '''<!doctype html><html lang="ja"><meta charset="utf-8">
        <title>取り込み確認</title><main>準備中</main><script>
        setTimeout(() => {
          window.addEventListener('mbg:planner-import', e => {
            const p = e.detail;
            if (p.kind === 'grades' && p.tables[0].rows[1][1] === '合成科目' && !location.hash) {
              document.querySelector('main').textContent = '合成科目を確認';
              fetch('/received', {method:'POST',body:document.querySelector('main').innerText});
            }
          });
          window.addEventListener('mbg:planner-probe', () => window.dispatchEvent(new Event('mbg:planner-ready')));
          window.dispatchEvent(new Event('mbg:planner-ready'));
        }, 350);</script></html>''',
      );
    } else if (req.method == 'POST' &&
        req.uri.path == '/received' &&
        await utf8.decoder.bind(req).join() == '合成科目を確認') {
      result.writeAsStringSync('Verified Windows WebView2 planner review');
      await req.response.close();
      timer.cancel();
      await server.close(force: true);
      exit(0);
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  });
  runApp(
    MaterialApp(
      home: CoursePlannerPage(
        service: const WindowsGakujoWebViewService(),
        url: Uri.parse('http://127.0.0.1:${server.port}/planner/'),
        source: CoursePlannerSource(_FixturePortal(), () => true),
        kind: CoursePlannerImportKind.grades,
        onExternalLink: (_) =>
            throw StateError('Unexpected external navigation'),
      ),
    ),
  );
}
