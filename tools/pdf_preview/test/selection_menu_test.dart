import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mbg_pdf_preview/selection_menu.dart';
import 'package:pdfrx/pdfrx.dart';

class FakeSelection implements PdfTextSelectionDelegate {
  FakeSelection({
    this.copyAllowed = true,
    this.selected = false,
    this.all = false,
    this.selectedText = '日本語テキスト\n2行目 😀',
  });

  bool copyAllowed;
  bool selected;
  bool all;
  String selectedText;
  PdfTextSelectionRange? range;
  int copyCalls = 0;
  int getTextCalls = 0;
  int clearCalls = 0;
  int selectCalls = 0;

  @override
  bool get isCopyAllowed => copyAllowed;
  @override
  bool get hasSelectedText => selected;
  @override
  bool get isSelectingAllText => all;
  @override
  PdfTextSelectionRange? get textSelectionPointRange => range;
  @override
  Future<bool> copyTextSelection() async {
    copyCalls++;
    return true;
  }

  @override
  Future<String> getSelectedText() async {
    getTextCalls++;
    return selectedText;
  }

  @override
  Future<void> clearTextSelection() async {
    clearCalls++;
    selected = false;
  }

  @override
  Future<void> selectAllText() async {
    selectCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PageText extends Fake implements PdfPageText {
  @override
  int get pageNumber => 1;
}

Widget testMenu(
  FakeSelection selection,
  TargetPlatform platform, {
  bool enabled = true,
}) {
  return MaterialApp(
    locale: const Locale('ja'),
    supportedLocales: const [Locale('ja')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(platform: platform),
    home: Scaffold(
      body: Builder(
        builder: (context) =>
            buildSelectionMenu(
              context,
              PdfViewerContextMenuBuilderParams(
                isTextSelectionEnabled: enabled,
                anchorA: const Offset(250, 250),
                textSelectionDelegate: selection,
                dismissContextMenu: () {},
                contextMenuFor: PdfViewerPart.background,
              ),
            ) ??
            const SizedBox.shrink(),
      ),
    ),
  );
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('$platform menu renders local font and dispatches actions', (
      tester,
    ) async {
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final selection = FakeSelection(selected: true);
      await tester.pumpWidget(testMenu(selection, platform));
      await tester.pumpAndSettle();

      for (final label in ['コピー', 'すべてを選択']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style?.fontFamily, 'MBGPreviewUI');
      }
      await tester.tap(find.text('コピー'));
      await tester.pump();
      await tester.tap(find.text('すべてを選択'));
      expect(selection.copyCalls, 0);
      expect(selection.getTextCalls, 1);
      expect(selection.clearCalls, 1);
      expect(selection.selected, isFalse);
      expect(copied, ['日本語テキスト\n2行目 😀']);
      expect(selection.selectCalls, 1);
    });

    testWidgets('$platform respects copy restriction and disabled selection', (
      tester,
    ) async {
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final selection = FakeSelection(copyAllowed: false, selected: true);
      await tester.pumpWidget(testMenu(selection, platform));
      await tester.pumpAndSettle();
      expect(find.text('コピー'), findsNothing);
      expect(find.text('すべてを選択'), findsOneWidget);

      await tester.pumpWidget(testMenu(selection, platform, enabled: false));
      await tester.pumpAndSettle();
      expect(find.text('コピー'), findsNothing);
      expect(find.text('すべてを選択'), findsNothing);
      expect(selection.copyCalls, 0);
      expect(selection.getTextCalls, 0);
      expect(selection.clearCalls, 0);
      expect(copied, isEmpty);
      expect(selection.selectCalls, 0);
    });
  }

  testWidgets(
    'copyPreviewSelection waits for ack and retains selection on error or empty',
    (tester) async {
      Completer<void>? ack;
      var shouldFail = false;
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
            final pendingAck = ack;
            if (pendingAck != null) await pendingAck.future;
            if (shouldFail) {
              throw PlatformException(code: 'copy_failed', message: 'failed');
            }
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final selection = FakeSelection(selected: true, selectedText: '待機確認テキスト');
      ack = Completer<void>();
      final pending = copyPreviewSelection(selection);
      await tester.pump();
      expect(copied, ['待機確認テキスト']);
      expect(selection.clearCalls, 0);
      expect(selection.selected, isTrue);

      ack.complete();
      expect(await pending, isTrue);
      expect(selection.clearCalls, 1);
      expect(selection.selected, isFalse);

      // Failure retains selection
      selection.selected = true;
      ack = null;
      shouldFail = true;
      expect(await copyPreviewSelection(selection), isFalse);
      expect(selection.clearCalls, 1);
      expect(selection.selected, isTrue);

      // Empty text does not write or clear
      shouldFail = false;
      selection.selectedText = '';
      expect(await copyPreviewSelection(selection), isFalse);
      expect(copied.length, 2);
      expect(selection.clearCalls, 1);

      // Denied permission or no selection does not read text or write
      selection.selectedText = '秘密';
      selection.copyAllowed = false;
      expect(await copyPreviewSelection(selection), isFalse);
      selection.copyAllowed = true;
      selection.selected = false;
      expect(await copyPreviewSelection(selection), isFalse);
      expect(copied.length, 2);
    },
  );

  testWidgets('a delayed copy does not clear a newly selected occurrence', (
    tester,
  ) async {
    final ack = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') await ack.future;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final page = _PageText();
    final selection = FakeSelection(selected: true, selectedText: 'same text')
      ..range = PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(page, 0),
        PdfTextSelectionPoint(page, 8),
      );
    final pending = copyPreviewSelection(selection);
    await tester.pump();
    selection.range = PdfTextSelectionRange.fromPoints(
      PdfTextSelectionPoint(page, 20),
      PdfTextSelectionPoint(page, 28),
    );
    ack.complete();
    expect(await pending, isTrue);
    expect(selection.selected, isTrue);
    expect(selection.clearCalls, 0);
  });

  testWidgets(
    'handleSelectionCopyKey copies on Ctrl/Cmd+C without clearing selection and ignores repeats',
    (tester) async {
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final selection = FakeSelection(
        selected: true,
        selectedText: 'ショートカットコピー',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                final handled = handleSelectionCopyKey(
                  selection,
                  event.logicalKey,
                  event is KeyDownEvent,
                );
                if (handled == true) return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      // Unmodified C is ignored
      expect(
        handleSelectionCopyKey(selection, LogicalKeyboardKey.keyC, true),
        isNull,
      );
      expect(copied, isEmpty);

      // Ctrl+C copies and keeps selection; key repeat is claimed but does not re-copy
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(copied, ['ショートカットコピー']);
      expect(selection.clearCalls, 0);
      expect(selection.selected, isTrue);

      expect(
        handleSelectionCopyKey(selection, LogicalKeyboardKey.keyC, false),
        isTrue,
      );
      await tester.pump();
      expect(copied.length, 1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      // Cmd+C (Meta) also copies and keeps selection
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(copied.length, 2);
      expect(selection.clearCalls, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    },
  );
}
