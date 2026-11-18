import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

// pdfrx's web copy bypasses Flutter's platform channel and ignores the
// clipboard promise. Keep selection until the app confirms the write.
Future<bool> copyPreviewSelection(
  PdfTextSelectionDelegate selection, {
  bool clearSelection = true,
}) async {
  if (!selection.isCopyAllowed || !selection.hasSelectedText) return false;
  try {
    final range = selection.textSelectionPointRange;
    final all = selection.isSelectingAllText;
    bool stillSelected() {
      final current = selection.textSelectionPointRange;
      return selection.hasSelectedText &&
          selection.isSelectingAllText == all &&
          current?.start == range?.start &&
          current?.end == range?.end;
    }

    final text = await selection.getSelectedText();
    if (text.isEmpty || !stillSelected()) return false;
    await Clipboard.setData(ClipboardData(text: text));
    if (clearSelection && stillSelected()) await selection.clearTextSelection();
    return true;
  } catch (_) {
    return false;
  }
}

bool? handleSelectionCopyKey(
  PdfTextSelectionDelegate selection,
  LogicalKeyboardKey key,
  bool isRealKeyPress,
) {
  if (key != LogicalKeyboardKey.keyC ||
      !(HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed)) {
    return null;
  }
  if (isRealKeyPress) {
    unawaited(copyPreviewSelection(selection, clearSelection: false));
  }
  return true;
}

Widget? buildSelectionMenu(
  BuildContext context,
  PdfViewerContextMenuBuilderParams params,
) {
  final selection = params.textSelectionDelegate;
  final labels = MaterialLocalizations.of(context);
  final actions = <(String, VoidCallback)>[
    if (params.isTextSelectionEnabled &&
        selection.isCopyAllowed &&
        selection.hasSelectedText)
      (
        labels.copyButtonLabel,
        () => unawaited(copyPreviewSelection(selection)),
      ),
    if (params.isTextSelectionEnabled && !selection.isSelectingAllText)
      (labels.selectAllButtonLabel, () => unawaited(selection.selectAllText())),
  ];
  if (actions.isEmpty) return null;
  final platform = Theme.of(context).platform;
  final desktop =
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS;
  return Align(
    alignment: Alignment.topLeft,
    child: AdaptiveTextSelectionToolbar(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: params.anchorA,
        secondaryAnchor: params.anchorB,
      ),
      children: [
        for (var i = 0; i < actions.length; i++)
          if (desktop)
            DesktopTextSelectionToolbarButton(
              onPressed: actions[i].$2,
              child: Text(
                actions[i].$1,
                style: const TextStyle(
                  fontFamily: 'MBGPreviewUI',
                  fontFamilyFallback: ['Unifont'],
                  fontSize: 14,
                ),
              ),
            )
          else
            TextSelectionToolbarTextButton(
              padding: TextSelectionToolbarTextButton.getPadding(
                i,
                actions.length,
              ),
              onPressed: actions[i].$2,
              child: Text(
                actions[i].$1,
                style: const TextStyle(
                  fontFamily: 'MBGPreviewUI',
                  fontFamilyFallback: ['Unifont'],
                ),
              ),
            ),
      ],
    ),
  );
}
