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
import 'package:morebettergakujo_flutter/src/generated/history_marker.g.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

class _Prefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'download folders and history follow the main-frame document',
    (tester) async {
      const origin = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
      const coursePage = '${origin}campussquare.do?_flowId=example-flow';
      const course = '地球科学';
      const otherCourse = '応用統計学';
      const unknown = '未分類';
      final store = GakujoDownloadHistoryStore();
      final root = Directory.systemTemp.createTempSync('download-course-');
      final body = utf8.encode('%PDF-1.4\nSample handout\n%%EOF');
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
      const plugin = MethodChannel('io.jns.webview.win');
      const view = MethodChannel('io.jns.webview.win/73');
      const events = EventChannel('io.jns.webview.win/73/events');
      const notifications = MethodChannel(
        'net.yoshida.morebettergakujo/notifications',
      );
      const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
      late MockStreamHandlerEventSink sink;
      var disposed = false;
      messenger.setMockMethodCallHandler(plugin, (call) async {
        if (call.method == 'initialize') return {'textureId': 73};
        if (call.method == 'dispose' && call.arguments == 73) disposed = true;
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
      for (final channel in [notifications, downloads]) {
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }

      final loads = <String>[];
      var reloads = 0;
      final transfers = <Map<String, dynamic>>[];
      final markerScript = gakujoHistoryMarkerJs({'action': 'read'});
      var pageCourse = unknown;
      var markerReads = 0;
      var estimates = 0;
      Completer<String>? nextEstimate;
      Completer<void>? nextTable;
      var bodyText = '';
      var chunkSent = false;
      messenger.setMockMethodCallHandler(view, (call) async {
        if (call.method == 'loadUrl') loads.add(call.arguments as String);
        if (call.method == 'reload') reloads++;
        if (call.method == 'addScriptToExecuteOnDocumentCreated') {
          return 'script';
        }
        if (call.method != 'executeScript') return null;
        final script = call.arguments as String;
        if (script == gakujoPortalAuthStateProbeScript) {
          return jsonEncode(jsonEncode({'hasAuthenticatedMarker': true}));
        }
        if (script == markerScript) markerReads++;
        if (script == gakujoCourseNameTablesJs) {
          final pending = nextTable;
          nextTable = null;
          if (pending != null) await pending.future;
          return jsonEncode(jsonEncode({'courseNameCandidates': []}));
        }
        if (script == gakujoCourseNameBodyTextJs) return jsonEncode(bodyText);
        if (script == gakujoCourseNameEstimateJs) {
          estimates++;
          final pending = nextEstimate;
          nextEstimate = null;
          return jsonEncode(
            jsonEncode({
              'courseName': pending == null ? pageCourse : await pending.future,
              'courseNameAmbiguous': false,
            }),
          );
        }
        if (script.contains('function authenticatedDownloadStart(')) {
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
          final chunk = !chunkSent;
          chunkSent = true;
          return jsonEncode(
            jsonEncode(
              chunk
                  ? {
                      'state': 'chunk',
                      'index': 0,
                      'bodyBase64': base64Encode(body),
                    }
                  : {
                      'state': 'done',
                      'payload': {
                        'ok': true,
                        'status': 200,
                        'finalUrl': transfers.last['url'],
                        'mimeType': 'application/pdf',
                        'chunkCount': 1,
                        'bodyByteLength': body.length,
                      },
                    },
            ),
          );
        }
        return jsonEncode('');
      });

      Future<void> waitFor(
        String description,
        FutureOr<bool> Function() ready,
      ) async {
        for (var i = 0; i < 150; i++) {
          if (await ready()) return;
          // File I/O runs on the real clock while the poll timer uses widget time.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 15));
        }
        fail('Timed out waiting for $description');
      }

      Future<void> emit(String type, Object value) async {
        sink.success({'type': type, 'value': value});
        await tester.idle();
      }

      Future<void> startPage(String url) async {
        await emit('navigationStarting', url);
        await emit('urlChanged', url);
        await emit('loadingStateChanged', windows.LoadingState.loading.index);
      }

      Future<void> completePage() => emit(
        'loadingStateChanged',
        windows.LoadingState.navigationCompleted.index,
      );

      Future<void> finishPage(String evidence) async {
        final before = markerReads;
        final previousEstimates = estimates;
        pageCourse = evidence;
        await completePage();
        await waitFor(
          'page estimate and history marker',
          () => estimates > previousEstimates && markerReads > before,
        );
      }

      Future<void> tapHome() async {
        final before = loads.length;
        await tester.tap(find.byTooltip('学務のHOMEへ').hitTestable());
        await tester.pump();
        await waitFor('issued HOME load', () => loads.length > before);
        expect(loads.skip(before), [gakujoHomePortalUrl]);
      }

      final savedCourses = <String, (Uri, String)>{};
      final expectedCourses = <String, (Uri, String)>{};
      Future<void> download(
        String fileName,
        String expectedCourse, {
        Future<void> Function(String url)? start,
      }) async {
        final before = transfers.length;
        final url = start == null
            ? '${origin}campussquare.do?_eventId=download&file=$fileName'
            : '$origin$fileName';
        if (start != null) {
          await start(url);
        } else {
          await emit('downloadEvent', {
            'kind': windows.WebviewDownloadEventKind.downloadStarted.index,
            'url': url,
            'resultFilePath': fileName,
            'mimeType': 'application/pdf',
            'bytesReceived': 0,
            'totalBytesToReceive': body.length,
            'contentDisposition': 'attachment; filename="$fileName"',
          });
        }
        await waitFor(
          fileName,
          () async => (await store.load()).any((e) => e.fileName == fileName),
        );
        final entry = (await store.load()).singleWhere(
          (e) => e.fileName == fileName,
        );
        final file = File(entry.location!);
        expect(transfers.length, before + 1);
        expect(transfers.last['url'], url);
        expect(transfers.last['method'], 'GET');
        expect(file.readAsBytesSync(), body);
        savedCourses[fileName] = (file.uri, entry.courseName);
        expectedCourses[fileName] = (
          root.uri.resolve('$expectedCourse/$fileName'),
          expectedCourse,
        );
      }

      Future<void> click(String url, String hint, {bool ambiguous = false}) =>
          emit('webMessageReceived', jsonEncode({
            'channel': 'MoreBetterGakujoDownloads',
            'message': jsonEncode({
              'url': url,
              'method': 'GET',
              'fileName': Uri.parse(url).pathSegments.last,
              'courseName': hint,
              'courseNameAmbiguous': ambiguous,
              'formFields': {},
            }),
          }));

      Future<void> estimateDuringDownload(
        String fileName,
        String initialCourse,
        String expectedCourse, {
        bool policyGet = false,
        bool replaceDocument = true,
      }) async {
        await startPage(coursePage);
        await finishPage(initialCourse);
        pageCourse = unknown;
        await download(fileName, expectedCourse, start: (url) async {
          final heading = Completer<String>();
          final table = Completer<void>();
          nextEstimate = heading;
          nextTable = table;
          try {
            if (policyGet) {
              await emit('navigationStarting', url);
              await emit('urlChanged', url);
            } else {
              await click(url, unknown);
            }
            await waitFor('first course read', () => nextEstimate == null);
            if (replaceDocument && !policyGet) {
              // A page refresh at the same URL can omit SourceChanged.
              await emit('navigationStarting', coursePage);
            }
            heading.complete(unknown);
            await waitFor('next course table read', () => nextTable == null);
            if (replaceDocument) {
              await emit(
                'loadingStateChanged',
                windows.LoadingState.loading.index,
              );
            }
            bodyText = '科目名：$otherCourse';
          } finally {
            if (!heading.isCompleted) heading.complete(unknown);
            table.complete();
          }
        });
        bodyText = '';
      }

      final held = Completer<String>();
      final heldReload = Completer<String>();
      try {
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
        await startPage(coursePage);
        await finishPage(course);
        // Following a fragment changes Source but keeps the displayed document.
        pageCourse = unknown;
        await emit('urlChanged', '$coursePage#materials');
        await download('006.pdf', course);
        await finishPage(unknown);
        await download('007.pdf', course);
        await tapHome();
        // HOME was requested, but the still-displayed A can finish again first.
        await emit('navigationStarting', gakujoHomePortalUrl);
        await finishPage(unknown);
        await download('001.pdf', course);

        // A page-finished estimate from A returns after HOME has finished.
        nextEstimate = held;
        await completePage();
        await waitFor('suspended estimate on A', () => nextEstimate == null);
        await startPage(gakujoHomePortalUrl);
        await finishPage(unknown);
        held.complete(course);
        await tester.idle();
        await download('002.pdf', unknown);

        // A new document can use the same URL. Its downloads may precede finish.
        await startPage(gakujoHomePortalUrl);
        await finishPage(course);
        pageCourse = unknown;
        await startPage(gakujoHomePortalUrl);
        await download('003.pdf', unknown);
        await finishPage(course);

        // Repeating the completion alone leaves this document's fallback intact.
        await finishPage(unknown);
        await download('004.pdf', course);

        await tester.tap(find.byTooltip('メニュー').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('再読み込み').hitTestable());
        await tester.pumpAndSettle();
        expect(reloads, 1);
        await emit('navigationStarting', gakujoHomePortalUrl);
        await emit('loadingStateChanged', windows.LoadingState.loading.index);
        await download('008.pdf', unknown);
        await finishPage(course);

        // A page-initiated same-URL reload on WebView2 may omit SourceChanged.
        nextEstimate = heldReload;
        await completePage();
        await waitFor(
          'suspended estimate before reload',
          () => nextEstimate == null,
        );
        await emit('navigationStarting', gakujoHomePortalUrl);
        await emit('loadingStateChanged', windows.LoadingState.loading.index);
        await finishPage(unknown);
        heldReload.complete(course);
        await tester.idle();
        await download('005.pdf', unknown);
        await estimateDuringDownload('009.pdf', course, course);
        await estimateDuringDownload('010.pdf', unknown, unknown);
        await estimateDuringDownload(
          '011.pdf',
          course,
          otherCourse,
          replaceDocument: false,
        );
        await estimateDuringDownload(
          '012.pdf', course, course, policyGet: true,
        );
        await estimateDuringDownload(
          '013.pdf', unknown, unknown, policyGet: true,
        );
        await startPage(coursePage);
        await finishPage(course);
        await download(
          '014.pdf', otherCourse, start: (url) => click(url, otherCourse),
        );
        await download(
          '015.pdf', unknown, start: (url) => click(url, unknown, ambiguous: true),
        );
        expect(savedCourses, expectedCourses);
        expect(await store.loadFailedDownloads(), isEmpty);
      } finally {
        if (!held.isCompleted) held.complete(course);
        if (!heldReload.isCompleted) heldReload.complete(course);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
        await waitFor('WebView disposal', () => disposed);
        for (final channel in [plugin, view, notifications, downloads]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        messenger.setMockStreamHandler(events, null);
        FlutterSecureStorage.setMockInitialValues({});
        await tester.binding.setSurfaceSize(null);
        root.deleteSync(recursive: true);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
