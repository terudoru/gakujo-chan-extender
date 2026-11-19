// Entrypoint of the standalone registration_assist_windows_smoke.ps1 host.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/registration_handoff.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

const _portal = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do';
const _grid = '$_portal?_flowId=RSW0001000-flow';
const _condition = '$_portal?_flowExecutionKey=e1s2&view=condition';
const _results = '$_portal?_flowExecutionKey=e1s3&view=results';
const _return = '$_portal?_flowExecutionKey=e1s4&view=grid';
const _code = '269G9001';
const _title = '合成科目';
const _import = '履修手帖の時間割を履修登録に入力';
const _copy = '学務の照会結果を履修手帖用にコピー';
const _skip = 'この科目を飛ばす';

void _check(bool passed, String message) {
  if (!passed) throw StateError(message);
}

Future<T> _waitFor<T>(FutureOr<T?> Function() read, String description) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 12)) {
    final value = await read();
    if (value != null) return value;
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  throw TimeoutException(description);
}

class _LocalOnly extends HttpOverrides {
  _LocalOnly(this.fail);
  final Never Function(Object) fail;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      fail('Unexpected Dart HTTP client');
}

class _PortalFixture {
  _PortalFixture(this.root, this.client, this.fail);

  final Directory root;
  final HttpClient client;
  final Never Function(Object) fail;
  final requests = <String>[];
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  late final WebSocket _socket;
  int _nextId = 0;

  Future<void> attach() async {
    final port = await _waitFor(() {
      for (final path in ['profile/EBWebView', 'profile']) {
        final file = File('${root.path}/$path/DevToolsActivePort');
        if (file.existsSync()) {
          final lines = file.readAsLinesSync();
          final port = lines.isEmpty ? null : int.tryParse(lines.first);
          if (port != null && port > 0 && port < 65536) return port;
        }
      }
      return null;
    }, 'Private DevTools port');
    final path = await _waitFor(() async {
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/json/list'),
      )).close();
      final targets =
          jsonDecode(await utf8.decoder.bind(response).join()) as List;
      final pages = targets
          .where((target) => target['type'] == 'page')
          .toList();
      if (pages.isEmpty) return null;
      _check(
        pages.length == 1 && pages.single['url'] == 'about:blank',
        'Expected a single blank WebView2 target',
      );
      final url = Uri.parse(pages.single['webSocketDebuggerUrl'] as String);
      _check(
        url.scheme == 'ws' &&
            url.host == '127.0.0.1' &&
            url.port == port &&
            url.path.startsWith('/devtools/page/'),
        'Unexpected DevTools endpoint',
      );
      return url.toString();
    }, 'Blank WebView2 target');
    _socket = await WebSocket.connect(path, customClient: client);
    _socket.listen(
      _onMessage,
      onError: fail,
      onDone: () => fail('DevTools disconnected'),
    );
    await send('Fetch.enable', {
      'patterns': [
        {'urlPattern': '*'},
      ],
    });
  }

  Future<Map<String, dynamic>> send(
    String method,
    Map<String, Object?> params,
  ) {
    final id = ++_nextId;
    final reply = _pending[id] = Completer<Map<String, dynamic>>();
    _socket.add(jsonEncode({'id': id, 'method': method, 'params': params}));
    return reply.future.timeout(const Duration(seconds: 8));
  }

  void _onMessage(dynamic raw) {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    final id = message['id'];
    if (id is int) {
      final reply = _pending.remove(id)!;
      if (message.containsKey('error')) {
        reply.completeError(StateError('${message['error']}'));
      } else {
        reply.complete(message['result'] as Map<String, dynamic>);
      }
    }
    if (message['method'] == 'Fetch.requestPaused') {
      unawaited(
        _respond(message['params'] as Map<String, dynamic>)
            .catchError((Object error) => fail(error)),
      );
    }
  }

  Future<void> _respond(Map<String, dynamic> event) async {
    final request = event['request'] as Map<String, dynamic>;
    final id = event['requestId'];
    final key = "${request['method']} ${request['url']}";
    const expected = [
      'GET $_grid',
      'GET $_condition',
      'POST $_results',
      'GET $_return',
    ];
    if (event['resourceType'] != 'Document' ||
        requests.length >= expected.length ||
        key != expected[requests.length]) {
      await send('Fetch.failRequest', {
        'requestId': id,
        'errorReason': 'BlockedByClient',
      });
      fail('Unexpected WebView2 request: $key');
    }
    final page = switch (requests.length) {
      0 => _gridHtml(false),
      1 => _conditionHtml,
      2 => _resultsHtml,
      _ => _gridHtml(true),
    };
    if (key == 'POST $_results') {
      final fields = Uri.splitQueryString(request['postData'] as String);
      _check(
        fields['code'] == _code &&
            fields['faculty'] == 'any' &&
            fields['title'] == 'keep' &&
            fields['day'] == '月' &&
            fields['period'] == '1限',
        'Unexpected search fields: $fields',
      );
    }
    requests.add(key);
    await send('Fetch.fulfillRequest', {
      'requestId': id,
      'responseCode': 200,
      'responseHeaders': [
        {'name': 'Content-Type', 'value': 'text/html; charset=utf-8'},
        {'name': 'Cache-Control', 'value': 'no-store'},
        {
          'name': 'Content-Security-Policy',
          'value':
              "default-src 'none'; script-src 'unsafe-inline'; "
              "style-src 'unsafe-inline'; img-src data:; form-action 'self'; base-uri 'none'",
        },
      ],
      'body': base64.encode(
        utf8.encode('''
        <!doctype html><meta charset="utf-8"><html lang="ja">
        <link rel="icon" href="data:,">
        <script>$_instrumentation</script>
        <button type="button">ログアウト</button>
        <h1>履修登録・登録状況照会</h1>$page
        </html>'''),
      ),
    });
  }
}

