import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/course_name_body_text.g.dart';
import 'package:morebettergakujo_flutter/src/generated/course_name_estimate.g.dart';
import 'package:morebettergakujo_flutter/src/generated/course_name_tables.g.dart';
import 'package:morebettergakujo_flutter/src/generated/document_title.g.dart';
import 'package:morebettergakujo_flutter/src/generated/download_capture.g.dart';
import 'package:morebettergakujo_flutter/src/generated/history_marker.g.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

const _origin = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
const _a = '${_origin}campussquare.do?_flowId=fictionalCourse-flow';
const _url = '${_origin}campussquare.do?_eventId=download';
const _file = '001.pdf';
const _generic = '学務情報システム';
const _previous = '地球科学';
const _current = '応用統計学';
const _titleOnly = '天文学';
const _unknown = '未分類';
final _body = utf8.encode('%PDF-1.4\nSample handout\n%%EOF');
final _marker = gakujoHistoryMarkerJs({'action': 'read'});

class _Prefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;
  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

typedef _Json = Map<String, dynamic>;
final _scripts = {
  gakujoDocumentTitleJs: 'title',
  gakujoCourseNameEstimateJs: 'primary',
  gakujoCourseNameTablesJs: 'tables',
  gakujoCourseNameBodyTextJs: 'body',
};

// Evaluate the generated scripts before and after installing the capture
// listener. Use the message that the listener actually posts for an anchor.
Future<_Json> _rendererPages() async {
  final process = await Process.start('node', [
    '-e',
    r'''
const vm = require('node:vm');
const { pages, scripts, capture, url } = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
const results = {};
for (const [name, page] of Object.entries(pages)) {
  const location = new URL(page.url);
  const document = { location, title: page.title, body: { innerText: page.body },
    querySelector: () => null, getElementById: () => null };
  const element = (tagName, text) => ({ tagName, innerText: text, textContent: text,
    ownerDocument: document, getAttribute: () => null, hasAttribute: () => false,
    closest: () => null, getClientRects: () => [{width: 80, height: 20}] });
  const anchor = element('A', '001.pdf');
  anchor.closest = selector => selector === 'a[href]' ? anchor : null;
  anchor.getAttribute = key => key === 'href' ? url : null;
  const headings = (page.headings || []).map(name => element('H2', name));
  const cells = [element('TH', '科目名'), element('TD', page.table)];
  const rows = [{ cells, querySelectorAll: selector => selector === 'th,td' ? cells : [] }];
  const tables = page.table ? [{ rows, querySelectorAll: selector => selector === 'tr' ? rows : [] }] : [];
  document.querySelectorAll = selector =>
    selector === 'h2' ? headings : selector === 'table' ? tables : [];
  let click, message, prevented = false;
  document.addEventListener = (type, listener) => { if (type === 'click') click = listener; };
  const window = { location, document, frames: [],
    getComputedStyle: () => ({display: 'block', visibility: 'visible', opacity: '1'}),
    MoreBetterGakujoDownloads: { postMessage: data => { message = JSON.parse(data); } } };
  window.parent = window.top = window;
  document.defaultView = window;
  const ctx = vm.createContext({ window, document, location, URL });
  const read = () => Object.fromEntries(Object.entries(scripts)
    .map(([name, script]) => [name, vm.runInContext(script, ctx)]));
  const cold = read();
  vm.runInContext(capture, ctx);
  const hot = read();
  click({target: anchor, preventDefault() { prevented = true; }, stopPropagation() {}});
  if (!prevented || message.url !== url || message.fileName !== '001.pdf') throw Error(name);
  results[name] = { cold, hot, message };
}
process.stdout.write(JSON.stringify(results));
''',
  ]);
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  Map<String, Object> page(
    String title, {
    String? table,
    List<String>? headings,
    String body = '$_generic\n$_file',
    String url = gakujoHomePortalUrl,
  }) => {
    'url': url,
    'title': title,
    'body': body,
    'headings': ?headings,
    'table': ?table,
  };
  process.stdin.add(
    utf8.encode(
      jsonEncode({
        'scripts': {
          for (final entry in _scripts.entries) entry.value: entry.key,
        },
        'capture': gakujoDownloadCaptureJs,
        'url': _url,
        'pages': {
          'a': page(_previous, headings: [_previous], url: _a),
          'generic': page(_generic),
          'title': page(_titleOnly),
          'heading': page(_titleOnly, headings: [_current]),
          'table': page(_titleOnly, table: _current),
          'body': page(_titleOnly, body: '科目名：$_current\n$_file'),
          'ambiguous': page(_titleOnly, headings: [_previous, _current]),
        },
      }),
    ),
  );
  await process.stdin.close();
  expect(await process.exitCode, 0, reason: await stderr);
  return jsonDecode(await stdout) as _Json;
}

