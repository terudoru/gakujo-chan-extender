import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/widgets/gakujo_gpa_taunt.dart';

void main() {
  test('versioned JSON round trip and legacy file migration', () async {
    final original = GakujoToolbarLayout.defaults();
    expect(
      GakujoToolbarLayout.fromJson(jsonDecode(jsonEncode(original.toJson())))
          .toJson(),
      original.toJson(),
    );
    final directory = await Directory.systemTemp.createTemp('toolbar-layout');
    try {
      final store = GakujoToolbarLinksStore(directory: directory);
      final link = GakujoToolbarLink.fromInput(
        name: '独自',
        address: 'https://example.test',
      )!;
      await store.save([link]);
      final migrated = await store.loadLayout();
      expect(migrated.toolbar, original.toolbar);
      expect(migrated.links.values.single.label, '独自');
      expect(migrated.menu.first, migrated.links.keys.single);
      await store.saveLayout(migrated);
      expect((await store.loadLayout()).toJson(), migrated.toJson());
      final invalid = GakujoToolbarLayout(toolbar: [], menu: [], links: {});
      await expectLater(store.saveLayout(invalid), throwsArgumentError);
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test(
    'defaults reproduce toolbar and fixed menu including repeated actions',
    () {
      final layout = GakujoToolbarLayout.defaults();
      expect(layout.toolbar, [
        'gpa',
        'spacer',
        'navigation',
        'reload',
        'home',
        'zoom',
        'messageStars',
        'akiko',
        'settings',
        'menu',
      ]);
      expect(layout.menu, [
        ...layout.links.keys,
        'divider',
        'hostedPlanner',
        'coursePlanner',
        'notificationHistory',
        'copyCoursePlanner',
        'registrationAssist',
        'addFavorite',
        'messageStars',
        'copyUrl',
        'openExternal',
        'divider',
        'reload',
      ]);
    },
  );
  test('unknown IDs and duplicates ignored; surface constraints enforced', () {
    final layout = GakujoToolbarLayout.fromJson({
      'version': 1,
      'links': {},
      'toolbar': [
        'settings',
        'unknown',
        'settings',
        'spacer',
        'spacer',
        'divider',
      ],
      'menu': [
        'unknown',
        'reload',
        'reload',
        'divider',
        'divider',
        'spacer',
        'menu',
      ],
    });
    expect(layout.toolbar, ['settings', 'spacer']);
    expect(layout.menu, ['reload', 'divider', 'divider']);
  });
  test('settings and editor remain reachable', () {
    GakujoToolbarLayout layout(List<String> toolbar, List<String> menu) =>
        GakujoToolbarLayout(toolbar: toolbar, menu: menu, links: {});
    expect(layout(['settings'], []).validationError, isNull);
    expect(layout(['menu'], ['settings']).validationError, isNull);
    expect(layout([], ['settings']).validationError, isNotNull);
    expect(layout(['menu'], []).validationError, isNotNull);
  });
  testWidgets('custom order spans both edges and moved menu action renders', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 40,
            child: GakujoCustomToolbar(
              items: const [
                'notificationHistory',
                'spacer',
                'settings',
                'menu',
              ],
              widthOf: (id) => id == 'spacer' ? 0 : 40,
              itemBuilder: (id) => IconButton(
                key: ValueKey(id),
                tooltip: id,
                onPressed: () {},
                icon: const Icon(Icons.star),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('notificationHistory'))).dx,
      0,
    );
    expect(tester.getTopRight(find.byKey(const ValueKey('menu'))).dx, 800);
    expect(tester.takeException(), isNull);
  });
  testWidgets('360px toolbar scrolls with menu pinned and no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 40,
            child: GakujoCustomToolbar(
              items: const ['gpa', 'spacer', 'navigation', 'zoom', 'settings'],
              widthOf: (id) => id == 'spacer' ? 0 : 180,
              itemBuilder: (id) => Text(id, key: ValueKey(id)),
            ),
          ),
        ),
      ),
    );
    expect(tester.getTopRight(find.byKey(const ValueKey('menu'))).dx, 360);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  Widget gpaToolbar(double? gpa, List<String> items) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 40,
        child: GakujoCustomToolbar(
          gpa: gpa,
          items: items,
          widthOf: (id) => switch (id) {
            'gpa' => 120,
            'spacer' => 0,
            'navigation' => 80,
            'zoom' => 136,
            _ => 40,
          },
          itemBuilder: (id) => id == 'gpa'
              ? GakujoGpaTaunt(gpa: gpa)
              : IconButton(
                  key: ValueKey(id),
                  tooltip: id,
                  onPressed: () {},
                  icon: const Icon(Icons.star),
                ),
        ),
      ),
    ),
  );

  testWidgets(
    'leading GPA uses remaining width and inset with or without spacer',
    (tester) async {
      for (final spacer in [false, true]) {
        final items = ['gpa', if (spacer) 'spacer', 'reload', 'menu'];
        await tester.pumpWidget(gpaToolbar(1.5, items));
        expect(tester.getTopLeft(find.byType(GakujoGpaTaunt)).dx, 12);
        expect(tester.getSize(find.byType(GakujoGpaTaunt)).width, 708);
        expect(tester.getTopLeft(find.byKey(const ValueKey('reload'))).dx, 720);
        expect(tester.getTopRight(find.byKey(const ValueKey('menu'))).dx, 800);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('hidden GPA leaves zero width before left aligned buttons', (
    tester,
  ) async {
    for (final gpa in [null, 3.0]) {
      await tester.pumpWidget(gpaToolbar(gpa, ['gpa', 'reload', 'menu']));
      expect(find.byType(GakujoGpaTaunt), findsNothing);
      expect(tester.getTopLeft(find.byKey(const ValueKey('reload'))).dx, 0);
      expect(tester.getTopLeft(find.byKey(const ValueKey('menu'))).dx, 40);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'buttons before GPA stay at left edge with GPA present or absent',
    (tester) async {
      for (final gpa in [1.5, null]) {
        await tester.pumpWidget(
          gpaToolbar(gpa, ['reload', 'gpa', 'spacer', 'settings', 'menu']),
        );
        expect(tester.getTopLeft(find.byKey(const ValueKey('reload'))).dx, 0);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('settings'))).dx,
          720,
        );
        if (gpa != null) {
          expect(tester.getTopLeft(find.byType(GakujoGpaTaunt)).dx, 40);
          expect(tester.getSize(find.byType(GakujoGpaTaunt)).width, 680);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    '360px GPA grows or scrolls without overflow and disappears cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        gpaToolbar(1.5, ['gpa', 'spacer', 'reload', 'menu']),
      );
      expect(tester.getTopLeft(find.byType(GakujoGpaTaunt)).dx, 12);
      expect(tester.getSize(find.byType(GakujoGpaTaunt)).width, 268);
      expect(tester.takeException(), isNull);
      for (final gpa in [1.5, null]) {
        await tester.pumpWidget(
          gpaToolbar(gpa, [
            'gpa',
            'spacer',
            'navigation',
            'zoom',
            'reload',
            'settings',
            'menu',
          ]),
        );
        expect(tester.getTopRight(find.byKey(const ValueKey('menu'))).dx, 360);
        if (gpa != null) {
          expect(tester.getSize(find.byType(GakujoGpaTaunt)).width, 120);
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(-240, 0),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('editor add remove reorder reset and failed save retain edits', (
    tester,
  ) async {
    GakujoToolbarLayout? saved;
    var succeed = false;
    final initial = GakujoToolbarLayout(
      toolbar: ['settings', 'reload'],
      menu: ['copyUrl'],
      links: {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GakujoToolbarLayoutEditor(
          initialLayout: initial,
          onSave: (value) async {
            saved = value;
            return succeed;
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('ツールバー: 再読み込みの操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上へ移動'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ツールバーに追加'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('URLをコピー').last);
    await tester.tap(find.text('URLをコピー').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('︙メニュー: URLをコピーの操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配置から削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved!.toolbar, ['reload', 'settings', 'copyUrl']);
    expect(saved!.menu, isEmpty);
    expect(find.text('保存できませんでした。編集内容を残しています。'), findsOneWidget);
    await tester.ensureVisible(find.text('初期状態に戻す'));
    await tester.tap(find.text('初期状態に戻す'));
    await tester.pumpAndSettle();
    succeed = true;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved!.toJson(), GakujoToolbarLayout.defaults().toJson());
  });
  testWidgets('drag handle reorders placements and lockout refuses saving', (
    tester,
  ) async {
    GakujoToolbarLayout? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: GakujoToolbarLayoutEditor(
          initialLayout: GakujoToolbarLayout(
            toolbar: ['settings', 'reload'],
            menu: [],
            links: {},
          ),
          onSave: (value) async {
            saved = value;
            return false;
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ReorderableDragStartListener).first),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, 1));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved!.toolbar, ['reload', 'settings']);
    await tester.tap(find.byTooltip('ツールバー: 設定の操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配置から削除'));
    await tester.pumpAndSettle();
    saved = null;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.textContaining('設定と編集画面を開けなくなります'), findsOneWidget);
  });
}
