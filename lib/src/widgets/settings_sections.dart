import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../gakujo_app_settings.dart';

const List<GakujoFeatureFlag> settingsLoginFeatureFlags = [
  GakujoFeatureFlag.loginAutofill,
  GakujoFeatureFlag.twoFactorAutofill,
  GakujoFeatureFlag.sessionExtender,
];

const List<GakujoFeatureFlag> settingsReportFeatureFlags = [
  GakujoFeatureFlag.uploadCompression,
];

const List<GakujoFeatureFlag> settingsDownloadFeatureFlags = [
  GakujoFeatureFlag.downloadCapture,
];

const List<GakujoFeatureFlag> settingsNotificationFeatureFlags = [
  GakujoFeatureFlag.deadlineNotifications,
];

const List<GakujoFeatureFlag> settingsBackupFeatureFlags = [
  GakujoFeatureFlag.autoBackup,
];

const List<GakujoFeatureFlag> settingsAppFeatureFlags = [
  GakujoFeatureFlag.updateNotice,
];

const List<List<GakujoFeatureFlag>> settingsFeatureFlagGroups = [
  settingsLoginFeatureFlags,
  settingsReportFeatureFlags,
  settingsDownloadFeatureFlags,
  settingsNotificationFeatureFlags,
  settingsBackupFeatureFlags,
  settingsAppFeatureFlags,
];

class TwoFactorSecretSection extends StatelessWidget {
  const TwoFactorSecretSection({
    super.key,
    required this.canSave,
    required this.onChanged,
    this.onClear,
    this.onSave,
    this.controller,
  });

