import 'package:flutter/material.dart';

import '../registration_handoff.dart';

class RegistrationAssistPanel extends StatelessWidget {
  const RegistrationAssistPanel({
    super.key,
    required this.status,
    this.onSkip,
    this.onNext,
    this.onCancel,
    this.onClose,
    this.onCopy,
  });

  final String status;
  final VoidCallback? onSkip;
  final VoidCallback? onNext;
  final VoidCallback? onCancel;
  final VoidCallback? onClose;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .36,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(liveRegion: true, child: Text(status)),
                if (onCancel != null) const Text(registrationSafetyText),
                Wrap(
                  spacing: 8,
                  children: [
                    if (onSkip != null)
                      TextButton(
                        onPressed: onSkip,
                        child: const Text('この科目を飛ばす'),
                      ),
                    if (onNext != null)
                      FilledButton(
                        onPressed: onNext,
                        child: const Text('次の科目へ'),
                      ),
                    if (onCancel != null)
                      TextButton(onPressed: onCancel, child: const Text('中止')),
                    if (onClose != null)
                      TextButton(onPressed: onClose, child: const Text('閉じる')),
                    if (onCopy != null)
                      TextButton(
                        onPressed: onCopy,
                        child: const Text('登録状況を履修手帖用にコピー'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
