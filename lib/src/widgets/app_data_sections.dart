import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../gakujo_app_settings.dart';
import 'settings_sections.dart';

class SettingsAction {
  const SettingsAction({
    required this.label,
    required this.icon,
    required this.run,
    this.quiet = false,
  });
  final String label;
  final IconData icon;
  final Future<void> Function() run;
  final bool quiet;
}

class SettingsActionGroup extends StatefulWidget {
  const SettingsActionGroup({super.key, required this.actions});
  final List<SettingsAction> actions;
  @override
  State<SettingsActionGroup> createState() => _SettingsActionGroupState();
}

class _SettingsActionGroupState extends State<SettingsActionGroup> {
  String? _activeDataAction;

  VoidCallback? _dataAction(String label, Future<void> Function() action) {
    if (_activeDataAction != null) return null;
    return () => unawaited(_runDataAction(label, action));
  }

  Future<void> _runDataAction(
    String label,
    Future<void> Function() action,
  ) async {
    if (_activeDataAction != null) return;
    setState(() => _activeDataAction = label);
    try {
      await action();
    } on Object catch (error, stackTrace) {
      developer.log(
        'Maintenance action failed: $label',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「$label」を完了できませんでした。もう一度お試しください')),
        );
      }
    } finally {
      if (mounted) setState(() => _activeDataAction = null);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in widget.actions)
            if (action.quiet)
              TextButton.icon(
                onPressed: _dataAction(action.label, action.run),
                icon: Icon(action.icon),
                label: Text(action.label),
              )
            else
              OutlinedButton.icon(
                onPressed: _dataAction(action.label, action.run),
                icon: Icon(action.icon),
                label: Text(action.label),
              ),
        ],
      ),
      if (_activeDataAction != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('「$_activeDataAction」を処理しています...')),
            ],
          ),
        ),
    ],
  );
}

class AppBackupSection extends StatelessWidget {
  const AppBackupSection({
    super.key,
    required this.onCreateBackup,
    required this.onExportSettings,
    required this.onImportSettings,
    required this.onImportSettingsFromFile,
  });
  final Future<void> Function() onCreateBackup,
      onExportSettings,
      onImportSettings,
      onImportSettingsFromFile;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('バックアップと設定の移行', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      const Text('設定、履歴、お気に入り、保存済み課題一覧をコピーします。ログイン情報と2FA秘密鍵は含めません。'),
      const SizedBox(height: 8),
      SettingsActionGroup(
        actions: [
          SettingsAction(
            label: 'バックアップ作成',
            icon: Icons.backup_outlined,
            run: onCreateBackup,
          ),
          SettingsAction(
            label: '設定をコピー',
            icon: Icons.upload_file,
            run: onExportSettings,
          ),
          SettingsAction(
            label: 'クリップボードから読み込み',
            icon: Icons.download,
            run: onImportSettings,
          ),
          SettingsAction(
            label: 'ファイルから読み込み',
            icon: Icons.file_open_outlined,
            run: onImportSettingsFromFile,
          ),
        ],
      ),
    ],
  );
}

class AppUpdateSection extends StatefulWidget {
  const AppUpdateSection({
    super.key,
    required this.settings,
    required this.onFlagChanged,
    required this.onCheckUpdates,
  });
  final GakujoAppSettings settings;
  final void Function(GakujoFeatureFlag, bool) onFlagChanged;
  final Future<void> Function() onCheckUpdates;
  @override
  State<AppUpdateSection> createState() => _AppUpdateSectionState();
}

class _AppUpdateSectionState extends State<AppUpdateSection> {
  bool _isCheckingForUpdates = false;
  Future<void> _checkForUpdates() async {
    if (_isCheckingForUpdates) {
      return;
    }
    setState(() {
      _isCheckingForUpdates = true;
    });
    try {
      await widget.onCheckUpdates();
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('アップデート', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _isCheckingForUpdates
              ? null
              : () => unawaited(_checkForUpdates()),
          icon: _isCheckingForUpdates
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt),
          label: Text(_isCheckingForUpdates ? '確認中...' : 'アップデートを確認'),
        ),
      ),
      FeatureFlagsSection(
        settings: widget.settings,
        onChanged: widget.onFlagChanged,
        title: null,
        flags: settingsAppFeatureFlags,
      ),
    ],
  );
}

class AppSupportSection extends StatelessWidget {
  const AppSupportSection({
    super.key,
    required this.onCreateErrorReport,
    required this.onCopyDiagnostics,
  });
  final Future<void> Function() onCreateErrorReport, onCopyDiagnostics;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('不具合の報告', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      SettingsActionGroup(
        actions: [
          SettingsAction(
            label: 'エラー報告パッケージ作成',
            icon: Icons.inventory_2_outlined,
            run: onCreateErrorReport,
          ),
          SettingsAction(
            label: '診断情報をコピー',
            icon: Icons.bug_report_outlined,
            run: onCopyDiagnostics,
            quiet: true,
          ),
        ],
      ),
    ],
  );
}

class AppDataShortcutsSection extends StatelessWidget {
  const AppDataShortcutsSection({
    super.key,
    required this.onShowDownloadHistory,
    required this.onShowFailedDownloads,
    required this.onShowCourseMaterials,
    required this.onShowCachedReports,
    required this.onShowDrafts,
    required this.onShowChangeHistory,
    required this.onShowFavorites,
    required this.onShowDataManagement,
  });

  final Future<void> Function() onShowDownloadHistory;
  final Future<void> Function() onShowFailedDownloads;
  final Future<void> Function() onShowCourseMaterials;
  final Future<void> Function() onShowCachedReports;
  final Future<void> Function() onShowDrafts;
  final Future<void> Function() onShowChangeHistory;
  final Future<void> Function() onShowFavorites;
  final Future<void> Function() onShowDataManagement;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'データと履歴',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text('保存したデータ、履歴、課題一覧を確認します。'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowDownloadHistory()),
              icon: const Icon(Icons.history),
              label: const Text('ダウンロード履歴'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowFailedDownloads()),
              icon: const Icon(Icons.error_outline),
              label: const Text('失敗したダウンロード'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowCourseMaterials()),
              icon: const Icon(Icons.folder_copy_outlined),
              label: const Text('授業ごとの資料'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowCachedReports()),
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('保存済み課題一覧'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowDrafts()),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('下書き'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowChangeHistory()),
              icon: const Icon(Icons.manage_history),
              label: const Text('変更履歴'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowFavorites()),
              icon: const Icon(Icons.star_border),
              label: const Text('お気に入り'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowDataManagement()),
              icon: const Icon(Icons.storage_outlined),
              label: const Text('データ管理'),
            ),
          ],
        ),
      ],
    );
  }
}

class AppIntegrationSection extends StatelessWidget {
  const AppIntegrationSection({
    super.key,
    required this.onScheduleIntegration,
  });

  final Future<void> Function() onScheduleIntegration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'カレンダー',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text('学務情報システムの授業予定をカレンダーに追加します。'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => unawaited(onScheduleIntegration()),
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('スケジュール連携'),
          ),
        ),
      ],
    );
  }
}
