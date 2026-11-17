import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/app_data_sections.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  Future<void> showSection(
    WidgetTester tester, {
    Uri? formUri,
    Future<String> Function()? loadVersion,
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
              reportFormUri: formUri,
              loadVersion: loadVersion,
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
    'disabled form keeps only package creation and GitHub reporting',
    (tester) async {
      final opened = <Uri>[];
      var packagesCreated = 0;
      await showSection(
        tester,
        onOpenUrl: (uri) async => opened.add(uri),
        onCreateErrorReport: () async {
          packagesCreated++;
        },
      );
      expect(find.text('不具合・要望の報告'), findsOneWidget);
      expect(find.text('報告フォームを開く'), findsNothing);
      expect(find.textContaining('フォームから'), findsNothing);
      expect(find.byType(OutlinedButton), findsNWidgets(2));
      expect(
        find.text('GitHub の投稿はすぐに公開されます。氏名・学籍番号・ログイン情報・学情の画面内容は書かないでください。'),
        findsOneWidget,
      );
      expect(opened, isEmpty);
      await tester.tap(find.text('エラー報告パッケージ作成'));
      await tester.pumpAndSettle();
      expect(packagesCreated, 1);
      await tester.tap(find.text('GitHub で報告（アカウントが必要）'));
      await tester.pumpAndSettle();
      expect(opened, [
        Uri.parse(
          'https://github.com/terudoru/gakujo-chan-extender/issues/new',
        ),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'version lookup failure still allows the form and GitHub to open',
    (tester) async {
      final opened = <Uri>[];
      await showSection(
        tester,
        formUri: Uri.https('gakujo-report.terudoru.com', '/'),
        loadVersion: () async => throw PlatformException(code: 'unavailable'),
        onOpenUrl: (uri) async => opened.add(uri),
        onCreateErrorReport: () async {},
      );
      await tester.tap(find.text('報告フォームを開く'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(opened.single.queryParameters, {
        'type': 'bug',
        'version': '',
        'platform': 'windows',
      });
      await tester.tap(find.text('GitHub で報告（アカウントが必要）'));
      await tester.pumpAndSettle();
      expect(
        opened.last,
        Uri.parse(
          'https://github.com/terudoru/gakujo-chan-extender/issues/new',
        ),
      );
      expect(opened, hasLength(2));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'enabled form opens on demand with package version and running OS',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'More Better Gakujo',
        packageName: 'example.app',
        version: '1.2.3',
        buildNumber: '42',
        buildSignature: '',
      );
      final opened = <Uri>[];
      await showSection(
        tester,
        formUri: Uri.https('gakujo-report.terudoru.com', '/'),
        onOpenUrl: (uri) async => opened.add(uri),
        onCreateErrorReport: () async {},
      );
      expect(find.textContaining('GitHub のアカウントがなくても'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNWidgets(3));
      expect(find.textContaining('GitHub の投稿はすぐに公開されます。'), findsOneWidget);
      expect(opened, isEmpty);
      await tester.tap(find.text('報告フォームを開く'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(opened.single.queryParameters, {
        'type': 'bug',
        'version': '1.2.3',
        'platform': 'linux',
      });
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
