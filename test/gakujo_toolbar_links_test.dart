import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  test(
    'menu links preserve custom order, empty lists, and standard targets',
    () async {
      final directory = await Directory.systemTemp.createTemp('toolbar-links-');
      try {
        final store = GakujoToolbarLinksStore(directory: directory);
        expect(
          (await store.load()).map((link) => link.destination),
          GakujoQuickJumpDestination.values,
        );
        final grades = GakujoQuickJumpDestination.grades;
        final renamed = GakujoToolbarLink.fromInput(
          name: '  成績表  ',
          address: grades.portalUrl,
          standardDestination: grades,
        )!;
        final custom = GakujoToolbarLink.fromInput(
          name: 'フォーム',
          address: 'https://example.test/form?a=1&a=2#section',
        )!;
        await store.save([custom, renamed]);
        final restored = await GakujoToolbarLinksStore(directory: directory)
            .load();
        expect(restored.map((link) => link.label), ['フォーム', '成績表']);
        expect(
          restored[0].address,
          'https://example.test/form?a=1&a=2#section',
        );
        expect(restored[1].destination, grades);
        await store.save([]);
        expect(await store.load(), isEmpty);
        await store.clear();
        expect(
          await store.load(),
          hasLength(GakujoQuickJumpDestination.values.length),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('only direct web URLs can become custom menu links', () {
    for (final value in [
      'javascript:alert(1)',
      '//example.test',
      'file:///c:/private',
      'https://@example.test',
      'https://user@example.test',
      'https://',
      r'https://example.test\alt',
      'https://example.test/\nfoo',
    ]) {
      expect(GakujoToolbarLink.parseUrl(value), isNull, reason: value);
    }
    expect(
      GakujoToolbarLink.parseUrl(' http://example.test:8080/path '),
      Uri.parse('http://example.test:8080/path'),
    );
  });

  testWidgets('editor validates URLs and preserves changes when saving fails', (
    tester,
  ) async {
    var attempts = 0;
    List<GakujoToolbarLink>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => GakujoToolbarLinksDialog(
                  initialLinks: GakujoToolbarLink.defaults.take(2).toList(),
                  onSave: (links) async {
                    attempts++;
                    if (attempts == 1) return false;
                    saved = links;
                    return true;
                  },
                ),
              ),
              child: const Text('設定から編集'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('設定から編集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('リンクを追加'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'フォーム');
    await tester.enterText(fields.at(1), 'mailto:a@example.test');
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();
    expect(find.text('http:// または https:// で始まるURLを入力してください'), findsOneWidget);
    await tester.enterText(fields.at(1), 'https://example.test/form');
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('フォームの操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上へ移動'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('保存できませんでした。編集内容を残しています。'), findsOneWidget);
    expect(find.text('フォーム'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('︙メニューを編集'), findsNothing);
    expect(saved?.map((link) => link.label), ['成績へ移動', 'フォーム', 'レポートへ移動']);
  });
}
