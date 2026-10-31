import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/app_about_section.dart';

void main() {
  testWidgets('shows version and opens source and licenses', (tester) async {
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppAboutSection(
              loadVersion: () async => '1.2.3',
              onOpenUrl: (url) => opened = url,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('バージョン 1.2.3'), findsOneWidget);
    await tester.ensureVisible(find.text('ソースコード'));
    await tester.tap(find.text('ソースコード'));
    expect(
      opened,
      Uri.parse('https://github.com/terudoru/gakujo-chan-extender'),
    );
    await tester.ensureVisible(find.text('オープンソースライセンス'));
    await tester.tap(find.text('オープンソースライセンス'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
