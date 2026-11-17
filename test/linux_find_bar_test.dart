import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/linux_find_bar.dart';

void main() {
  Future<void> showBar(
    WidgetTester tester, {
    String text = '',
    int matches = 0,
    bool found = false,
    void Function(String, bool)? onFind,
    VoidCallback? onClose,
  }) async {
    final controller = TextEditingController(text: text);
    final focusNode = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focusNode.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              LinuxFindBar(
                controller: controller,
                focusNode: focusNode,
                matches: matches,
                found: found,
                onFind: (text, {bool forward = true}) =>
                    onFind?.call(text, forward),
                onClose: onClose ?? () {},
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('typing searches only the latest text after 150 ms', (
    tester,
  ) async {
    final searches = <(String, bool)>[];
    await showBar(
      tester,
      onFind: (text, forward) {
        searches.add((text, forward));
      },
    );
    expect(find.widgetWithText(TextField, 'ページ内を検索'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'pag');
    await tester.pump(const Duration(milliseconds: 149));
    expect(searches, isEmpty);
    await tester.enterText(find.byType(TextField), 'page');
    await tester.pump(const Duration(milliseconds: 149));
    expect(searches, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(searches, [('page', true)]);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 150));
    expect(searches, [('page', true), ('', true)]);
  });

  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.f3,
  ]) {
    testWidgets(
      '${key.keyLabel} searches forward and Shift searches backward',
      (tester) async {
        final searches = <(String, bool)>[];
        await showBar(
          tester,
          onFind: (text, forward) {
            searches.add((text, forward));
          },
        );
        await tester.enterText(find.byType(TextField), 'term');
        await tester.sendKeyEvent(key);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump(const Duration(milliseconds: 150));
        expect(searches, [('term', true), ('term', false)]);
      },
    );
  }

  testWidgets('Ctrl+G searches forward and Ctrl+Shift+G searches backward', (
    tester,
  ) async {
    final searches = <(String, bool)>[];
    await showBar(
      tester,
      onFind: (text, forward) {
        searches.add((text, forward));
      },
    );
    await tester.enterText(find.byType(TextField), 'term');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 150));
    expect(searches, [('term', true), ('term', false)]);
  });

  testWidgets('previous and next search immediately in their direction', (
    tester,
  ) async {
    final searches = <(String, bool)>[];
    await showBar(
      tester,
      onFind: (text, forward) {
        searches.add((text, forward));
      },
    );
    await tester.enterText(find.byType(TextField), 'term');
    await tester.pump();
    await tester.tap(find.byTooltip('前を検索'));
    await tester.tap(find.byTooltip('次を検索'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(searches, [('term', false), ('term', true)]);
  });

  testWidgets('IME search submits once and keeps the field focused', (
    tester,
  ) async {
    final searches = <(String, bool)>[];
    await showBar(
      tester,
      onFind: (text, forward) {
        searches.add((text, forward));
      },
    );
    await tester.enterText(find.byType(TextField), 'ページ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 150));
    expect(searches, [('ページ', true)]);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
  });

  for (final escape in [true, false]) {
    testWidgets(
      '${escape ? 'Esc' : 'close button'} closes and cancels debounce',
      (tester) async {
        var closed = 0;
        final searches = <String>[];
        await showBar(
          tester,
          onFind: (text, _) => searches.add(text),
          onClose: () => closed++,
        );
        await tester.enterText(find.byType(TextField), 'pending');
        if (escape) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tap(find.byTooltip('閉じる'));
        }
        await tester.pump(const Duration(milliseconds: 150));
        expect(closed, 1);
        expect(searches, isEmpty);
      },
    );
  }

  testWidgets('Escape dismisses the text menu before closing the find bar', (
    tester,
  ) async {
    var closed = 0;
    await showBar(tester, text: 'needle', onClose: () => closed++);
    await tester.tap(
      find.byType(TextField),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    expect(closed, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final (text, found, label) in [
    ('term', true, '3件'),
    ('term', false, '見つかりません'),
    ('', true, ''),
    ('', false, ''),
  ]) {
    testWidgets('result label for text "$text", found: $found', (tester) async {
      await showBar(tester, text: text, matches: 3, found: found);
      expect(find.text('3件'), label == '3件' ? findsOneWidget : findsNothing);
      expect(
        find.text('見つかりません'),
        label == '見つかりません' ? findsOneWidget : findsNothing,
      );
      if (text.isNotEmpty) {
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(find.text(label), findsNothing);
      } else {
        for (final tooltip in ['前を検索', '次を検索']) {
          expect(
            tester
                .widget<IconButton>(
                  find.ancestor(
                    of: find.byTooltip(tooltip),
                    matching: find.byType(IconButton),
                  ),
                )
                .onPressed,
            isNull,
          );
        }
      }
    });
  }

  testWidgets('removing the strip cancels a pending search', (tester) async {
    final searches = <String>[];
    await showBar(tester, onFind: (text, _) => searches.add(text));
    await tester.enterText(find.byType(TextField), 'pending');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 150));
    expect(searches, isEmpty);
  });
}
