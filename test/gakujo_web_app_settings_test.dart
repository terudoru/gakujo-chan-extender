import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  testWidgets('download destination controls show unset state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadDestinationSection(
            rootLabel: '未設定',
            isConfigured: false,
            onPick: () async {},
            onClear: () async {},
          ),
        ),
      ),
    );

    expect(find.text('ダウンロード保存先'), findsOneWidget);
    expect(find.text('未設定'), findsOneWidget);
    expect(find.text('フォルダを選択'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '解除'))
            .enabled,
        isFalse);
  });
}
