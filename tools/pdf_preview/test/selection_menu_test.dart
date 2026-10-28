import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mbg_pdf_preview/selection_menu.dart';
import 'package:pdfrx/pdfrx.dart';

class FakeSelection implements PdfTextSelectionDelegate {
  FakeSelection({
    this.copyAllowed = true,
    this.selected = false,
    this.all = false,
  });

  bool copyAllowed;
  bool selected;
  bool all;
  int copyCalls = 0;
  int selectCalls = 0;

  @override
  bool get isCopyAllowed => copyAllowed;
  @override
  bool get hasSelectedText => selected;
  @override
  bool get isSelectingAllText => all;
  @override
  Future<bool> copyTextSelection() async {
    copyCalls++;
    return true;
  }

  @override
  Future<void> selectAllText() async {
    selectCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
      final selection = FakeSelection(selected: true);
      await tester.pumpWidget(testMenu(selection, platform));
      await tester.pumpAndSettle();

      for (final label in ['コピー', 'すべてを選択']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style?.fontFamily, 'MBGPreviewUI');
      }
      await tester.tap(find.text('コピー'));
      await tester.tap(find.text('すべてを選択'));
      expect(selection.copyCalls, 1);
      expect(selection.selectCalls, 1);
    });

    testWidgets('$platform respects copy restriction and disabled selection', (
      tester,
    ) async {
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
      expect(selection.selectCalls, 0);
    });
  }
}
