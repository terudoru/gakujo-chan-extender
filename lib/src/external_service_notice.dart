import 'package:flutter/material.dart';

/// AKIKO, a free-classroom search run by CIRCLE, a group unrelated to this
/// app or to Niigata University's Gakujo system.
const akikoServiceUrl = 'https://akiko.niigata-circle.com/';

class ExternalServiceNoticeResult {
  const ExternalServiceNoticeResult({required this.dontShowAgain});

  final bool dontShowAgain;
}

/// Tells the user that AKIKO is an external service before it opens.
/// Returns null when the user cancels.
Future<ExternalServiceNoticeResult?> showExternalServiceNoticeDialog(
  BuildContext context,
) {
  return showDialog<ExternalServiceNoticeResult>(
    context: context,
    builder: (_) => const _ExternalServiceNoticeDialog(),
  );
}

class _ExternalServiceNoticeDialog extends StatefulWidget {
  const _ExternalServiceNoticeDialog();

  @override
  State<_ExternalServiceNoticeDialog> createState() =>
      _ExternalServiceNoticeDialogState();
}

class _ExternalServiceNoticeDialogState
    extends State<_ExternalServiceNoticeDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('外部サービスを開きます'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AKIKO は、新潟大学の空き講義室を検索できる外部サービスです。'
            'CIRCLE という団体が運営しており、このアプリや学務情報システムとは関係ありません。外部ブラウザで開きます。',
          ),
          const SizedBox(height: 8),
          SelectableText(
            akikoServiceUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _dontShowAgain,
            onChanged: (value) =>
                setState(() => _dontShowAgain = value ?? false),
            title: const Text('再度表示しない'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(ExternalServiceNoticeResult(dontShowAgain: _dontShowAgain)),
          child: const Text('開く'),
        ),
      ],
    );
  }
}
