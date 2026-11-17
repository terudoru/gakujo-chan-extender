import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/app_data_sections.dart';
import 'package:morebettergakujo_flutter/src/widgets/report_dialog.dart';

void main() {
  Future<void> showSection(
    WidgetTester tester, {
    Uri? endpoint,
    required Future<void> Function(Uri) onOpenUrl,
    required Future<void> Function() onCreateErrorReport,
  }) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: AppSupportSection(
              reportEndpoint: endpoint,
              loadVersion: () async => '',
              collectDiagnostics: () async => '{"downloadHistoryCount":2}',
              onOpenUrl: onOpenUrl,
              onCreateErrorReport: onCreateErrorReport,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'disabled report keeps package, GitHub action and warning unchanged',
    (tester) async {
      final opened = <Uri>[];
      var packages = 0;
      await showSection(
        tester,
        onOpenUrl: (uri) async => opened.add(uri),
        onCreateErrorReport: () async {
          packages++;
        },
      );
      expect(find.text('アプリから報告する'), findsNothing);
      expect(find.byType(OutlinedButton), findsNWidgets(2));
      expect(
        find.text('GitHub の投稿はすぐに公開されます。氏名・学籍番号・ログイン情報・学情の画面内容は書かないでください。'),
        findsOneWidget,
      );
      await tester.tap(find.text('エラー報告パッケージ作成'));
      await tester.pumpAndSettle();
      expect(packages, 1);
      await tester.tap(find.text('GitHub で報告（アカウントが必要）'));
      await tester.pumpAndSettle();
      expect(opened, [
        Uri.parse(
          'https://github.com/terudoru/gakujo-chan-extender/issues/new',
        ),
      ]);
    },
  );

  testWidgets(
    'enabled report opens the in-app dialog without launching a browser',
    (tester) async {
      final opened = <Uri>[];
      await showSection(
        tester,
        endpoint: Uri.parse('https://script.google.com/macros/s/test/exec'),
        onOpenUrl: (uri) async => opened.add(uri),
        onCreateErrorReport: () async {},
      );
      expect(find.byType(OutlinedButton), findsNWidgets(3));
      await tester.tap(find.text('アプリから報告する'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportDialog), findsOneWidget);
      expect(opened, isEmpty);
      expect(find.text('件名（必須）'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GitHub で報告（アカウントが必要）'));
      await tester.pumpAndSettle();
      expect(opened.single.path, '/terudoru/gakujo-chan-extender/issues/new');
    },
  );
}