enum _TitleReply { renderer, quoted, missing, wrongType, malformed, error }

class _Portal {
  _Portal(this.tester, this.pages, this.id);
  final int id;
  final WidgetTester tester;
  final _Json pages;
  final root = Directory.systemTemp.createTempSync('course-title-');
  final loads = <String>[];
  final transfers = <_Json>[];
  final reads = <String>[];
  final store = GakujoDownloadHistoryStore();
  final release = Completer<void>();
  final held = Completer<Object?>();
  String page = 'a';
  String? holdScript;
  var titleReply = _TitleReply.renderer;
  var installed = false;
  var completions = 0;
  var markers = 0;
  var disposed = false;
  var intercepted = false;
  var chunkSent = false;
  late MockStreamHandlerEventSink sink;
  static const plugin = MethodChannel('io.jns.webview.win');
  late final view = MethodChannel('io.jns.webview.win/$id');
  late final events = EventChannel('io.jns.webview.win/$id/events');
  static const channels = [
    MethodChannel('net.yoshida.morebettergakujo/notifications'),
    MethodChannel('net.yoshida.morebettergakujo/downloads'),
    SystemChannels.platform,
  ];

  Future<void> mount() async {
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_setup_completed': 'true',
      'more_better_gakujo_disabled_feature_flags': 'update_notice',
      'more_better_gakujo_download_root_path': root.path,
      'more_better_gakujo_download_save_mode': 'autoSortToConfiguredFolder',
    });
    PackageInfo.setMockInitialValues(
      appName: 'Example',
      packageName: 'example.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
    messenger.setMockMethodCallHandler(plugin, (call) async {
      if (call.method == 'initialize') return {'textureId': id};
      if (call.method == 'dispose' && call.arguments == id) disposed = true;
      return null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, value) {
          sink = value;
        },
      ),
    );
    messenger.setMockMethodCallHandler(view, (call) async {
      if (call.method == 'setDownloadInterceptionEnabled') {
        intercepted = call.arguments as bool;
      }
      if (call.method == 'loadUrl') loads.add(call.arguments as String);
      if (call.method == 'addScriptToExecuteOnDocumentCreated') return 'id';
      if (call.method == 'executeScript') {
        return evaluate(call.arguments as String);
      }
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    await tester.pumpWidget(
      MaterialApp(
        home: GakujoWebApp(
          localPrefsStore: _Prefs(),
          gakujoReachable: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, hasLength(1));
    expect(await store.load(), isEmpty);
    expect(intercepted, isTrue);
  }

  Future<String?> evaluate(String script) async {
    Object? result = '';
    if (script == gakujoDownloadCaptureJs) installed = true;
    if (script == gakujoPortalAuthStateProbeScript) {
      result = jsonEncode({'hasAuthenticatedMarker': true});
    }
    if (script == _marker) markers++;
    final key = _scripts[script];
    if (key != null) {
      reads.add('$page/$key');
      result = pages[page][installed ? 'hot' : 'cold'][key];
      if (script == gakujoDocumentTitleJs) {
        switch (titleReply) {
          case _TitleReply.quoted:
            result = jsonEncode(result);
          case _TitleReply.missing:
            return null;
          case _TitleReply.wrongType:
            result = {'title': result};
          case _TitleReply.malformed:
            return '{';
          case _TitleReply.error:
            throw PlatformException(code: 'renderer-unavailable');
          case _TitleReply.renderer:
            break;
        }
      }
    }
    if (script == holdScript && !held.isCompleted) {
      // Capture the value at evaluation, before the reply can be delayed.
      held.complete(result);
      await release.future;
    }
    if (script.contains('function authenticatedDownloadStart(')) {
      final args = script.substring(script.lastIndexOf('})(') + 3).trim();
      transfers.add(jsonDecode(args.substring(0, args.length - 1)) as _Json);
      chunkSent = false;
      return jsonEncode(true);
    }
    if (script.contains('function authenticatedDownloadPoll(')) {
      result = jsonEncode(
        chunkSent
            ? {
                'state': 'done',
                'payload': {
                  'ok': true,
                  'status': 200,
                  'finalUrl': _url,
                  'mimeType': 'application/pdf',
                  'chunkCount': 1,
                  'bodyByteLength': _body.length,
                },
              }
            : {'state': 'chunk', 'index': 0, 'bodyBase64': base64Encode(_body)},
      );
      chunkSent = true;
    }
    return jsonEncode(result);
  }

  Future<void> wait(String label, FutureOr<bool> Function() condition) async {
    for (var i = 0; i < 300; i++) {
      if (await condition()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 15));
    }
    fail('Missing $label on $page (loads=$loads, reads=$reads)');
  }

  Future<void> event(String type, Object value) async {
    sink.success({'type': type, 'value': value});
    await tester.idle();
  }

  Future<void> begin(String next) async {
    final url = next == 'a' ? _a : gakujoHomePortalUrl;
    await event('navigationStarting', url);
    await event('urlChanged', url);
    page = next;
    installed = false;
    await event('loadingStateChanged', windows.LoadingState.loading.index);
  }

  Future<void> complete() async {
    completions++;
    await event(
      'loadingStateChanged',
      windows.LoadingState.navigationCompleted.index,
    );
  }

  Future<void> finish() async {
    final previous = markers;
    await complete();
    await wait(
      'history marker after course estimation',
      () => markers > previous && reads.contains('$page/primary'),
    );
  }

  Future<void> openHome([String next = 'generic']) async {
    final before = loads.length;
    await tester.tap(find.byTooltip('学務のHOMEへ').hitTestable());
    await tester.pump();
    await wait('toolbar HOME load', () => loads.length > before);
    expect(loads.skip(before), [gakujoHomePortalUrl]);
    await begin(next);
  }

  Future<void> native() => event('downloadEvent', {
    'kind': windows.WebviewDownloadEventKind.downloadStarted.index,
    'url': _url,
    'resultFilePath': _file,
    'contentDisposition': 'attachment; filename="001.pdf"',
    'mimeType': 'application/pdf',
    'bytesReceived': 0,
    'totalBytesToReceive': _body.length,
  });

  Future<void> click({bool ambiguous = false}) async {
    expect(installed, isTrue);
    final message = pages[page]['message'] as _Json;
    expect(message['courseName'], _unknown);
    expect(message['courseNameAmbiguous'], ambiguous ? true : null);
    await event(
      'webMessageReceived',
      jsonEncode({
        'channel': 'MoreBetterGakujoDownloads',
        'message': jsonEncode(message),
      }),
    );
  }

  Future<void> expectFile(String expected) async {
    await wait(
      'persisted download',
      () async => (await store.load()).isNotEmpty,
    );
    final fresh = GakujoDownloadHistoryStore();
    final entry = (await fresh.load()).single;
    final output = File(entry.location!);
    expect(entry.fileName, _file);
    expect(output.uri.pathSegments.last, _file);
    expect(output.parent.parent.absolute.path, root.absolute.path);
    expect(await tester.runAsync(output.readAsBytes), _body);
    expect(transfers, hasLength(1));
    expect(transfers.single['url'], _url);
    expect(transfers.single['method'], 'GET');
    expect(await fresh.loadFailedDownloads(), isEmpty);
    expect(
      [
        output.parent.uri.pathSegments.where((s) => s.isNotEmpty).last,
        entry.courseName,
      ],
      [expected, expected],
      reason: 'Folder and fresh history for $page',
    );
  }

  Future<void> dispose() async {
    if (!release.isCompleted) release.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    await wait('WebView disposal', () => disposed);
    await tester.binding.setSurfaceSize(null);
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in [plugin, view, ...channels]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockStreamHandler(events, null);
    root.deleteSync(recursive: true);
  }
}

void main() {
  late _Json pages;
  setUpAll(() async {
    pages = await _rendererPages();
  });

  final journeys =
      <({String name, bool finishA, Future<void> Function(_Portal) run})>[];
  void journey(
    String name,
    Future<void> Function(_Portal) run, {
    bool finishA = true,
  }) {
    journeys.add((name: name, finishA: finishA, run: run));
  }

  for (final click in [false, true]) {
    final source = click ? 'generated click' : 'native download';
    journey('late native title after HOME finishes ($source)', (p) async {
      await p.openHome();
      await p.finish();
      await p.event('titleChanged', _generic);
      if (click) {
        await p.click();
      } else {
        await p.native();
      }
      await p.expectFile(_unknown);
    });

    journey('$source while HOME finish is suspended', (p) async {
      await p.openHome();
      p.holdScript = click
          ? gakujoDownloadCaptureJs
          : gakujoPortalAuthStateProbeScript;
      await p.complete();
      await p.wait('held finish reply', () => p.held.isCompleted);
      expect(p.installed, click);
      if (click) {
        await p.click();
      } else {
        await p.native();
      }
      await p.expectFile(_unknown);
      expect(p.reads.where((v) => v == 'generic/primary'), hasLength(1));
      final before = p.markers;
      p.release.complete();
      await p.wait('finish resumed after download', () => p.markers > before);
    });
  }

  journey('fresh history and bytes precede the first HOME completion', (
    p,
  ) async {
    await p.openHome();
    await p.native();
    await p.expectFile(_unknown);
    expect(p.completions, 1);
    expect(p.installed, isFalse);
    await p.event('titleChanged', _generic);
    await p.finish();
    expect(p.completions, 2);
    await p.expectFile(_unknown);
  });

  journey('a same-document retitle supplies the only useful course evidence', (
    p,
  ) async {
    await p.openHome();
    await p.event('titleChanged', _generic);
    p.page = 'title'; // HOME retains its URL and content-loading generation.
    p.titleReply = _TitleReply.quoted;
    await p.native();
    await p.expectFile(_titleOnly);
  });

  for (final (page, reply, expected, evidence) in [
    ('heading', _TitleReply.renderer, _current, 'primary'),
    ('table', _TitleReply.renderer, _current, 'tables'),
    ('body', _TitleReply.renderer, _current, 'body'),
    ('table', _TitleReply.missing, _current, 'tables'),
    ('body', _TitleReply.wrongType, _current, 'body'),
    ('heading', _TitleReply.error, _current, 'primary'),
    ('table', _TitleReply.malformed, _current, 'tables'),
    ('generic', _TitleReply.wrongType, _unknown, 'body'),
  ]) {
    journey('$page course evidence with a ${reply.name} title', (p) async {
      await p.openHome(page);
      p.titleReply = reply;
      if (page == 'heading') await p.finish();
      p.reads.clear();
      await p.native();
      await p.expectFile(expected);
      expect(p.reads, contains('$page/title'));
      expect(p.reads, contains('$page/$evidence'));
    });
  }

  journey('confirmed click ambiguity takes precedence over a useful title', (
    p,
  ) async {
    await p.openHome('ambiguous');
    await p.finish();
    await p.click(ambiguous: true);
    await p.expectFile(_unknown);
  });

  journey('late title evaluated on A cannot populate the HOME course cache', (
    p,
  ) async {
    p.holdScript = gakujoDocumentTitleJs;
    await p.complete();
    await p.wait('A title evaluated', () => p.held.isCompleted);
    expect(await p.held.future, _previous);
    await p.openHome();
    await p.finish();
    final before = p.reads.length;
    p.release.complete();
    await p.wait(
      'A estimate resumed against HOME',
      () => p.reads.skip(before).contains('generic/body'),
    );
    await p.native();
    await p.expectFile(_unknown);
  }, finishA: false);

  journey('a pending title cannot classify a download across a HOME reload', (
    p,
  ) async {
    await p.openHome('title');
    p.holdScript = gakujoDocumentTitleJs;
    await p.native();
    await p.wait('old HOME title evaluated', () => p.held.isCompleted);
    expect(await p.held.future, _titleOnly);
    await p.begin('generic');
    p.release.complete();
    await p.expectFile(_unknown);
  });

  testWidgets(
    'saved attachment course follows renderer title evidence',
    (tester) async {
      for (final (index, scenario) in journeys.indexed) {
        final portal = _Portal(tester, pages, 73 + index);
        await portal.mount();
        try {
          await portal.begin('a');
          await portal.event('titleChanged', scenario.finishA ? _previous : '');
          if (scenario.finishA) await portal.finish();
          await scenario.run(portal);
        } catch (_) {
          printOnFailure(scenario.name);
          rethrow;
        } finally {
          await portal.dispose();
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
