// Companion to course_planner_windows_smoke.ps1 -PlannerDist <directory>.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:morebettergakujo_flutter/src/course_planner_page.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

// Public offering in 教育学部 (03), with a deliberately conflicting synthetic transcript.
const _course = '情報通信技術教育論I';
const _code = '261K0501';

// CoursePlannerPage still constructs and configures its own Windows controller.
// Observe it at the point where the production service builds the real widget.
class _ObservedWindowsView extends WindowsGakujoWebViewService {
  final ready = Completer<GakujoWebViewController>();

  @override
  Widget buildWidget(
    GakujoWebViewController controller, {
    ValueChanged<String>? onError,
  }) {
    if (!ready.isCompleted) ready.complete(controller);
    return super.buildWidget(controller, onError: onError);
  }
}

Future<void> _waitFor(GakujoWebViewController view, String expression) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 15)) {
    if (await view.runJavaScriptReturningResult(expression) == true) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Condition was not reached');
}

Future<void> _check(GakujoWebViewController view, String expression) async {
  if (await view.runJavaScriptReturningResult(expression) != true) {
    throw StateError('Unexpected fixture state');
  }
}

Future<CoursePlannerSource> _openSyntheticPortal(Directory root) async {
  final portal = Directory('${root.path}/portal');
  final pages = await Directory('${portal.path}/campusweb')
      .create(recursive: true);
  const host = 'gakujo.iess.niigata-u.ac.jp';
  // WebView2 serves these local HTML files on the mapped origin. replaceState
  // gives each document its portal servlet path without making an HTTP request.
  await File('${pages.path}/index.html').writeAsString('''<!doctype html>
    <meta charset="utf-8"><script>history.replaceState(null,"","campusportal.do")</script>
    <iframe title="照会画面" src="grades.html"></iframe>''');
  await File('${pages.path}/grades.html').writeAsString('''<!doctype html>
    <meta charset="utf-8"><script>history.replaceState(null,"","campussquare.do")</script>
    <h1>単位修得状況照会</h1><form id="taniReferListForm"></form>
    <table><tr><th>開講番号</th><th>科目名</th><th>配当単位数</th><th>修得単位数</th><th>評価</th><th>年度</th>
    <th>開講所属</th><th>学生所属</th><th>担当教員</th></tr>
    <tr><td>$_code</td><td>$_course</td><td>1</td><td>1</td><td>優</td><td>2026</td>
    <td>人文学部</td><td>教育学部</td><td>PRIVATE-COLUMN-CANARY</td></tr>
    <tr><td>269K9001</td><td>合成最終評価</td><td>2</td><td>0</td><td>不可</td><td>2026</td>
    <td>教育学部</td><td></td><td></td></tr>
    <tr><td>259K9002</td><td>合成矛盾評価</td><td>2</td><td>1</td><td>不可</td><td>2025</td>
    <td>教育学部</td><td></td><td></td></tr></table>
    <table><tr><th>開講番号</th><th>科目名</th><th>取得単位数</th><th>評価</th><th>年度</th><th>開講所属</th></tr>
    <tr><td>260K0363</td><td>現代教育学概論</td><td>0</td><td>不可</td><td>2026</td><td>教育学部</td></tr>
    <tr><td>250K0363</td><td>現代教育学概論</td><td>0</td><td>不可</td><td>2025</td><td>教育学部</td></tr></table>''');
  final inner = windows.WebviewController();
  final controller = WindowsGakujoWebViewController(inner);
  await controller.setJavaScriptModeUnrestricted();
  await inner.setSize(const Size(900, 600));
  await inner.addVirtualHostNameMapping(
    host,
    portal.path,
    windows.WebviewHostResourceAccessKind.deny,
  );
  await controller.loadUrl('https://$host/campusweb/index.html');
  await _waitFor(
    controller,
    '''document.querySelector('iframe')?.contentDocument
    ?.querySelector('#taniReferListForm + table')?.rows.length === 4''',
  );
  final source = CoursePlannerSource(controller, () => true);
  final choices = await source.choices();
  if (choices.length != 1 || choices.single != CoursePlannerImportKind.grades) {
    throw StateError('The portal fixture must offer a grade import');
  }
  return source;
}

