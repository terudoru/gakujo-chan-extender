import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

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
      (labels.copyButtonLabel, () => unawaited(selection.copyTextSelection())),
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