  final TextEditingController? controller;
  final bool canSave;
  final ValueChanged<String> onChanged;
  final Future<void> Function()? onClear;
  final Future<void> Function()? onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '2FA秘密鍵',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'QRコード横の長いBase32文字列を保存します。6桁コードではありません。保存済みの秘密鍵は表示しません。\n注意: 秘密鍵を保存すると、パスワードと2段階認証の両方がこの端末にそろいます。端末やその保存データが他人の手に渡ると2段階認証では防げないため、共用の端末では保存しないでください。\n取得方法: https://github.com/koji-genba/gakujo-chan-extender#2段階認証自動入力',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '2FA秘密鍵（長いBase32文字列）',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
        ),
        if (onSave != null || onClear != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: canSave && onSave != null
                    ? () => unawaited(onSave!())
                    : null,
                icon: const Icon(Icons.key),
                label: const Text('秘密鍵を保存'),
              ),
              if (onClear case final clear?)
                TextButton.icon(
                  onPressed: () => unawaited(clear()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('秘密鍵を削除'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class SecretProtectionSection extends StatelessWidget {
  const SecretProtectionSection({super.key, required this.enabled,
    required this.isAndroid, required this.onChanged});

  final bool enabled;
  final bool isAndroid;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: const Text('ログイン情報を使うときに本人確認する'),
    subtitle: Text(isAndroid
      ? 'Android 11以降で利用できます。指紋・顔または端末のPINなどで本人確認します。キャンセルすると自動ログインを一時停止します。'
      : '自動ログインのたびにFace ID・Touch ID・パスコードで確認します。本人確認をキャンセルすると、そのときは自動ログインしません。'),
    value: enabled,
    onChanged: onChanged,
  );
}

class LoginCredentialsSection extends StatelessWidget {
  const LoginCredentialsSection({
    super.key,
    required this.isConfigured,
    required this.canSave,
    required this.onLoginIdChanged,
    required this.onPasswordChanged,
    this.onClear,
    this.onSave,
    this.loginIdController,
    this.passwordController,
  });

  final TextEditingController? loginIdController;
  final TextEditingController? passwordController;
  final bool isConfigured;
  final bool canSave;
  final ValueChanged<String> onLoginIdChanged;
  final ValueChanged<String> onPasswordChanged;
  final Future<void> Function()? onClear;
  final Future<void> Function()? onSave;

  @override
  Widget build(BuildContext context) {
    final status = isConfigured ? '保存済み' : '未設定';

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ログイン自動入力',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'ログインIDとパスワードを端末内に保存します。保存済みの場合、起動直後のログイン画面で入力とログイン操作を自動で行います。現在の状態: $status',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: loginIdController,
            decoration: const InputDecoration(
              labelText: 'ログインID',
              border: OutlineInputBorder(),
            ),
            autofillHints: const [
              AutofillHints.username,
              AutofillHints.email,
            ],
            keyboardType: TextInputType.emailAddress,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: onLoginIdChanged,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: passwordController,
            decoration: const InputDecoration(
              labelText: 'パスワード',
              border: OutlineInputBorder(),
            ),
            autofillHints: const [AutofillHints.password],
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: onPasswordChanged,
          ),
          if (onSave != null || onClear != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: canSave && onSave != null
                      ? () => unawaited(onSave!())
                      : null,
                  icon: const Icon(Icons.login),
                  label: const Text('ログイン情報を保存'),
                ),
                if (onClear case final clear?)
                  TextButton.icon(
                    onPressed: () => unawaited(clear()),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('ログイン情報を削除'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class DownloadDestinationSection extends StatelessWidget {
  const DownloadDestinationSection({
    super.key,
    required this.rootLabel,
    required this.isConfigured,
    required this.saveMode,
    required this.helperText,
    required this.onSaveModeChanged,
    required this.onPick,
    required this.onClear,
  });

  final String rootLabel;
  final bool isConfigured;
  final DownloadSaveMode saveMode;
  final String? helperText;
  final ValueChanged<DownloadSaveMode?> onSaveModeChanged;
  final Future<void> Function() onPick;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '保存方法と保存先',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SettingsRadioGroup<DownloadSaveMode>(
          groupValue: saveMode,
          values: DownloadSaveMode.values,
          labelFor: (mode) => mode.label,
          onChanged: onSaveModeChanged,
          decoration: const InputDecoration(
            labelText: 'ファイル保存モード',
            border: OutlineInputBorder(),
          ),
        ),
        if (saveMode.needsConfiguredRoot) ...[
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '保存先フォルダ',
              border: OutlineInputBorder(),
            ),
            child: Text(rootLabel),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.folder_open),
                label: const Text('フォルダを選択'),
              ),
              if (isConfigured)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.link_off),
                  label: const Text('解除'),
                ),
            ],
          ),
        ],
        if (helperText != null) ...[
          const SizedBox(height: 8),
          Text(helperText!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class SettingsRadioGroup<T> extends StatelessWidget {
  const SettingsRadioGroup({
    super.key,
    required this.groupValue,
    required this.values,
    required this.labelFor,
    required this.onChanged,
    required this.decoration,
  });

  final T groupValue;
  final Iterable<T> values;
  final String Function(T value) labelFor;
  final ValueChanged<T?> onChanged;
  final InputDecoration decoration;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: decoration,
      child: RadioGroup<T>(
        groupValue: groupValue,
        onChanged: onChanged,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in values)
              RadioListTile<T>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: value,
                title: Text(labelFor(value)),
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsExpansionSection extends StatelessWidget {
  const SettingsExpansionSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
    this.focusNodeOnExpand,
    this.onExpansionChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;
  final FocusNode? focusNodeOnExpand;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      initiallyExpanded: initiallyExpanded,
      maintainState: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      onExpansionChanged: (expanded) {
        onExpansionChanged?.call(expanded);
        final focusNode = focusNodeOnExpand;
        if (!expanded || focusNode == null) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && focusNode.canRequestFocus) {
            focusNode.requestFocus();
          }
        });
      },
      children: [child],
    );
  }
}

class GakujoPageModeSection extends StatelessWidget {
  const GakujoPageModeSection({
    super.key,
    required this.pageMode,
    required this.onChanged,
  });

