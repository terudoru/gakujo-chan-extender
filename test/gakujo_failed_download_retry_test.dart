import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/course_name_estimate.g.dart';
import 'package:morebettergakujo_flutter/src/generated/history_marker.g.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

const _origin = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
const _url = '${_origin}campussquare.do?_eventId=download';
const _fileName = 'handout.pdf';
const _formPairs = [
  ['unit', '1'],
  ['section', 'blue'],
  ['unit', '2'],
];
const _capture = {
  'url': _url,
  'method': 'POST',
  'fileName': _fileName,
  'courseName': '未分類',
  'formFields': {'unit': '2', 'section': 'blue'},
  'formFieldPairs': _formPairs,
};

class _TestPrefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

Future<void> _waitFor(
  WidgetTester tester,
  String description,
  FutureOr<bool> Function() condition,
) async {
  for (var i = 0; i < 150; i++) {
    if (await condition()) return;
    // The real filesystem and page-finished asset reads run outside fake time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 15));
  }
  fail('Timed out waiting for $description');
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'retry preserves the selected course while new captures use the open page',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const plugin = MethodChannel('io.jns.webview.win');
      const view = MethodChannel('io.jns.webview.win/73');
      const events = EventChannel('io.jns.webview.win/73/events');
      const notifications = MethodChannel(
        'net.yoshida.morebettergakujo/notifications',
      );
      const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
      final root = Directory.systemTemp.createTempSync(
        'failed-download-retry-',
      );
      final store = GakujoDownloadHistoryStore();
      final body = utf8.encode('%PDF-1.4\nSample handout\n%%EOF');
      final transfers = <Map<String, dynamic>>[];
      final readHistory = gakujoHistoryMarkerJs({'action': 'read'});
      late MockStreamHandlerEventSink webView;
      var historyReads = 0;
      var pageCourse = '';
      var status = 503;
      var chunkSent = false;

      FlutterSecureStorage.setMockInitialValues({
        'more_better_gakujo_setup_completed': 'true',
        'more_better_gakujo_disabled_feature_flags': 'update_notice',
        'more_better_gakujo_download_root_path': root.path,
        'more_better_gakujo_download_save_mode': 'autoSortToConfiguredFolder',
      });
      messenger.setMockMethodCallHandler(
        plugin,
        (call) async => call.method == 'initialize' ? {'textureId': 73} : null,
      );
      messenger.setMockMethodCallHandler(notifications, (_) async => null);
      messenger.setMockMethodCallHandler(downloads, (_) async => null);
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            webView = sink;
          },
        ),
      );
      messenger.setMockMethodCallHandler(view, (call) async {
        if (call.method == 'addScriptToExecuteOnDocumentCreated') return 'id';
        if (call.method != 'executeScript') return null;
        final script = call.arguments as String;
        if (script == readHistory) historyReads++;
        if (script == gakujoPortalAuthStateProbeScript) {
          return jsonEncode({'hasAuthenticatedMarker': true});
        }
        if (script == gakujoCourseNameEstimateJs) {
          return jsonEncode(
            jsonEncode({
              'courseName': pageCourse,
              'courseNameAmbiguous': false,
            }),
          );
        }
        if (script.contains('function authenticatedDownloadStart(')) {
          // The generated script ends with the JSON argument to the function.
          final argument = script
              .substring(script.lastIndexOf('})(') + 3)
              .trim();
          transfers.add(
            jsonDecode(argument.substring(0, argument.length - 1))
                as Map<String, dynamic>,
          );
          chunkSent = false;
          return jsonEncode(true);
        }
        if (script.contains('function authenticatedDownloadPoll(')) {
          if (status == 200 && !chunkSent) {
            chunkSent = true;
            return jsonEncode(
              jsonEncode({
                'state': 'chunk',
                'index': 0,
                'bodyBase64': base64Encode(body),
              }),
            );
          }
          return jsonEncode(
            jsonEncode({
              'state': 'done',
              'payload': {
                'ok': status == 200,
                'status': status,
                'finalUrl': _url,
                'mimeType': 'application/pdf',
                if (chunkSent) 'chunkCount': 1,
                if (chunkSent) 'bodyByteLength': body.length,
              },
            }),
          );
        }
        return jsonEncode('');
      });
      addTearDown(() async {
        for (final channel in [plugin, view, notifications, downloads]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        messenger.setMockStreamHandler(events, null);
        FlutterSecureStorage.setMockInitialValues({});
        await tester.binding.setSurfaceSize(null);
        root.deleteSync(recursive: true);
      });

      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(
            home: GakujoWebApp(
              localPrefsStore: _TestPrefs(),
              gakujoReachable: () async => false,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      void event(String type, Object value) =>
          webView.success({'type': type, 'value': value});

      Future<void> visit(String tab, String course) async {
        final url = '${_origin}campusportal.do?page=main&tabId=$tab';
        pageCourse = course;
        final before = historyReads;
        event('navigationStarting', url);
        await tester.idle();
        event('urlChanged', url);
        await tester.idle();
        event('loadingStateChanged', windows.LoadingState.loading.index);
        await tester.idle();
        event(
          'loadingStateChanged',
          windows.LoadingState.navigationCompleted.index,
        );
        await _waitFor(tester, 'page $tab', () => historyReads > before);
      }

      Future<void> failure(int code) => _waitFor(
        tester,
        'queued HTTP $code',
        () async => (await store.loadFailedDownloads()).any(
          (entry) => entry.errorMessage.contains('HTTP $code'),
        ),
      );

      // The capture debounce uses wall time even in a widget test.
      Future<void> nextAttempt() async {
        await tester.runAsync(
          () => Future<void>.delayed(
            GakujoDownloadOperationGate().duplicateCaptureWindow,
          ),
        );
      }

      Future<void> capture(int response) async {
        status = response;
        event(
          'webMessageReceived',
          jsonEncode({
            'channel': 'MoreBetterGakujoDownloads',
            'message': jsonEncode(_capture),
          }),
        );
        await failure(response);
      }

      Future<void> openSavedData() async {
        await _tap(tester, find.byTooltip('設定'));
        await _tap(tester, find.text('保存データ'));
      }

      Future<void> openFailedList() async {
        await _tap(tester, find.widgetWithText(OutlinedButton, 'ダウンロード記録'));
        await _tap(tester, find.widgetWithText(ListTile, '失敗したダウンロード'));
      }

      Future<void> retry(int previous, int response) async {
        await openFailedList();
        final row = find.ancestor(
          of: find.textContaining('HTTP $previous'),
          matching: find.byType(ListTile),
        );
        status = response;
        await nextAttempt();
        await _tap(
          tester,
          find.descendant(of: row, matching: find.byTooltip('再試行')),
        );
      }

      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      try {
        await mount();
        await visit('home', '');
        await capture(503);
        expect(
          (await store.loadFailedDownloads()).single.request.toJson(),
          _capture,
        );

        // Same URL and ordered POST body, genuinely captured on a different course.
        const course = '応用統計学';
        await visit('sch', course);
        await nextAttempt();
        await capture(504);
        final distinct = await store.loadFailedDownloads();
        expect(
          distinct.map((e) => e.request.courseName),
          unorderedEquals(['未分類', course]),
        );
        final other = distinct.singleWhere(
          (e) => e.request.courseName == course,
        );

        await openSavedData();
        await retry(503, 502);
        await failure(502);
        final failed = await store.loadFailedDownloads();
        final retried = failed.singleWhere(
          (e) => e.errorMessage.contains('HTTP 502'),
        );
        expect(retried.request.toJson(), _capture);
        expect(
          failed.map((e) => e.id),
          unorderedEquals([retried.id, other.id]),
        );

        await retry(502, 200);
        await _waitFor(
          tester,
          'saved history and selected row removal',
          () async =>
              (await store.load()).isNotEmpty &&
              !(await store.loadFailedDownloads()).any(
                (e) => e.id == retried.id,
              ),
        );
        final saved = (await store.load()).single;
        final file = File(saved.location!);
        expect(saved.courseName, '未分類');
        expect(file.uri, root.uri.resolve('未分類/$_fileName'));
        expect(file.readAsBytesSync(), body);
        expect(transfers, hasLength(4));
        for (final transfer in transfers) {
          expect(transfer['url'], _url);
          expect(transfer['method'], 'POST');
          expect(jsonDecode(transfer['fields'] as String), _formPairs);
        }
        expect((await store.loadFailedDownloads()).single.id, other.id);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await mount();
        await openSavedData();
        await openFailedList();
        expect(find.text(_fileName), findsOneWidget);
        expect(find.textContaining('HTTP 504'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
