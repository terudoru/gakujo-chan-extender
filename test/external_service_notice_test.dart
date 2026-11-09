import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/external_service_notice.dart';

void main() {
  Future<ExternalServiceNoticeResult? Function()> openDialog(
    WidgetTester tester,
  ) async {
    ExternalServiceNoticeResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showExternalServiceNoticeDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('explains the external service and offers to hide the notice', (
    tester,
  ) async {
    await openDialog(tester);
    expect(find.text('外部サービスを開きます'), findsOneWidget);
    expect(find.textContaining('CIRCLE という団体が運営'), findsOneWidget);
    expect(find.text(akikoServiceUrl), findsOneWidget);
    expect(find.text('再度表示しない'), findsOneWidget);
  });

  testWidgets('cancel returns null', (tester) async {
    final result = await openDialog(tester);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
    expect(find.text('外部サービスを開きます'), findsNothing);
  });

  testWidgets('open without the checkbox keeps showing the notice', (
    tester,
  ) async {
    final result = await openDialog(tester);
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(result()?.dontShowAgain, isFalse);
  });

  testWidgets('open with the checkbox asks not to show it again', (
    tester,
  ) async {
    final result = await openDialog(tester);
    await tester.tap(find.text('再度表示しない'));
    await tester.pump();
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(result()?.dontShowAgain, isTrue);
  });
}
