import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../linux_overlay_guard.dart';

class LinuxFindBar extends StatefulWidget {
  const LinuxFindBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onFind,
    required this.onClose,
    this.matches = 0,
    this.found = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String text, {bool forward}) onFind;
  final VoidCallback onClose;
  final int matches;
  final bool found;

  @override
  State<LinuxFindBar> createState() => _LinuxFindBarState();
}

class _LinuxFindBarState extends State<LinuxFindBar> {
  Timer? _debounce;

  void _find(bool forward) {
    _debounce?.cancel();
    widget.onFind(widget.controller.text, forward: forward);
  }

  void _close() {
    _debounce?.cancel();
    widget.onClose();
  }

  void _escape() {
    if (LinuxTextSelectionToolbar.isShown) {
      ContextMenuController.removeAny();
      return;
    }
    _close();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () => _find(true),
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
            _find(false),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            _find(true),
        const SingleActivator(
          LogicalKeyboardKey.numpadEnter,
          shift: true,
        ): () =>
            _find(false),
        const SingleActivator(LogicalKeyboardKey.f3): () => _find(true),
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
            _find(false),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
            _find(true),
        const SingleActivator(
          LogicalKeyboardKey.keyG,
          control: true,
          shift: true,
        ): () =>
            _find(false),
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  contextMenuBuilder: (context, state) =>
                      LinuxTextSelectionToolbar(
                        child: AdaptiveTextSelectionToolbar.editableText(
                          editableTextState: state,
                        ),
                      ),
                  decoration: const InputDecoration(
                    hintText: 'ページ内を検索',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 150),
                      () => _find(true),
                    );
                  },
                  onSubmitted: (_) =>
                      _find(!HardwareKeyboard.instance.isShiftPressed),
                  // Keep the field focused when the IME submits a search.
                  onEditingComplete: () {},
                ),
              ),
              if (hasText)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    widget.found ? '${widget.matches}件' : '見つかりません',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              IconButton(
                tooltip: '前を検索',
                icon: const Icon(Icons.keyboard_arrow_up),
                visualDensity: VisualDensity.compact,
                onPressed: hasText ? () => _find(false) : null,
              ),
              IconButton(
                tooltip: '次を検索',
                icon: const Icon(Icons.keyboard_arrow_down),
                visualDensity: VisualDensity.compact,
                onPressed: hasText ? () => _find(true) : null,
              ),
              IconButton(
                tooltip: '閉じる',
                icon: const Icon(Icons.close),
                visualDensity: VisualDensity.compact,
                onPressed: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
