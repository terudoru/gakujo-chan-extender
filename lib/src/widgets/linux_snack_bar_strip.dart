import 'dart:async';

import 'package:flutter/material.dart';

class LinuxSnackBarStrip extends StatefulWidget {
  const LinuxSnackBarStrip({
    super.key,
    required this.snackBar,
    required this.onDismiss,
  });

  final SnackBar snackBar;
  final VoidCallback onDismiss;

  @override
  State<LinuxSnackBarStrip> createState() => _LinuxSnackBarStripState();
}

class _LinuxSnackBarStripState extends State<LinuxSnackBarStrip> {
  Timer? _timer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant LinuxSnackBarStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snackBar, widget.snackBar)) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _dismissed = false;
    _timer = Timer(widget.snackBar.duration, _dismiss);
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.snackBar.action;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.inverseSurface,
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: colors.onInverseSurface,
            ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: widget.snackBar.content,
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: () {
                  if (_dismissed) return;
                  _dismiss();
                  action.onPressed();
                },
                style: TextButton.styleFrom(
                  foregroundColor: action.textColor ?? colors.inversePrimary,
                  backgroundColor: action.backgroundColor,
                ),
                child: Text(action.label),
              ),
            IconButton(
              onPressed: _dismiss,
              color: colors.onInverseSurface,
              icon: const Icon(Icons.close, semanticLabel: '閉じる'),
            ),
          ],
        ),
      ),
    );
  }
}
