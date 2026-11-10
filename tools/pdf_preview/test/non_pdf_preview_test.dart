import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbg_pdf_preview/image_view.dart';
import 'package:mbg_pdf_preview/text_view.dart';

void main() {
  testWidgets('text search navigates matches and adjusts font size', (tester) async {
    final messages = <String>[];
    await tester.pumpWidget(MaterialApp(home: TextPreview(
      title: 'sample.txt', text: 'red blue\nred green\nred',
      note: 'notice', onMessage: messages.add,
    )));
    expect(find.text('notice'), findsOneWidget);
    await tester.tap(find.text('閉じる').first);
    await tester.pump();
    expect(find.text('notice'), findsNothing);
    await tester.tap(find.byTooltip('検索'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'red');
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('次の検索結果'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('前の検索結果'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    final lineFinder = find.byWidgetPredicate((widget) => widget is Text && widget.textSpan != null);
    final textBefore = tester.widget<Text>(lineFinder.first);
    final oldSize = textBefore.style!.fontSize!;
    await tester.tap(find.byTooltip('拡大'));
    await tester.pumpAndSettle();
    final textAfter = tester.widget<Text>(lineFinder.first);
    expect(textAfter.style!.fontSize, oldSize + 2);
    await tester.tap(find.byTooltip('閉じる'));
    expect(messages, contains('mbg-preview-close'));
  });

  testWidgets('image reports decode and close', (tester) async {
    final messages = <String>[];
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
    await tester.pumpWidget(MaterialApp(home: ImagePreview(title: 'image.png', bytes: png, onMessage: messages.add)));
    // Image decoding completes outside the fake test clock.
    for (var i = 0; i < 20 && !messages.contains('mbg-preview-loaded'); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(messages, contains('mbg-preview-loaded'));
    await tester.tap(find.byTooltip('拡大'));
    await tester.pump();
    expect(find.text('120%'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(messages, contains('mbg-preview-close'));
  });

  testWidgets('invalid image reports failure', (tester) async {
    final messages = <String>[];
    await tester.pumpWidget(MaterialApp(home: ImagePreview(title: 'bad', bytes: Uint8List.fromList([1, 2, 3]), onMessage: messages.add)));
    for (var i = 0; i < 20 && !messages.contains('mbg-preview-failed'); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(messages, contains('mbg-preview-failed'));
  });
}
