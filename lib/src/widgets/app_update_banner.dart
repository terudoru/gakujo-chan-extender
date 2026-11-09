import 'package:flutter/material.dart';

class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({
    super.key,
    required this.latestVersion,
    required this.currentVersion,
    required this.onOpen,
    required this.onDismiss,
  });

  final String latestVersion;
  final String currentVersion;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: const Icon(Icons.system_update_alt),
      content: Text('新しいバージョン $latestVersion があります（現在 $currentVersion）'),
      actions: [
        TextButton(onPressed: onOpen, child: const Text('リリースページを開く')),
        TextButton(onPressed: onDismiss, child: const Text('閉じる')),
      ],
    );
  }
}
