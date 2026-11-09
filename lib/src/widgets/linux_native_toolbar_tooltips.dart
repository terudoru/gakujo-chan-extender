import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uses GTK tooltips so they appear above the native Linux WebView.
class LinuxNativeToolbarTooltips extends StatefulWidget {
  const LinuxNativeToolbarTooltips({super.key, required this.child});

  final Widget child;

  @override
  State<LinuxNativeToolbarTooltips> createState() =>
      _LinuxNativeToolbarTooltipsState();
}

class _LinuxNativeToolbarTooltipsState
    extends State<LinuxNativeToolbarTooltips> {
  static const _channel = MethodChannel('com.abandoft.webview_all_linux');
  String? _currentMessage;

  void _setMessage(String? message) {
    if (_currentMessage == message) return;
    _currentMessage = message;
    unawaited(_sendMessage(message));
  }

  Future<void> _sendMessage(String? message) async {
    try {
      await _channel.invokeMethod<void>('setFlutterTooltip', {
        'message': message,
      });
    } on MissingPluginException {
      // The view may already be shutting down.
    } on PlatformException catch (error) {
      debugPrint('Could not update the Linux toolbar tooltip: $error');
    }
  }

  void _updateAt(Offset position) {
    String? message;
    void visit(Element element) {
      final candidate = element.widget;
      if (candidate is Tooltip) {
        final render = element.findRenderObject();
        if (render is RenderBox && render.hasSize && render.attached) {
          final local = render.globalToLocal(position);
          if ((Offset.zero & render.size).contains(local)) {
            message = candidate.message ?? candidate.richMessage?.toPlainText();
          }
        }
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    _setMessage(message);
  }

  @override
  void dispose() {
    if (_currentMessage != null) unawaited(_sendMessage(null));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TooltipTheme.of(context);
    return MouseRegion(
      onEnter: (event) => _updateAt(event.position),
      onHover: (event) => _updateAt(event.position),
      onExit: (_) => _setMessage(null),
      child: TooltipTheme(
        // Keep Flutter's tooltip semantics and non-mouse triggers, while GTK
        // supplies the visible tooltip for mouse hover.
        data: theme.copyWith(waitDuration: const Duration(days: 1)),
        child: widget.child,
      ),
    );
  }
}
