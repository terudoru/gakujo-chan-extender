import 'package:flutter/material.dart';

const _toolbarButtonExtent = 40.0;
const _toolbarIconSize = 20.0;
const _zoomResetButtonWidth = 56.0;

class GakujoNavigationActions extends StatelessWidget {
  const GakujoNavigationActions({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '前のページ',
          onPressed: canGoBack ? onBack : null,
          icon: const Icon(Icons.arrow_back),
          iconSize: _toolbarIconSize,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(
            width: _toolbarButtonExtent,
            height: _toolbarButtonExtent,
          ),
        ),
        IconButton(
          tooltip: '次のページ',
          onPressed: canGoForward ? onForward : null,
          icon: const Icon(Icons.arrow_forward),
          iconSize: _toolbarIconSize,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(
            width: _toolbarButtonExtent,
            height: _toolbarButtonExtent,
          ),
        ),
      ],
    );
  }
}

class GakujoZoomActions extends StatelessWidget {
  const GakujoZoomActions({
    super.key,
    required this.zoomPercent,
    required this.canZoomOut,
    required this.canZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final int zoomPercent;
  final bool canZoomOut;
  final bool canZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '縮小',
          onPressed: canZoomOut ? onZoomOut : null,
          icon: const Icon(Icons.remove),
          iconSize: _toolbarIconSize,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(
            width: _toolbarButtonExtent,
            height: _toolbarButtonExtent,
          ),
        ),
        TextButton(
          onPressed: onReset,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            fixedSize: const Size(_zoomResetButtonWidth, _toolbarButtonExtent),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            '$zoomPercent%',
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ),
        IconButton(
          tooltip: '拡大',
          onPressed: canZoomIn ? onZoomIn : null,
          icon: const Icon(Icons.add),
          iconSize: _toolbarIconSize,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(
            width: _toolbarButtonExtent,
            height: _toolbarButtonExtent,
          ),
        ),
      ],
    );
  }
}
