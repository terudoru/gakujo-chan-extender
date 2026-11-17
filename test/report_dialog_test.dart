import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/report_form.dart';
import 'package:morebettergakujo_flutter/src/widgets/report_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'report_form_test.dart' show FakeReportHttp, Reply;

const diagnostic =
    '{\n  "downloadHistoryCount": 2,\n  "loginCredentialsConfigured": true\n}';
const receipt = 'R-ABCDEFGH29';

class RecordingClient extends ReportClient {
  RecordingClient(this.results)
    : super(endpoint: Uri.parse('https://example.invalid/exec'));
  final List<ReportResult> results;
  final submissions = <ReportSubmission>[];
  @override
  Future<ReportResult> submit(ReportSubmission submission) async {
    submissions.add(submission);
    return results.removeAt(0);
  }
}

class DelayedClient extends ReportClient {
  DelayedClient(this.responses)
    : super(endpoint: Uri.parse('https://example.invalid/exec'));
  final List<Future<ReportResult>> responses;
  final submissions = <ReportSubmission>[];
  @override
  Future<ReportResult> submit(ReportSubmission submission) {
    submissions.add(submission);
    return responses.removeAt(0);
  }
}

Future<void> openDialog(
  WidgetTester tester, {
  ReportClient? client,
  Future<String> Function()? collect,
  Future<String> Function()? version,
  Future<void> Function(Uri)? openUrl,
  Size size = const Size(1100, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ReportDialog(
                  client:
                      client ??
                      RecordingClient([const ReportResult.success(receipt)]),
                  collectDiagnostics: collect ?? () async => diagnostic,
                  loadVersion: version ?? () async => '0.71.0',
                  onOpenUrl: openUrl ?? (_) async {},
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String name, String value) async {
  final field = find.byKey(ValueKey('report-$name'));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> validForm(WidgetTester tester) async {
  await fill(tester, 'title', 'テストの件名');
  await fill(tester, 'content', 'テストの内容');
  await tapVisible(tester, find.byKey(const ValueKey('report-consent')));
}

Future<void> send(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, '送信'));
  await tester.pumpAndSettle();
}

Future<void> selectType(WidgetTester tester, ReportType type) async {
  await tapVisible(tester, find.byKey(const ValueKey('report-type')));
  await tester.tap(find.text(type.label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'submission note reflects the actual diagnostic choice and always includes version and OS',
    (tester) async {
      const attached = '送信すると、入力した内容・アプリのバージョンとOS・診断情報を開発者に送ります。';
      const omitted = '送信すると、入力した内容・アプリのバージョンとOSを開発者に送ります。';
      await openDialog(tester);
      expect(find.text(attached), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('report-omit')));
      expect(find.text(omitted), findsOneWidget);
      expect(find.text(attached), findsNothing);
      for (final type in ReportType.values.where(
        (type) => type != ReportType.bug,
      )) {
        await selectType(tester, type);
        expect(find.text(omitted), findsOneWidget);
        expect(find.text(attached), findsNothing);
      }
    },
  );

  testWidgets(
    'required labels, consent, type guidance, hints and success explain what happens',
    (tester) async {
      await openDialog(tester);
      expect(find.text('報告の種類（必須）'), findsOneWidget);
      expect(
        find.text('どの種類も個別の返信はありません。手順と診断情報はバグ報告だけに含めます。'),
        findsOneWidget,
      );
      expect(
        find.text(
          'アプリの設定の状態と、保存している履歴・お気に入りなどの件数です。名前や内容は含みません。送る前に「送る内容を見る」で確認できます。',
        ),
        findsOneWidget,
      );
      final consent =
          tester
                  .widget<CheckboxListTile>(
                    find.byKey(const ValueKey('report-consent')),
                  )
                  .title!
              as Text;
      expect(consent.data, endsWith('公開される場合があることに同意します。（必須）'));
      await selectType(tester, ReportType.improvement);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('report-content')),
                matching: find.byType(TextField),
              ),
            )
            .decoration!
            .hintText,
        '使っている機能と、困っている点・変えてほしい点',
      );
      await selectType(tester, ReportType.other);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('report-content')),
                matching: find.byType(TextField),
              ),
            )
            .decoration!
            .hintText,
        '伝えたい内容',
      );
      await validForm(tester);
      await send(tester);
      expect(
        find.text('受付番号は送信の控えです。個別の返信はありません。すべての報告が公開されるとは限りません。'),
        findsOneWidget,
      );
    },
  );

  testWidgets('counters and submitted text both use cleaned UTF-16 lengths', (
    tester,
  ) async {
    final client = RecordingClient([const ReportResult.success(receipt)]);
    await openDialog(tester, client: client);
    for (final entry in {
      'title': 80,
      'content': 4000,
      'steps': 2000,
      'expected': 1000,
    }.entries) {
      await fill(tester, entry.key, ' \u0001あ😀 ');
      expect(find.text('3/${entry.value}'), findsOneWidget);
    }
    await tapVisible(tester, find.byKey(const ValueKey('report-consent')));
    await send(tester);
    final payload = client.submissions.single.toJson();
    for (final field in ['title', 'content', 'steps', 'expected']) {
      expect(payload[field], 'あ😀');
    }
  });

  testWidgets(
    'diagnostic state and blocked-send text distinguish missing, collecting and failure',
    (tester) async {
      final collecting = Completer<String>();
      final client = RecordingClient([]);
      await openDialog(
        tester,
        client: client,
        collect: () => collecting.future,
      );
      expect(
        find.text('診断情報はまだ集めていません。「送る内容を見る」を開くか、「送信」を押すと集めます。'),
        findsOneWidget,
      );
      expect(find.text('もう一度集める'), findsNothing);
      await tapVisible(tester, find.text('送る内容を見る'));
      expect(find.text('診断情報を集めています…'), findsOneWidget);
      expect(find.text('送信できる診断情報がありません。'), findsNothing);
      expect(find.text('診断情報を集められませんでした。'), findsNothing);
      await validForm(tester);
      await send(tester);
      expect(
        find.text(
          '診断情報を集めています。終わるまで待つか、「診断情報を付けずに送る」にチェックを入れてください。\n入力内容は残っています。',
        ),
        findsOneWidget,
      );
      expect(find.text('もう一度集める'), findsNothing);
      collecting.completeError(StateError('fake collection failure'));
      await tester.pumpAndSettle();
      expect(find.text('診断情報を集められませんでした。'), findsOneWidget);
      expect(find.text('診断情報を集めています…'), findsNothing);
      expect(find.text('もう一度集める'), findsOneWidget);
      await send(tester);
      expect(
        find.text(
          '診断情報を付けて送れません。「もう一度集める」を押すか、「診断情報を付けずに送る」にチェックを入れてください。\n入力内容は残っています。',
        ),
        findsOneWidget,
      );
      expect(client.submissions, isEmpty);
    },
  );

  testWidgets(
    'invalid shows editable field errors inline and hidden field errors by the send button',
    (tester) async {
      final client = RecordingClient([
        const ReportResult.failure(
          'invalid',
          fields: {
            'title': '件名を確認してください。',
            'version': '40文字以内にしてください。',
            'platform': '対応していないOSです。',
            'submissionKey': '受付用の情報を確認できません。',
          },
        ),
      ]);
      await openDialog(tester, client: client);
      await validForm(tester);
      await send(tester);
      expect(find.text('件名を確認してください。'), findsOneWidget);
      expect(
        find.text(
          '入力内容を確認してください。各項目の下に理由を表示しています。\nアプリのバージョン：40文字以内にしてください。\nOS：対応していないOSです。\n送る情報：受付用の情報を確認できません。\n入力内容は残っています。',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final type in ReportType.values) {
    for (final omit in (type == ReportType.bug ? [false, true] : [false])) {
      testWidgets(
        'too_large for ${type.name} omit=$omit only suggests an available diagnostic choice',
        (tester) async {
          final client = RecordingClient([
            const ReportResult.failure('too_large'),
          ]);
          await openDialog(tester, client: client);
          if (type != ReportType.bug) await selectType(tester, type);
          if (omit) {
            await tapVisible(tester, find.byKey(const ValueKey('report-omit')));
          }
          await validForm(tester);
          await send(tester);
          final attached = type == ReportType.bug && !omit;
          final message = attached
              ? '送る内容が大きすぎます。文章を短くするか、「診断情報を付けずに送る」にチェックを入れて、もう一度送ってください。'
              : '送る内容が大きすぎます。文章を短くして、もう一度送ってください。';
          expect(find.text('$message\n入力内容は残っています。'), findsOneWidget);
        },
      );
    }
  }

  testWidgets(
    'pending response locks inputs; failure restores editing and success stays fixed',
    (tester) async {
      final pending = Completer<ReportResult>();
      final client = DelayedClient([
        pending.future,
        Future.value(const ReportResult.success(receipt)),
      ]);
      await openDialog(tester, client: client);
      await validForm(tester);
      await fill(tester, 'steps', '送信前の手順');
      await fill(tester, 'expected', '送信前の期待する動作');
      await send(tester);
      expect(find.text('送信中…'), findsOneWidget);
      for (final field in ['title', 'content', 'steps', 'expected']) {
        expect(
          tester
              .widget<TextFormField>(find.byKey(ValueKey('report-$field')))
              .enabled,
          isFalse,
        );
      }
      expect(
        tester
            .widget<DropdownButtonFormField<ReportType>>(
              find.byKey(const ValueKey('report-type')),
            )
            .onChanged,
        isNull,
      );
      for (final field in ['consent', 'omit']) {
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(ValueKey('report-$field')))
              .onChanged,
          isNull,
        );
      }
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '閉じる'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '送信中…'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('report-title')));
      await tester.tap(
        find.byKey(const ValueKey('report-title')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      final titleEditor = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('report-title')),
          matching: find.byType(EditableText),
        ),
      );
      expect(titleEditor.focusNode.hasFocus, isFalse);
      expect(client.submissions, hasLength(1));
      pending.complete(const ReportResult.failure('network'));
      await tester.pumpAndSettle();
      for (final field in ['title', 'content', 'steps', 'expected']) {
        expect(
          tester
              .widget<TextFormField>(find.byKey(ValueKey('report-$field')))
              .enabled,
          isTrue,
        );
      }
      expect(
        tester
            .widget<DropdownButtonFormField<ReportType>>(
              find.byKey(const ValueKey('report-type')),
            )
            .onChanged,
        isNotNull,
      );
      for (final field in ['consent', 'omit']) {
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(ValueKey('report-$field')))
              .onChanged,
          isNotNull,
        );
      }
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('report-content')))
            .controller!
            .text,
        'テストの内容',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('report-steps')))
            .controller!
            .text,
        '送信前の手順',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('report-expected')),
            )
            .controller!
            .text,
        '送信前の期待する動作',
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('report-consent')),
            )
            .value,
        isTrue,
      );
      await fill(tester, 'content', '失敗後に修正した内容');
      await send(tester);
      expect(client.submissions.first.content, 'テストの内容');
      expect(client.submissions.last.content, '失敗後に修正した内容');
      expect(
        client.submissions.first.submissionKey,
        isNot(client.submissions.last.submissionKey),
      );
      expect(find.text('受付番号：$receipt'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(DropdownButtonFormField<ReportType>), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.text('もう1件送る'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('report-title')))
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('report-title')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  for (final type in ReportType.values) {
    testWidgets(
      '${type.name} uses one endpoint and preserves the selected type on retry',
      (tester) async {
        var collections = 0;
        final http = FakeReportHttp([
          Reply.error(),
          Reply.json({'ok': true, 'receipt': receipt}),
        ]);
        final endpoint = Uri.parse(
          'https://script.google.com/macros/s/test/exec',
        );
        await openDialog(
          tester,
          client: ReportClient(
            endpoint: endpoint,
            httpClientFactory: () => http,
          ),
          collect: () async {
            collections++;
            return diagnostic;
          },
        );
        expect(collections, 0);
        if (type != ReportType.bug) await selectType(tester, type);
        await validForm(tester);
        expect(find.text('${type.contentLabel}（必須）'), findsOneWidget);
        await send(tester);
        expect(
          tester
              .widget<DropdownButtonFormField<ReportType>>(
                find.byKey(const ValueKey('report-type')),
              )
              .initialValue,
          type,
        );
        if (type != ReportType.bug) {
          expect(find.text('送る内容を見る'), findsNothing);
          expect(find.byKey(const ValueKey('report-omit')), findsNothing);
        }
        await send(tester);
        final first = jsonDecode(utf8.decode(http.requests[0].body)) as Map;
        final second = jsonDecode(utf8.decode(http.requests[1].body)) as Map;
        expect(first, second);
        expect(first['type'], type.name);
        expect(first['diagnostic'], type == ReportType.bug ? diagnostic : null);
        expect(first['diagnosticOmitted'], isFalse);
        expect(collections, type == ReportType.bug ? 1 : 0);
        expect(
          http.requests.every((request) => request.uri == endpoint),
          isTrue,
        );
        expect(first.keys.toSet(), {
          'v',
          'client',
          'submissionKey',
          'type',
          'title',
          'content',
          'steps',
          'expected',
          'version',
          'platform',
          'consent',
          'diagnostic',
          'diagnosticOmitted',
        });
      },
    );
  }

  for (final edit in [
    'title',
    'content',
    'steps',
    'expected',
    'consent',
    'omit',
    'type',
    'diagnostic',
  ]) {
    testWidgets('editing $edit after an attempt creates a new submission key', (
      tester,
    ) async {
      final client = RecordingClient([
        const ReportResult.failure('network'),
        const ReportResult.success(receipt),
      ]);
      await openDialog(tester, client: client);
      await validForm(tester);
      await send(tester);
      switch (edit) {
        case 'title' || 'content' || 'steps' || 'expected':
          await fill(tester, edit, '変更した内容');
        case 'consent':
          await tapVisible(
            tester,
            find.byKey(const ValueKey('report-consent')),
          );
          await tapVisible(
            tester,
            find.byKey(const ValueKey('report-consent')),
          );
        case 'omit':
          await tapVisible(tester, find.byKey(const ValueKey('report-omit')));
        case 'type':
          await selectType(tester, ReportType.improvement);
        case 'diagnostic':
          await tapVisible(tester, find.text('もう一度集める'));
      }
      await send(tester);
      expect(client.submissions, hasLength(2));
      expect(
        client.submissions[0].submissionKey,
        isNot(client.submissions[1].submissionKey),
      );
      if (edit == 'type') {
        expect(client.submissions.last.type, ReportType.improvement);
      }
    });
  }

  testWidgets(
    'conflict gives its message and rotates the key for an unchanged retry',
    (tester) async {
      final http = FakeReportHttp([
        Reply.json({'ok': false, 'code': 'conflict'}),
        Reply.json({'ok': true, 'receipt': receipt}),
      ]);
      await openDialog(
        tester,
        client: ReportClient(
          endpoint: Uri.parse('https://script.google.com/macros/s/test/exec'),
          httpClientFactory: () => http,
        ),
      );
      await validForm(tester);
      await send(tester);
      expect(find.text('内容が変わったため、もう一度送ってください。\n入力内容は残っています。'), findsOneWidget);
      await send(tester);
      final first = jsonDecode(utf8.decode(http.requests.first.body)) as Map;
      final second = jsonDecode(utf8.decode(http.requests.last.body)) as Map;
      expect(
        first.remove('submissionKey'),
        isNot(second.remove('submissionKey')),
      );
      expect(first, second);
      expect(find.text('受付番号：$receipt'), findsOneWidget);
    },
  );

  testWidgets(
    'late collection does not change the key of a report sent with diagnostics omitted',
    (tester) async {
      final pending = Completer<String>();
      final client = RecordingClient([
        const ReportResult.failure('network'),
        const ReportResult.success(receipt),
      ]);
      await openDialog(tester, client: client, collect: () => pending.future);
      await tapVisible(tester, find.text('送る内容を見る'));
      await validForm(tester);
      await tapVisible(tester, find.byKey(const ValueKey('report-omit')));
      await send(tester);
      pending.complete(diagnostic);
      await tester.pumpAndSettle();
      await send(tester);
      expect(client.submissions[0].toJson(), client.submissions[1].toJson());
    },
  );

  testWidgets('transport timeout preserves payload and reuses the key', (
    tester,
  ) async {
    final http = FakeReportHttp([
      Reply.pending(),
      Reply.json({'ok': true, 'receipt': receipt, 'duplicate': true}),
    ]);
    await openDialog(
      tester,
      client: ReportClient(
        endpoint: Uri.parse('https://script.google.com/macros/s/test/exec'),
        httpClientFactory: () => http,
        requestTimeout: const Duration(milliseconds: 20),
      ),
    );
    await validForm(tester);
    await send(tester);
    expect(
      find.text('送信できたか確認できませんでした。内容を変えずにもう一度送れば、二重には登録されません。\n入力内容は残っています。'),
      findsOneWidget,
    );
    await send(tester);
    expect(
      utf8.decode(http.requests.first.body),
      utf8.decode(http.requests.last.body),
    );
    expect(find.text('受付番号：$receipt'), findsOneWidget);
  });

  testWidgets('changing away from bug discards late diagnostic collection', (
    tester,
  ) async {
    final pending = Completer<String>();
    final client = RecordingClient([const ReportResult.success(receipt)]);
    await openDialog(tester, client: client, collect: () => pending.future);
    await tapVisible(tester, find.text('送る内容を見る'));
    await selectType(tester, ReportType.other);
    pending.complete(diagnostic);
    await tester.pumpAndSettle();
    await validForm(tester);
    await send(tester);
    expect(client.submissions.single.type, ReportType.other);
    expect(client.submissions.single.diagnostic, isNull);
    expect(client.submissions.single.diagnosticOmitted, isFalse);
  });

  testWidgets('Tab and Shift-Tab move between the title and content fields', (
    tester,
  ) async {
    await openDialog(tester);
    EditableText editor(String name) => tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey('report-$name')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editor('title').focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(editor('content').focusNode.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(editor('title').focusNode.hasFocus, isTrue);
  });

  testWidgets('consent is still required after valid text is entered', (
    tester,
  ) async {
    final client = RecordingClient([]);
    await openDialog(tester, client: client);
    await fill(tester, 'title', '件名');
    await fill(tester, 'content', '内容');
    await send(tester);
    expect(find.text('確認してチェックを入れてください。'), findsOneWidget);
    expect(client.submissions, isEmpty);
  });

  testWidgets(
    'required fields and consent show inline errors without sending',
    (tester) async {
      final client = RecordingClient([]);
      await openDialog(tester, client: client);
      await send(tester);
      expect(find.text('件名を入力してください。'), findsOneWidget);
      expect(find.text('起きたことを入力してください。'), findsOneWidget);
      expect(find.text('確認してチェックを入れてください。'), findsOneWidget);
      expect(client.submissions, isEmpty);
      final message = find.text('入力内容と確認欄を見直してください。\n入力内容は残っています。');
      expect(Focus.of(tester.element(message)).hasFocus, isTrue);
    },
  );

  for (final entry in {
    'title': 80,
    'content': 4000,
    'steps': 2000,
    'expected': 1000,
  }.entries) {
    testWidgets('${entry.key} enforces UTF-16 limit with visible counter', (
      tester,
    ) async {
      final client = RecordingClient([]);
      await openDialog(tester, client: client);
      await validForm(tester);
      // Emoji consume two UTF-16 units each.
      await fill(tester, entry.key, '😀' * (entry.value ~/ 2 + 1));
      await send(tester);
      expect(find.text('${entry.value}文字以内で入力してください。'), findsOneWidget);
      expect(find.text('${entry.value + 2}/${entry.value}'), findsOneWidget);
      expect(client.submissions, isEmpty);
    });
  }

  testWidgets(
    'bug-only fields disappear for requests and are forced empty on wire',
    (tester) async {
      final http = FakeReportHttp([
        Reply.json({'ok': true, 'receipt': receipt}),
      ]);
      await openDialog(
        tester,
        client: ReportClient(
          endpoint: Uri.parse('https://script.google.com/macros/s/test/exec'),
          httpClientFactory: () => http,
        ),
      );
      await validForm(tester);
      await fill(tester, 'steps', 'a' * 2001);
      await fill(tester, 'expected', 'b' * 1001);
      await tapVisible(tester, find.byKey(const ValueKey('report-type')));
      await tester.tap(find.text('機能追加の要望').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('report-steps')), findsNothing);
      expect(find.byKey(const ValueKey('report-expected')), findsNothing);
      await send(tester);
      final json = jsonDecode(utf8.decode(http.requests.single.body)) as Map;
      expect(json['type'], 'request');
      expect(json['steps'], '');
      expect(json['expected'], '');
      expect(json['diagnostic'], isNull);
      expect(json['diagnosticOmitted'], isFalse);
      expect(find.text('受付番号：$receipt'), findsOneWidget);
    },
  );

  testWidgets('preview is exact diagnostic JSON and default attaches it', (
    tester,
  ) async {
    final client = RecordingClient([const ReportResult.success(receipt)]);
    await openDialog(tester, client: client, size: const Size(1100, 700));
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('report-omit')))
          .value,
      isFalse,
    );
    await tapVisible(tester, find.text('送る内容を見る'));
    expect(
      tester
          .widget<SelectableText>(
            find.byWidgetPredicate(
              (widget) => widget is SelectableText && widget.data == diagnostic,
            ),
          )
          .data,
      diagnostic,
    );
    await validForm(tester);
    await send(tester);
    expect(client.submissions.single.diagnostic, diagnostic);
    expect(client.submissions.single.diagnosticOmitted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'success shows receipt, distinguishes Issue number, opens Issues and resets',
    (tester) async {
      final opened = <Uri>[];
      final client = RecordingClient([
        const ReportResult.success(receipt),
        const ReportResult.success(receipt),
        const ReportResult.success(receipt),
      ]);
      await openDialog(
        tester,
        client: client,
        openUrl: (uri) async => opened.add(uri),
      );
      await validForm(tester);
      await send(tester);
      expect(find.text('受付番号：$receipt'), findsOneWidget);
      expect(find.textContaining('Issue 番号ではありません'), findsOneWidget);
      await tester.tap(find.text('GitHub の Issue 一覧を見る'));
      await tester.pumpAndSettle();
      expect(
        opened.single.toString(),
        'https://github.com/terudoru/gakujo-chan-extender/issues',
      );
      await tester.tap(find.text('もう1件送る'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('report-title')))
            .controller!
            .text,
        '',
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('report-consent')),
            )
            .value,
        isFalse,
      );
      await validForm(tester);
      await send(tester);
      expect(
        client.submissions[0].submissionKey,
        isNot(client.submissions[1].submissionKey),
      );
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await validForm(tester);
      await send(tester);
      expect(
        client.submissions.map((s) => s.submissionKey).toSet(),
        hasLength(3),
      );
    },
  );

  for (final omit in [false, true]) {
    testWidgets(
      'failure preserves all input, consent, omission=$omit and key on retry',
      (tester) async {
        final http = FakeReportHttp([
          Reply.error(),
          Reply.json({'ok': true, 'receipt': receipt, 'duplicate': true}),
        ]);
        await openDialog(
          tester,
          client: ReportClient(
            endpoint: Uri.parse('https://script.google.com/macros/s/test/exec'),
            httpClientFactory: () => http,
          ),
        );
        await validForm(tester);
        await fill(tester, 'steps', '手順を保持');
        await fill(tester, 'expected', '期待する動作を保持');
        if (omit) {
          await tapVisible(tester, find.byKey(const ValueKey('report-omit')));
        }
        await send(tester);
        const message =
            '送信できたか確認できませんでした。内容を変えずにもう一度送れば、二重には登録されません。\n入力内容は残っています。';
        expect(find.text(message), findsOneWidget);
        expect(Focus.of(tester.element(find.text(message))).hasFocus, isTrue);
        for (final entry in {
          'title': 'テストの件名',
          'content': 'テストの内容',
          'steps': '手順を保持',
          'expected': '期待する動作を保持',
        }.entries) {
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(ValueKey('report-${entry.key}')),
                )
                .controller!
                .text,
            entry.value,
          );
        }
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('report-consent')),
              )
              .value,
          isTrue,
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('report-omit')),
              )
              .value,
          omit,
        );
        await send(tester);
        final first = jsonDecode(utf8.decode(http.requests[0].body)) as Map;
        final second = jsonDecode(utf8.decode(http.requests[1].body)) as Map;
        expect(second, first);
        expect(first['diagnosticOmitted'], omit);
        expect(first['diagnostic'], omit ? null : diagnostic);
        expect(find.text('受付番号：$receipt'), findsOneWidget);
      },
    );
  }

  testWidgets('server field errors display inline and can be corrected', (
    tester,
  ) async {
    final client = RecordingClient([
      const ReportResult.failure(
        'invalid',
        fields: {'title': '別の件名を入力してください。'},
      ),
      const ReportResult.success(receipt),
    ]);
    await openDialog(tester, client: client);
    await validForm(tester);
    await send(tester);
    expect(find.text('別の件名を入力してください。'), findsOneWidget);
    await fill(tester, 'title', '修正した件名');
    await send(tester);
    expect(find.text('受付番号：$receipt'), findsOneWidget);
    expect(
      client.submissions[0].submissionKey,
      isNot(client.submissions[1].submissionKey),
    );
  });

  for (final code in [
    'unexpected',
    'rate_limited',
    'busy',
    'unavailable',
    'full',
    'too_large',
    'not_public',
  ]) {
    testWidgets('$code failure stays open with retry enabled', (tester) async {
      final result = ReportResult.failure(code, retryAfterSeconds: 120);
      final client = RecordingClient([result]);
      await openDialog(tester, client: client);
      await validForm(tester);
      await send(tester);
      expect(
        find.text(
          '${result.messageFor(includesDiagnostics: true)}\n入力内容は残っています。',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '送信'))
            .onPressed,
        isNotNull,
      );
      expect(find.byType(ReportDialog), findsOneWidget);
    });
  }

  testWidgets(
    'diagnostic failure blocks sending until collection retry succeeds',
    (tester) async {
      var calls = 0;
      final client = RecordingClient([const ReportResult.success(receipt)]);
      await openDialog(
        tester,
        client: client,
        collect: () async {
          if (++calls == 1) throw StateError('test failure');
          return diagnostic;
        },
      );
      await validForm(tester);
      await send(tester);
      expect(client.submissions, isEmpty);
      expect(
        find.text(
          '診断情報を付けて送れません。「もう一度集める」を押すか、「診断情報を付けずに送る」にチェックを入れてください。\n入力内容は残っています。',
        ),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('もう一度集める'));
      await send(tester);
      expect(client.submissions.single.diagnostic, diagnostic);
      expect(client.submissions.single.diagnosticOmitted, isFalse);
      expect(calls, 2);
    },
  );

  for (final oversize in [false, true]) {
    testWidgets(
      'diagnostic ${oversize ? 'oversize' : 'failure'} requires explicit omit choice',
      (tester) async {
        final client = RecordingClient([const ReportResult.success(receipt)]);
        await openDialog(
          tester,
          client: client,
          collect: () async {
            if (!oversize) throw StateError('test');
            return 'a' * 20001;
          },
        );
        await validForm(tester);
        await send(tester);
        expect(client.submissions, isEmpty);
        if (oversize) {
          expect(find.textContaining('20,000文字を超えている'), findsOneWidget);
        }
        await tapVisible(tester, find.byKey(const ValueKey('report-omit')));
        await send(tester);
        expect(client.submissions.single.diagnosticOmitted, isTrue);
        expect(client.submissions.single.toJson()['diagnostic'], isNull);
      },
    );
  }

  testWidgets(
    'pending diagnostics never silently omitted; explicit choice can send',
    (tester) async {
      final collecting = Completer<String>();
      final client = RecordingClient([const ReportResult.success(receipt)]);
      await openDialog(
        tester,
        client: client,
        collect: () => collecting.future,
      );
      await validForm(tester);
      await send(tester);
      expect(client.submissions, isEmpty);
      await tapVisible(tester, find.byKey(const ValueKey('report-omit')));
      await send(tester);
      expect(client.submissions.single.diagnosticOmitted, isTrue);
      collecting.complete(diagnostic);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('version lookup failure is optional and running OS is included', (
    tester,
  ) async {
    final client = RecordingClient([const ReportResult.success(receipt)]);
    await openDialog(
      tester,
      client: client,
      version: () async => throw PlatformException(code: 'unavailable'),
    );
    await validForm(tester);
    await send(tester);
    expect(client.submissions.single.version, '');
    expect(client.submissions.single.platform, 'windows');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'late diagnostics from a previous report cannot replace the new report',
    (tester) async {
      final previous = Completer<String>();
      var collections = 0;
      final client = RecordingClient([
        const ReportResult.success(receipt),
        const ReportResult.success(receipt),
      ]);
      await openDialog(
        tester,
        client: client,
        collect: () {
          if (++collections == 1) return previous.future;
          return Future.value(diagnostic);
        },
      );
      await tapVisible(tester, find.text('送る内容を見る'));
      await validForm(tester);
      await tapVisible(tester, find.byKey(const ValueKey('report-omit')));
      await send(tester);
      await tester.tap(find.text('もう1件送る'));
      await tester.pumpAndSettle();
      previous.complete('{"stale":true}');
      await tester.pumpAndSettle();
      await validForm(tester);
      await send(tester);
      expect(client.submissions.last.diagnosticOmitted, isFalse);
      expect(client.submissions.last.diagnostic, diagnostic);
    },
  );

  testWidgets('PackageInfo version is used by default', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1.2.3',
      buildNumber: '4',
      buildSignature: '',
    );
    final client = RecordingClient([const ReportResult.success(receipt)]);
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDialog(
          client: client,
          collectDiagnostics: () async => diagnostic,
          onOpenUrl: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await validForm(tester);
    await send(tester);
    expect(client.submissions.single.version, '1.2.3');
  });

  test('every OS maps to the contract value', () {
    expect(
      {
        for (final platform in TargetPlatform.values)
          platform: reportPlatform(platform),
      },
      {
        TargetPlatform.windows: 'windows',
        TargetPlatform.macOS: 'macos',
        TargetPlatform.linux: 'linux',
        TargetPlatform.android: 'android',
        TargetPlatform.iOS: 'ios',
        TargetPlatform.fuchsia: 'other',
      },
    );
  });
}