  final GakujoPageMode pageMode;
  final ValueChanged<GakujoPageMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '表示版',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SettingsRadioGroup<GakujoPageMode>(
          groupValue: pageMode,
          values: GakujoPageMode.values,
          labelFor: (mode) => mode.label,
          onChanged: onChanged,
          decoration: const InputDecoration(
            labelText: '開く画面',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class GakujoStartupPageSection extends StatelessWidget {
  const GakujoStartupPageSection({
    super.key,
    required this.page,
    required this.onChanged,
  });
  final GakujoStartupPage page;
  final ValueChanged<GakujoStartupPage?> onChanged;
  @override
  Widget build(BuildContext context) => SettingsRadioGroup<GakujoStartupPage>(
    groupValue: page,
    values: GakujoStartupPage.values,
    labelFor: (value) => value.label,
    onChanged: onChanged,
    decoration: const InputDecoration(
      labelText: '起動時に開くページ',
      border: OutlineInputBorder(),
    ),
  );
}

class GakujoDesktopZoomSection extends StatelessWidget {
  const GakujoDesktopZoomSection({
    super.key,
    required this.settings,
    required this.onStartupChanged,
    required this.onFixedPercentChanged,
    required this.onStepChanged,
  });
  final GakujoDesktopZoomSettings settings;
  final ValueChanged<GakujoStartupZoom> onStartupChanged;
  final ValueChanged<int> onFixedPercentChanged;
  final ValueChanged<int> onStepChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsRadioGroup<GakujoStartupZoom>(
        groupValue: settings.startup,
        values: GakujoStartupZoom.values,
        labelFor: (value) =>
            value == GakujoStartupZoom.previous ? '前回の倍率を引き継ぐ' : '固定値',
        onChanged: (value) {
          if (value != null) onStartupChanged(value);
        },
        decoration: const InputDecoration(
          labelText: '起動時の表示倍率',
          border: OutlineInputBorder(),
        ),
      ),
      if (settings.startup == GakujoStartupZoom.fixed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: '固定の表示倍率',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                value: settings.fixedPercent,
                items: [
                  for (var value = 50; value <= 200; value++)
                    DropdownMenuItem(value: value, child: Text('$value%')),
                ],
                onChanged: (value) {
                  if (value != null) onFixedPercentChanged(value);
                },
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      SettingsRadioGroup<int>(
        groupValue: settings.stepPercent,
        values: GakujoDesktopZoomSettings.steps,
        labelFor: (value) => '$value%',
        onChanged: (value) {
          if (value != null) onStepChanged(value);
        },
        decoration: const InputDecoration(
          labelText: '拡大・縮小の刻み',
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );
}

class GakujoAutoBackupSection extends StatelessWidget {
  const GakujoAutoBackupSection({
    super.key,
    required this.settings,
    required this.onIntervalChanged,
    required this.onGenerationsChanged,
  });
  final GakujoAutoBackupSettings settings;
  final ValueChanged<int?> onIntervalChanged;
  final ValueChanged<int?> onGenerationsChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsRadioGroup<int>(
        groupValue: settings.intervalHours,
        values: GakujoAutoBackupSettings.intervals,
        labelFor: (value) => '$value時間',
        onChanged: onIntervalChanged,
        decoration: const InputDecoration(
          labelText: '自動バックアップの間隔',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      SettingsRadioGroup<int>(
        groupValue: settings.generations,
        values: GakujoAutoBackupSettings.generationCounts,
        labelFor: (value) => '$value世代',
        onChanged: onGenerationsChanged,
        decoration: const InputDecoration(
          labelText: '残す世代数',
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );
}

class GakujoReportInitialSortSection extends StatelessWidget {
  const GakujoReportInitialSortSection({
    super.key,
    required this.sort,
    required this.onChanged,
  });
  final GakujoReportInitialSort sort;
  final ValueChanged<GakujoReportInitialSort?> onChanged;
  @override
  Widget build(BuildContext context) =>
      SettingsRadioGroup<GakujoReportInitialSort>(
        groupValue: sort,
        values: GakujoReportInitialSort.values,
        labelFor: (value) => value.label,
        onChanged: onChanged,
        decoration: const InputDecoration(
          labelText: '課題一覧の初期並び順',
          border: OutlineInputBorder(),
        ),
      );
}

class FeatureFlagsSection extends StatelessWidget {
  const FeatureFlagsSection({
    super.key,
    required this.settings,
    required this.onChanged,
    this.flags = GakujoFeatureFlag.values,
    this.title = '機能のオン/オフ',
  });

  final List<GakujoFeatureFlag> flags;
  final String? title;
  final GakujoAppSettings settings;
  final void Function(GakujoFeatureFlag flag, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        for (final flag in flags)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(flag.label),
            subtitle: switch (flag) {
              GakujoFeatureFlag.uploadCompression =>
                const Text('5MBを超えるファイルを提出前に圧縮します。オフでもプレビューできます。'),
              GakujoFeatureFlag.updateNotice =>
                const Text('1日1回 GitHub で新しい版を確認し、あれば画面の上部で知らせます。'),
              _ => null,
            },
            value: settings.isFeatureEnabled(flag),
            onChanged: (value) => onChanged(flag, value ?? true),
          ),
      ],
    );
  }
}

typedef NotificationPreferencesUpdate = GakujoNotificationPreferences Function(
  GakujoNotificationPreferences preferences,
);

typedef MessageNotificationUpdate = GakujoMessageNotificationSettings Function(
  GakujoMessageNotificationSettings messages,
);

class NotificationTopicsSection extends StatelessWidget {
  const NotificationTopicsSection({
    super.key,
    required this.topics,
    required this.messages,
    required this.notificationsEnabled,
    required this.onChanged,
    required this.onMessagesChanged,
    required this.keywordController,
    required this.canAddKeyword,
    required this.onKeywordInputChanged,
    required this.preferences,
    required this.onPreferencesChanged,
    this.remindersOnlyWhileOpen = false,
    this.notificationPermission,
    this.onOpenNotificationSettings,
  });

  final GakujoNotificationPreferences preferences;
  final Future<void> Function(NotificationPreferencesUpdate update)
      onPreferencesChanged;

  /// The OS cannot book reminders ahead here; they come from the open app.
  final bool remindersOnlyWhileOpen;
  final ValueListenable<bool?>? notificationPermission;
  final VoidCallback? onOpenNotificationSettings;

  final Set<GakujoNotificationTopic> topics;
  final GakujoMessageNotificationSettings messages;
  final bool notificationsEnabled;
  final void Function(GakujoNotificationTopic topic, bool enabled) onChanged;
  final Future<bool> Function(MessageNotificationUpdate update)
      onMessagesChanged;
  final TextEditingController keywordController;
  final bool canAddKeyword;
  final ValueChanged<String> onKeywordInputChanged;

  Future<void> _addKeyword() async {
    final keyword = keywordController.text;
    final saved = await onMessagesChanged(
      (current) => current.copyWith(
        keywords: normalizeMessageExcludeKeywords([
          ...current.keywords,
          keyword,
        ]),
      ),
    );
    if (!saved) return;
    keywordController.clear();
    onKeywordInputChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '端末に通知する内容',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          notificationsEnabled
              ? 'チェックした種類の期限だけをスマートフォンやパソコンの通知に出します。'
              : '「提出期限の通知」がオフのため、通知は出ません。',
        ),
        if (notificationsEnabled && notificationPermission != null)
          ValueListenableBuilder<bool?>(
            valueListenable: notificationPermission!,
            builder: (context, granted, _) => granted == false
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('端末の設定で通知が許可されていません'),
                      if (onOpenNotificationSettings != null)
                        TextButton(
                          onPressed: onOpenNotificationSettings,
                          child: const Text('端末の通知設定を開く'),
                        ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        for (final topic in GakujoNotificationTopic.values)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(topic.label),
            value: topics.contains(topic),
            onChanged: notificationsEnabled
                ? (value) => onChanged(topic, value ?? false)
                : null,
          ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('提出済みの課題は通知しない'),
          subtitle: const Text('レポート・小テスト一覧で「提出済」になっているものを除きます。'),
          value: preferences.skipSubmitted,
          onChanged: notificationsEnabled
              ? (value) => unawaited(
                    onPreferencesChanged(
                      (current) => current.copyWith(skipSubmitted: value),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          '締切前のリマインド',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          remindersOnlyWhileOpen
              ? '未提出の課題を締切の前にもう一度知らせます。WindowsとLinuxではアプリを開いている間に届きます。閉じている間に通知の時刻を過ぎたものは、次に開いたときに知らせます。'
              : '未提出の課題を締切の前にもう一度知らせます。アプリを閉じていても届きます。',
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final offset in GakujoReminderOffset.values)
              FilterChip(
                label: Text(offset.label),
                selected: preferences.reminderOffsets.contains(offset),
                onSelected: notificationsEnabled
                    ? (selected) => unawaited(
                          onPreferencesChanged(
                            (current) => current.copyWith(
                              reminderOffsets: {
                                for (final value in current.reminderOffsets)
                                  if (value != offset) value,
                                if (selected) offset,
                              },
                            ),
                          ),
                        )
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '連絡通知',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          '全学への案内が多いため、通知するものを絞れます。設定を切り替えた後に届いた連絡通知から通知します。',
        ),
        RadioGroup<GakujoMessageNotificationMode>(
          groupValue: messages.mode,
          onChanged: (mode) {
            if (notificationsEnabled && mode != null) {
              unawaited(onMessagesChanged(
                (current) => current.copyWith(mode: mode),
              ));
            }
          },
          child: Column(
            children: [
              for (final mode in GakujoMessageNotificationMode.values)
                RadioListTile<GakujoMessageNotificationMode>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(mode.label),
                  value: mode,
                  enabled: notificationsEnabled,
                ),
            ],
          ),
        ),
        if (messages.mode == GakujoMessageNotificationMode.keywords) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: keywordController,
                  enabled: notificationsEnabled,
                  decoration: const InputDecoration(
                    labelText: '通知するキーワード',
                    hintText: '例: 授業連絡、休講、締切',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: onKeywordInputChanged,
                  onSubmitted: canAddKeyword
                      ? (_) {
                          unawaited(_addKeyword());
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: notificationsEnabled && canAddKeyword
                    ? () => unawaited(_addKeyword())
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('追加'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            messages.keywords.isEmpty
                ? 'キーワードが未設定のため、連絡通知は通知されません。'
                : 'いずれかのキーワードを表題・ジャンル・差出人などに含む連絡通知を通知します。'
                    '「授業連絡」だけを登録すると、授業の連絡だけを通知します。',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in messages.keywords)
                InputChip(
                  label: Text(keyword),
                  onDeleted: notificationsEnabled
                      ? () => unawaited(
                            onMessagesChanged(
                              (current) => current.copyWith(
                                keywords: [
                                  for (final value in current.keywords)
                                    if (value != keyword) value,
                                ],
                              ),
                            ),
                          )
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class MessageExcludeKeywordsSection extends StatelessWidget {
  const MessageExcludeKeywordsSection({
    super.key,
    required this.keywords,
    required this.controller,
    required this.canAdd,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
    this.focusNode,
  });

  final List<String> keywords;
  final TextEditingController controller;
  final bool canAdd;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onAdd;
  final Future<void> Function(String keyword) onRemove;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '連絡通知の除外キーワード',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          '連絡通知の一覧で、除外キーワードを含む通知を非表示にします。'
          'キーワード通知を有効にしている場合は、通知用キーワードに一致する通知も一覧に表示します。',
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  labelText: 'キーワード',
                  hintText: '例: アンケート',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onChanged: onChanged,
                onSubmitted: canAdd
                    ? (_) {
                        unawaited(onAdd());
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: canAdd ? () => unawaited(onAdd()) : null,
              icon: const Icon(Icons.add),
              label: const Text('追加'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (keywords.isEmpty)
          const Text('除外キーワードは未設定です。')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in keywords)
                InputChip(
                  label: Text(keyword),
                  onDeleted: () => unawaited(onRemove(keyword)),
                ),
            ],
          ),
      ],
    );
  }
}

class DriveDownloadSwitch extends StatelessWidget {
  const DriveDownloadSwitch({
    super.key,
    required this.value,
    required this.signingIn,
    required this.enabled,
    required this.onChanged,
    this.subtitle,
    this.onCancel,
  });

  final bool value;
  final bool signingIn;
  final bool enabled;
  final String? subtitle;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: const Text('ダウンロードしたファイルを Google ドライブにも保存する'),
    subtitle: signingIn
        ? Row(
            children: [
              const Expanded(child: LinearProgressIndicator()),
              if (onCancel != null)
                TextButton(onPressed: onCancel, child: const Text('キャンセル')),
            ],
          )
        : subtitle == null
        ? null
        : Text(subtitle!),
    value: value,
    onChanged: signingIn || !enabled ? null : onChanged,
  );
}

class DriveSaveFolderTile extends StatelessWidget {
  const DriveSaveFolderTile({
    super.key,
    required this.name,
    required this.onChange,
  });

  final String? name;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: const Text('Google ドライブの保存先フォルダ'),
    subtitle: Text(name ?? '既定（マイドライブ / More Better Gakujo）'),
    onTap: onChange,
    trailing: const Icon(Icons.chevron_right),
  );
}
