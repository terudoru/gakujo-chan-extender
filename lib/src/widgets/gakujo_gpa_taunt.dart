import 'dart:async';

import 'package:flutter/material.dart';

const gakujoGpaTauntThreshold = 2.0;
const gakujoGpaTauntMessages = <String>[
  '可もなく、不可しかない',
  'この学年をキャンプ地とする',
  'ソビエトロシアでは単位が君を落とす',
];

bool shouldShowGakujoGpaTaunt(double? gpa) =>
    gpa != null && gpa.isFinite && gpa >= 0 && gpa < gakujoGpaTauntThreshold;

class GakujoGpaTaunt extends StatefulWidget {
  const GakujoGpaTaunt({
    super.key,
    required this.gpa,
    this.interval = const Duration(seconds: 6),
  });

  final double? gpa;
  final Duration interval;

  @override
  State<GakujoGpaTaunt> createState() => _GakujoGpaTauntState();
}

class _GakujoGpaTauntState extends State<GakujoGpaTaunt> {
  Timer? _timer;
  int _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _updateTimer();
  }

  @override
  void didUpdateWidget(covariant GakujoGpaTaunt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interval != oldWidget.interval ||
        shouldShowGakujoGpaTaunt(widget.gpa) !=
            shouldShowGakujoGpaTaunt(oldWidget.gpa)) {
      _updateTimer();
    }
  }

  void _updateTimer() {
    _timer?.cancel();
    _timer = null;
    _messageIndex = 0;
    if (!shouldShowGakujoGpaTaunt(widget.gpa)) {
      return;
    }
    _timer = Timer.periodic(widget.interval, (_) {
      setState(() {
        _messageIndex = (_messageIndex + 1) % gakujoGpaTauntMessages.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldShowGakujoGpaTaunt(widget.gpa)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          ...previousChildren,
          ?currentChild,
        ],
      ),
      child: Text(
        gakujoGpaTauntMessages[_messageIndex],
        key: ValueKey(_messageIndex),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        textAlign: TextAlign.start,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