Future<HttpServer> _serveBuild(Directory dist) async {
  final assets = <String, File>{};
  await for (final entry in dist.list(recursive: true, followLinks: false)) {
    if (entry is! File) continue;
    final name = entry.path
        .substring(dist.path.length)
        .split(Platform.pathSeparator)
        .where((part) => part.isNotEmpty)
        .join('/');
    assets['/planner/$name'] = entry;
  }
  assets['/planner/'] = assets['/planner/index.html']!;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    try {
      final file = assets[request.uri.path];
      if (request.headers.host != '127.0.0.1' ||
          file == null ||
          !const {'GET', 'HEAD'}.contains(request.method)) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final extension = file.path.split('.').last.toLowerCase();
      response.headers.contentType = switch (extension) {
        'html' => ContentType.html,
        'js' || 'mjs' => ContentType('text', 'javascript'),
        'css' => ContentType('text', 'css'),
        'json' || 'map' => ContentType.json,
        'svg' => ContentType('image', 'svg+xml'),
        'png' || 'webp' => ContentType('image', extension),
        'woff' || 'woff2' => ContentType('font', extension),
        _ => ContentType.binary,
      };
      if (request.method == 'GET') await response.addStream(file.openRead());
    } finally {
      await response.close();
    }
  });
  return server;
}