class _FixtureViewService extends WindowsGakujoWebViewService {
  _FixtureViewService(this.fixture);
  final _PortalFixture fixture;
  late final GakujoWebViewController controller;

  @override
  GakujoWebViewController createController() =>
      controller = super.createController();

  @override
  Future<void> configureController(
    GakujoWebViewController controller, {
    required bool debugAllowed,
    bool downloadInterceptionEnabled = true,
  }) async {
    await super.configureController(
      controller,
      debugAllowed: debugAllowed,
      downloadInterceptionEnabled: downloadInterceptionEnabled,
    );
    // The app awaits configuration before its first navigation.
    await fixture.attach();
  }
}

String _gridHtml(bool registered) =>
    '''
  <table><tr><th>年度・学期</th><td>2026年度 第1学期</td></tr></table>
  <table><caption>第1学期</caption>
  <tr><th>時限</th><th>月</th><th>火</th><th>水</th><th>木</th><th>金</th><th>土</th></tr>
  <tr><th>1限</th><td><a data-control="add" href="$_condition">追加</a>
  <div class="tblDivNml"><a href="#" onclick="CallDetail('2026','09',
    '${registered ? _code : '269G9002'}','1','1')">
    ${registered ? _code : '269G9002'} (T1)</a><br>$_title
    <input data-control="delete" type="button" value="削除" onclick="confirm('delete')">
    </div></td><td></td><td></td><td></td><td></td><td></td></tr></table>''';

const _conditionHtml =
    '''
  <h2>条件入力</h2><form method="post" action="$_results">
  <table>
    <tr><th>開講所属</th><td><select name="faculty"><option value="initial">合成学部</option>
      <option value="any">指示なし</option></select></td></tr>
    <tr><th>開講番号</th><td><input name="code"></td></tr>
    <tr><th>科目名</th><td><input name="title" value="keep"></td></tr>
    <tr><th>曜日</th><td><select name="day"><option>月</option></select></td></tr>
    <tr><th>時限</th><td><select name="period"><option>1限</option></select></td></tr>
  </table><button data-control="search">検索開始</button></form>''';

const _resultsHtml =
    '''
  <h2>検索結果</h2><table>
  <tr><th>選択</th><th>優先度</th><th>開講番号</th><th>科目名</th></tr>
  <tr><td><a data-control="choose" href="$_return">選択</a></td>
  <td><label><input data-control="priority" type="radio" name="priority" checked>なし</label>
      <label><input data-control="priority" type="radio" name="priority">高</label></td>
  <td>$_code</td><td>$_title</td></tr></table>
  <button data-control="confirm">登録</button><button data-control="confirm">確定</button>
  <button data-control="confirm">申請</button><button data-control="confirm">OK</button>''';

