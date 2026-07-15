import 'dart:async';

import 'package:flutter/material.dart';

import '../gakujo_app_settings.dart';

class TwoFactorSecretSection extends StatelessWidget {
  const TwoFactorSecretSection({
    super.key,
    required this.canSave,
    required this.onChanged,
    required this.onClear,
    required this.onSave,
  });

  final bool canSave;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onClear;
  final Future<void> Function() onSave;

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
          'QRコード横の長いBase32文字列を保存します。6桁コードではありません。保存済みの秘密鍵は表示しません。\n取得方法: https://github.com/koji-genba/gakujo-chan-extender#2段階認証自動入力',
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: '長いBase32 2FA秘密鍵',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: canSave ? () => unawaited(onSave()) : null,
              icon: const Icon(Icons.key),
              label: const Text('秘密鍵を保存'),
            ),
            TextButton.icon(
              onPressed: () => unawaited(onClear()),
              icon: const Icon(Icons.delete_outline),
              label: const Text('秘密鍵を削除'),
            ),
          ],
        ),
      ],
    );
  }
}

class LoginCredentialsSection extends StatelessWidget {
  const LoginCredentialsSection({
    super.key,
    required this.isConfigured,
    required this.canSave,
    required this.onLoginIdChanged,
    required this.onPasswordChanged,
    required this.onClear,
    required this.onSave,
  });

  final bool isConfigured;
  final bool canSave;
  final ValueChanged<String> onLoginIdChanged;
  final ValueChanged<String> onPasswordChanged;
  final Future<void> Function() onClear;
  final Future<void> Function() onSave;

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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: canSave ? () => unawaited(onSave()) : null,
                icon: const Icon(Icons.login),
                label: const Text('ログイン情報を保存'),
              ),
              TextButton.icon(
                onPressed: isConfigured ? () => unawaited(onClear()) : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('ログイン情報を削除'),
              ),
            ],
          ),
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
          'ダウンロード設定',
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
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: '保存先フォルダ',
            border: OutlineInputBorder(),
          ),
          child: Text(rootLabel),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 8),
          Text(
            helperText!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
            TextButton.icon(
              onPressed: isConfigured ? onClear : null,
              icon: const Icon(Icons.link_off),
              label: const Text('解除'),
            ),
          ],
        ),
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
  });

  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      initiallyExpanded: initiallyExpanded,
      maintainState: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
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

class FeatureFlagsSection extends StatelessWidget {
  const FeatureFlagsSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final GakujoAppSettings settings;
  final void Function(GakujoFeatureFlag flag, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '機能のオン/オフ',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final flag in GakujoFeatureFlag.values)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(flag.label),
            value: settings.isFeatureEnabled(flag),
            onChanged: (value) => onChanged(flag, value ?? true),
          ),
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
  });

  final List<String> keywords;
  final TextEditingController controller;
  final bool canAdd;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onAdd;
  final Future<void> Function(String keyword) onRemove;

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
          '連絡通知タブの通知一覧で、タイトルや行の文字に含まれるキーワードを非表示にします。',
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
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
