import 'package:flutter/material.dart';

import '../gakujo_notification_history.dart';

class NotificationHistoryDialog extends StatelessWidget {
  const NotificationHistoryDialog({
    super.key,
    required this.account,
    required this.activeAccount,
    required this.entries,
    required this.targetUrl,
  });

  final String? account;
  final ValueNotifier<String?> activeAccount;
  final Future<List<GakujoNotificationHistoryEntry>> entries;
  final String? Function(String?) targetUrl;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('通知履歴'),
      content: SizedBox(
        width: 520,
        child: ValueListenableBuilder(
          valueListenable: activeAccount,
          builder: (context, currentAccount, child) {
            if (account == null || currentAccount != account) {
              return const Text('学務にログインすると、通知履歴を確認できます。');
            }
            return child!;
          },
          child: FutureBuilder(
            future: entries,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('通知履歴を読み込めませんでした。');
              }
              final items = snapshot.data;
              if (items == null) return const LinearProgressIndicator();
              if (items.isEmpty) return const Text('通知履歴はありません。');
              final locale = MaterialLocalizations.of(context);
              return ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final entry = items[index];
                  final date = entry.postedAt.toLocal();
                  final time = locale.formatTimeOfDay(
                    TimeOfDay.fromDateTime(date),
                    alwaysUse24HourFormat: true,
                  );
                  final url = targetUrl(entry.url);
                  return ExpansionTile(
                    key: PageStorageKey(index),
                    title: Text(entry.title),
                    subtitle: Text('${locale.formatCompactDate(date)} $time'),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      if (entry.body.isNotEmpty)
                        SelectionArea(child: Text(entry.body)),
                      if (url != null)
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(url),
                          child: const Text('元のページを開く'),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}