Future<void> runReactPlannerSmoke(
  Directory root,
  Directory dist,
  File result,
) async {
  var stage = 'initializing private WebView2 profile';
  void fail() {
    result.writeAsStringSync('Failed while $stage');
    exit(1);
  }

  final syncProject = Platform.environment['MBG_PLANNER_SMOKE_SYNC_PROJECT'];
  final sync = syncProject != null && syncProject.isNotEmpty;
  final timer = Timer(Duration(seconds: sync ? 240 : 75), fail);
  try {
    await windows.WebviewController.initializeEnvironment(
      userDataPath: '${root.path}/profile',
      additionalArguments: [
        '--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"',
        if (sync)
          '--remote-debugging-address=127.0.0.1 --remote-debugging-port=0',
      ].join(' '),
    );
    runApp(const SizedBox.shrink());
    stage = 'binding the local synthetic portal table';
    final source = await _openSyntheticPortal(root);
    stage = 'serving the supplied planner build';
    final server = await _serveBuild(dist);
    final view = _ObservedWindowsView();
    final url = Uri.parse('http://127.0.0.1:${server.port}/planner/');
    runApp(
      MaterialApp(
        home: CoursePlannerPage(
          service: view,
          url: url,
          source: source,
          kind: CoursePlannerImportKind.grades,
          onExternalLink: (_) => fail(),
        ),
      ),
    );
    final planner = await view.ready.future;
    const dialog =
        '''document.querySelector('dialog[open], [role="dialog"]')''';
    const checkbox =
        '''$dialog?.querySelector('input[type="checkbox"][aria-label*="$_course"]')''';
    const finalGrade =
        '''$dialog?.querySelector('input[type="checkbox"][aria-label*="合成最終評価"]')''';
    const conflict =
        '''$dialog?.querySelector('input[type="checkbox"][aria-label*="合成矛盾評価"]')''';
    const grades =
        '''(JSON.parse(localStorage.getItem('mbg.course-planner.v1'))?.grades ?? [])''';
    const noneSaved = '$grades.length === 0';
    const saved =
        '''(() => {
      const rows = $grades, g = rows[0];
      return rows.length === 1 && g.title === '$_course' && g.code === '$_code' &&
        g.grade === '優' && g.credits === 1 && String(g.year) === '2026' &&
        g.offeringDepartment === '人文学部' && g.matchedCourse === null &&
        !JSON.stringify(g).includes('PRIVATE-COLUMN-CANARY');
    })()''';
    String button(int count) =>
        '''Array.from($dialog?.querySelectorAll('button') ?? [])
      .find(b => b.textContent.includes('選択した$count件を取り込む'))''';
    stage = 'loading the compiled React planner';
    await _waitFor(
      planner,
      '''Boolean(document.querySelector('#planner-main'))''',
    );
    stage = 'waiting for the React import review for the captured course';
    await _waitFor(
      planner,
      '''Boolean($checkbox && $dialog.innerText.includes('$_code') &&
      $dialog.innerText.includes('260K0363') && $dialog.innerText.includes('250K0363') &&
      $dialog.innerText.includes('$_course') && $dialog.innerText.includes('優'))''',
    );
    stage = 'checking that receipt did not select or persist the grade';
    await _check(
      planner,
      '''(!$checkbox.disabled && !$checkbox.checked &&
      $finalGrade?.disabled === false && !$finalGrade.checked &&
      $conflict?.disabled === true && !$conflict.checked &&
      (${button(0)}?.matches(':disabled, [aria-disabled="true"]') === true) && $noneSaved)''',
    );
    await planner.runJavaScript('$finalGrade.click()');
    await _waitFor(planner, '''Boolean($finalGrade.checked && ${button(1)})''');
    await _check(planner, noneSaved);
    await planner.runJavaScript('$finalGrade.click()');
    await _waitFor(planner, '''Boolean(!$finalGrade.checked && ${button(0)})''');
    await planner.runJavaScript('$checkbox.click()');
    stage = 'checking that row selection alone did not persist the grade';
    await _waitFor(planner, '''Boolean($checkbox.checked && ${button(1)} &&
      !${button(1)}.matches(':disabled, [aria-disabled="true"]'))''');
    await _check(planner, noneSaved);
    stage = 'confirming the selected row and checking the saved grade';
    await planner.runJavaScript('${button(1)}.click()');
    await _waitFor(planner, '(!$dialog && $saved)');
    stage =
        'verifying a fresh planner document and persisted grade after reload';
    await planner.runJavaScript('document.__fixtureBeforeReload = true');
    await planner.reload();
    await _waitFor(
      planner,
      '''!document.__fixtureBeforeReload &&
      Boolean(document.querySelector('#planner-main')) && !$dialog && $saved''',
    );
    stage = 'reading the saved grade in the reloaded planner history';
    await planner.runJavaScript(
      '''Array.from(document.querySelectorAll('nav button'))
      .find(b => b.getClientRects().length && b.textContent.trim() === '単位・要件')?.click()''',
    );
    const history =
        '''document.querySelector('[role="radio"][data-value="history"]')''';
    await _waitFor(planner, 'Boolean($history)');
    await planner.runJavaScript('$history.click()');
    await _waitFor(planner, '''Array.from(document.querySelectorAll('main li'))
      .filter(li => li.getClientRects().length && ['$_course','$_code','2026','優','1単位']
        .every(value => li.innerText.includes(value))).length === 1''');
    await source.controller.dispose();
    if (sync) {
      stage = 'opening the isolated Windows and Chrome relay driver';
      // Identify this Flutter-owned planner document before attaching to the
      // ephemeral DevTools endpoint inside its fresh WebView2 profile.
      final random = Random.secure();
      final marker = base64Url.encode(
        List<int>.generate(18, (_) => random.nextInt(256)),
      );
      await planner.runJavaScript(
        'document.__mbgSmokeHost = ${jsonEncode(marker)}',
      );
      final driver = await Process.run(
        'node',
        [
          Platform.environment['MBG_PLANNER_SMOKE_SYNC_DRIVER']!,
          syncProject,
          root.path,
          url.toString(),
          marker,
        ],
        environment: {'DEBUG': '', 'PWDEBUG': '0'},
      );
      final proof = driver.stdout.toString().trim();
      if (driver.exitCode != 0 || proof != 'PASS') {
        if (RegExp(r'^FAIL [a-z -]{1,100}$').hasMatch(proof)) {
          stage = proof.substring(5);
        }
        fail();
      }
    }
    await server.close(force: true);
    timer.cancel();
    result.writeAsStringSync(
      sync
          ? 'Verified WebView2 and Chrome relay edits, history consent and withdrawal'
          : 'Verified Windows WebView2 React planner capture, consent and persisted grade after reload',
    );
    exit(0);
  } on Object {
    fail();
  }
}
