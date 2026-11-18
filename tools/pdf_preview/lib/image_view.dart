
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'preview_app.dart' show PreviewZoomController;

/// Titles carry arbitrary file names, so name the bundled fonts explicitly.
const previewTitleStyle = TextStyle(fontFamily: 'MBGPreviewUI', fontFamilyFallback: ['Unifont']);

class ImagePreview extends StatefulWidget {
  const ImagePreview({super.key, required this.title, required this.bytes, required this.onMessage, this.zoomController});
  final String title;
  final Uint8List bytes;
  final ValueChanged<String> onMessage;
  final PreviewZoomController? zoomController;

  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  final _transform = TransformationController();
  final _viewerKey = GlobalKey();
  int _rotation = 0;
  bool _reported = false;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_updateScale);
    widget.zoomController?.addListener(_nativeZoom);
  }

  void _nativeZoom() {
    final next = (_scale * widget.zoomController!.factor).clamp(.25, 8.0);
    final ratio = next / _scale;
    final viewport = _viewerKey.currentContext?.size ?? Size.zero;
    final centre = viewport.center(Offset.zero);
    final matrix = _transform.value.clone();
    final translation = matrix.getTranslation();
    matrix.scaleByDouble(ratio, ratio, 1, 1);
    matrix.setTranslationRaw((translation.x - centre.dx) * ratio + centre.dx,
        (translation.y - centre.dy) * ratio + centre.dy, 0);
    _transform.value = matrix;
  }

  void _scroll(PointerSignalEvent event) {
    // Browsers report trackpad two-finger scrolling as a mouse wheel, so
    // trackpadScrollCausesScale alone cannot distinguish it from zoom.
    if (event is! PointerScrollEvent || event.kind == PointerDeviceKind.trackpad) return;
    final viewport = _viewerKey.currentContext?.size ?? Size.zero;
    final matrix = _transform.value.clone();
    final translation = matrix.getTranslation();
    final width = viewport.width * (1 - _scale), height = viewport.height * (1 - _scale);
    matrix.setTranslationRaw(
      (translation.x - event.scrollDelta.dx).clamp(width < 0 ? width : 0, width > 0 ? width : 0),
      (translation.y - event.scrollDelta.dy).clamp(height < 0 ? height : 0, height > 0 ? height : 0), 0);
    _transform.value = matrix;
  }

  @override
  void didUpdateWidget(ImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.zoomController != oldWidget.zoomController) {
      oldWidget.zoomController?.removeListener(_nativeZoom);
      widget.zoomController?.addListener(_nativeZoom);
    }
  }

  void _updateScale() {
    final scale = _transform.value.getMaxScaleOnAxis();
    if (mounted && (scale - _scale).abs() > .001) setState(() => _scale = scale);
  }

  void _zoom(double factor) {
    final scale = (_scale * factor).clamp(.25, 8.0);
    _transform.value = Matrix4.identity()..scaleByDouble(scale, scale, 1, 1);
  }

  void _report(String value) {
    if (_reported) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onMessage(value);
    });
  }

  @override
  void dispose() {
    widget.zoomController?.removeListener(_nativeZoom);
    _transform.removeListener(_updateScale);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    void action(String value) {
      switch (value) {
        case 'fit': _transform.value = Matrix4.identity();
        case 'rotate': setState(() => _rotation = (_rotation + 1) % 4);
      }
    }
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => widget.onMessage('mbg-preview-close')},
      child: Focus(autofocus: true, child: Scaffold(
        appBar: AppBar(
          toolbarHeight: narrow ? 48 : null,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: previewTitleStyle),
          actions: [
            IconButton(tooltip: '縮小', onPressed: () => _zoom(1 / 1.2), icon: const Icon(Icons.zoom_out)),
            Text('${(_scale * 100).round()}%'),
            IconButton(tooltip: '拡大', onPressed: () => _zoom(1.2), icon: const Icon(Icons.zoom_in)),
            if (!narrow) ...[
              IconButton(tooltip: '全体を表示', onPressed: () => action('fit'), icon: const Icon(Icons.fit_screen)),
              IconButton(tooltip: '右に回転', onPressed: () => action('rotate'), icon: const Icon(Icons.rotate_right)),
            ] else PopupMenuButton<String>(tooltip: 'その他', onSelected: action, itemBuilder: (_) => const [
              PopupMenuItem(value: 'fit', child: Text('全体を表示', style: previewTitleStyle)),
              PopupMenuItem(value: 'rotate', child: Text('右に回転', style: previewTitleStyle)),
            ]),
            IconButton(tooltip: '閉じる', onPressed: () => widget.onMessage('mbg-preview-close'), icon: const Icon(Icons.close)),
          ],
        ),
        body: Listener(onPointerSignal: _scroll, child: InteractiveViewer(
          key: _viewerKey,
          transformationController: _transform,
          minScale: .25, maxScale: 8, trackpadScrollCausesScale: false,
          // PointerScaleEvent and pan/zoom pinches still use their real scale.
          scaleFactor: double.infinity,
          child: Center(child: RotatedBox(quarterTurns: _rotation, child: Image.memory(
            widget.bytes, fit: BoxFit.contain,
            frameBuilder: (context, child, frame, synchronous) {
              if (frame != null || synchronous) _report('mbg-preview-loaded');
              return child;
            },
            errorBuilder: (context, error, stack) {
              _report('mbg-preview-failed');
              return const Center(child: Text('画像を開けませんでした。', style: previewTitleStyle));
            },
          ))),
        )),
      )),
    );
  }
}