const _instrumentation = '''
  function record(entry) {
    const log = JSON.parse(sessionStorage.getItem('fixture') || '[]');
    log.push(entry);
    sessionStorage.setItem('fixture', JSON.stringify(log));
  }
  window.confirm = () => { record('confirm:dialog'); return false; };
  const checked = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'checked');
  Object.defineProperty(HTMLInputElement.prototype, 'checked', {
    ...checked,
    set(value) {
      if (this.type === 'radio') record('priority:assignment');
      checked.set.call(this, value);
    },
  });
  for (const type of ['click', 'input', 'change']) {
    document.addEventListener(type, (event) => {
      const control = event.target.closest('[data-control]')?.dataset.control;
      if (!control) return;
      record(control + ':' + type + ':' + event.isTrusted);
      if (type === 'click' && control === 'choose') {
        event.preventDefault();
        // Leave the result document visible until Dart has received the channel
        // message, then let the fixture complete the normal navigation.
        if (event.isTrusted) window.finishSelection = () => location.assign(event.target.href);
      }
    }, true);
  }
  document.addEventListener('submit', () => record('search:submit'), true);
  const submit = HTMLFormElement.prototype.submit;
  HTMLFormElement.prototype.submit = function () {
    record('search:direct-submit');
    return submit.call(this);
  };
''';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final root = Directory(Platform.environment['MBG_REGISTRATION_SMOKE_DIR']!);
  final result = File('${root.path}/result.txt');
  var stage = 'initializing isolated WebView2';
  Never fail(Object error, [StackTrace? stack]) {
    final trace = stack == null ? '' : '\n$stack';
    result.writeAsStringSync('Failed while $stage\n$error$trace');
    exit(1);
  }

  final watchdog = Timer(const Duration(seconds: 70), () => fail('Timed out'));
  FlutterError.onError = (details) => fail(details.exception, details.stack);
  binding.platformDispatcher.onError = fail;
  try {
    _check(root.listSync().isEmpty, 'Expected a fresh run directory');
    for (final variable in [
      'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS',
      'WEBVIEW2_BROWSER_EXECUTABLE_FOLDER',
      'WEBVIEW2_USER_DATA_FOLDER',
    ]) {
      _check(
        !Platform.environment.containsKey(variable),
        'Unexpected $variable override',
      );
    }
    // All browser traffic that escapes the document interceptor is sent to this
    // loopback-only proxy. It never forwards requests and fails on any connection.
    final denyProxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    denyProxy.listen((socket) {
      socket.destroy();
      fail('Browser attempted a request outside the fixture interceptor');
    });
    final devTools = HttpClient()..findProxy = (_) => 'DIRECT';
    HttpOverrides.global = _LocalOnly(fail);
    final fixture = _PortalFixture(root, devTools, fail);
    await WebviewController.initializeEnvironment(
      userDataPath: '${root.path}/profile',
      additionalArguments: [
        '--proxy-server=http://127.0.0.1:${denyProxy.port}',
        '--proxy-bypass-list=<-loopback>',
        '--host-resolver-rules="MAP * ~NOTFOUND"',
        '--disable-background-networking',
        '--disable-quic',
        '--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
        '--remote-debugging-address=127.0.0.1',
        '--remote-debugging-port=0',
      ].join(' '),
    );
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_setup_completed': 'true',
      'more_better_gakujo_active_login_account': 'synthetic-smoke-account',
      'more_better_gakujo_disabled_feature_flags': 'update_notice',
    });
    final prefs = GakujoLocalPrefsStore(directory: root);
    await prefs.saveUpdateCheck(checkedAt: DateTime.now());
    final service = _FixtureViewService(fixture);
    runApp(
      MaterialApp(
        home: GakujoWebApp(
          webViewService: service,
          startUrl: _grid,
          localPrefsStore: prefs,
          gakujoReachable: () async => fail('Unexpected reachability probe'),
        ),
      ),
    );
    final ui = LiveWidgetController(binding);
    Future<void> press(String label) async {
      final finder = find.widgetWithText(FilledButton, label);
      final button = await _waitFor(
        () => finder.evaluate().singleOrNull?.widget as FilledButton?,
        label,
      );
      button.onPressed!();
    }

    Future<Object?> eval(String js) =>
        service.controller.runJavaScriptReturningResult(js);

    stage = 'opening the production menu and confirming the preview';
    await ui.pump();
    await _waitFor(
      () => fixture.requests.length == 1 ? true : null,
      'Initial grid',
    );
    final menu = find.byWidgetPredicate(
      (widget) => widget is PopupMenuButton<Object> && widget.tooltip == 'メニュー',
    );
    final assist = find.ancestor(
      of: find.text(_import),
      matching: find.byType(PopupMenuItem<Object>),
    );
    // Availability is asynchronous. Reopen the menu to read its current snapshot.
    final item = await _waitFor(() async {
      ui.state<PopupMenuButtonState<Object>>(menu).showButtonMenu();
      await ui.pump(const Duration(milliseconds: 300));
      final element = assist.evaluate().single;
      if ((element.widget as PopupMenuItem<Object>).enabled) return element;
      Navigator.of(element).pop();
      await ui.pump(const Duration(milliseconds: 300));
      return null;
    }, 'Enabled registration menu');
    _check(
      find.text(_copy).evaluate().length == 1,
      'Inquiry copy menu missing',
    );
    Navigator.of(item).pop((item.widget as PopupMenuItem<Object>).value);
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(EditableText),
    );
    await _waitFor(
      () => field.evaluate().length == 1 ? true : null,
      'Handoff input',
    );
    const plan = RegistrationHandoff(2026, [
      RegistrationCourse(
        code: _code,
        title: _title,
        semester: 1,
        quarters: [1],
        slots: ['月1'],
        credits: 1,
      ),
    ]);
    ui.widget<EditableText>(field).controller.text =
        'MBGREG1.${base64Url.encode(utf8.encode(jsonEncode(plan.toJson()))).replaceAll('=', '')}';
    await press('内容を確認');
    await _waitFor(
      () => find.text('入力する 1件').evaluate().isNotEmpty ? true : null,
      'One guided course in the preview',
    );
    _check(fixture.requests.length == 1, 'Preview navigated before starting');
    await press('入力を開始');

    stage = 'checking add, search and highlight before user input';
    final point = await _waitFor(() async {
      final value = await eval('''(() => {
        const link = document.querySelector('[data-control="choose"]');
        if (!link?.style.outline || !link.closest('tr').style.outline) return null;
        const box = link.getBoundingClientRect();
        const x = box.x + box.width / 2, y = box.y + box.height / 2;
        return document.elementFromPoint(x, y) === link ? JSON.stringify([x, y]) : null;
      })()''');
      return value is String ? jsonDecode(value) as List : null;
    }, 'Highlighted result');
    _check(fixture.requests.length == 3, 'Expected grid, add, and search only');
    _check(
      await eval(
            "JSON.parse(sessionStorage.fixture).every(x => x.startsWith('add:') || x.startsWith('search:'))",
          ) ==
          true,
      'The assist touched a protected control before the click',
    );
    await _waitFor(
      () => find.text(_skip).evaluate().isNotEmpty ? true : null,
      'Skip before selection',
    );

    stage = 'sending trusted input and waiting for MbgRegistrationChoice';
    for (final type in ['mousePressed', 'mouseReleased']) {
      await fixture.send('Input.dispatchMouseEvent', {
        'type': type,
        'x': point[0],
        'y': point[1],
        'button': 'left',
        'clickCount': 1,
      });
    }
    await _waitFor(
      () => find.text(_skip).evaluate().isEmpty ? true : null,
      'Channel receipt should hide Skip while still on results',
    );
    _check(
      fixture.requests.length == 3,
      'Grid returned before channel receipt',
    );
    _check(
      await eval("typeof window.finishSelection === 'function'") == true,
      'Trusted DOM click was not observed',
    );
    await service.controller.runJavaScript('window.finishSelection()');

    stage = 'checking the returned grid and completed session';
    await _waitFor(
      () =>
          find.text('$_code $_title — 完了').evaluate().isNotEmpty ? true : null,
      'Dart session must show 完了',
    );
    _check(fixture.requests.length == 4, 'Expected one return to the grid');
    _check(
      await eval(
            "document.querySelector('.tblDivNml a').innerText.includes('$_code')",
          ) ==
          true,
      'The returned grid is missing the course',
    );
    final log =
        jsonDecode((await eval('sessionStorage.fixture')) as String) as List;
    _check(
      jsonEncode(log) == '["add:click:false","search:click:false","search:submit","choose:click:true"]',
      'Unexpected fixture interactions: $log',
    );
    watchdog.cancel();
    result.writeAsStringSync(
      'Verified Windows WebView2 registration preview, add, search, highlight, '
      'one trusted selection, channel receipt and 完了. '
      'Delete, priority and confirm untouched. Four intercepted requests, no proxy traffic.',
    );
    exit(0);
  } on Object catch (error, stack) {
    fail(error, stack);
  }
}
