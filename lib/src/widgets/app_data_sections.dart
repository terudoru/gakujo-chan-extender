import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

class AppMaintenanceSection extends StatefulWidget {
  const AppMaintenanceSection({
    super.key,
    required this.onCheckUpdates,
    required this.onCreateBackup,
    required this.onCreateErrorReport,
    required this.onExportSettings,
    required this.onImportSettings,
    required this.onImportSettingsFromFile,
    required this.onCheckDownloadDestination,
    required this.onCopyDiagnostics,
  });

  final Future<void> Function() onCheckUpdates;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onCreateErrorReport;
  final Future<void> Function() onExportSettings;
  final Future<void> Function() onImportSettings;
  final Future<void> Function() onImportSettingsFromFile;
  final Future<void> Function() onCheckDownloadDestination;
  final Future<void> Function() onCopyDiagnostics;

  @override
  State<AppMaintenanceSection> createState() => _AppMaintenanceSectionState();
}

class _AppMaintenanceSectionState extends State<AppMaintenanceSection> {
  bool _isCheckingForUpdates = false;
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
      developer.log('Maintenance action failed: $label',
          name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('「$label」を完了できませんでした。もう一度お試しください'),
        ));
      }
    } finally {
      if (mounted) setState(() => _activeDataAction = null);
    }
  }

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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'バックアップと診断',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          '設定、履歴、お気に入り、課題キャッシュをコピーします。ログイン情報と2FA秘密鍵は含めません。',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _isCheckingForUpdates
                  ? null
                  : () => unawaited(_checkForUpdates()),
              icon: _isCheckingForUpdates
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt),
              label: Text(
                _isCheckingForUpdates ? '確認中...' : 'アップデートを確認',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _dataAction('バックアップ作成', widget.onCreateBackup),
              icon: const Icon(Icons.backup_outlined),
              label: const Text('バックアップ作成'),
            ),
            OutlinedButton.icon(
              onPressed: _dataAction('設定をコピー', widget.onExportSettings),
              icon: const Icon(Icons.upload_file),
              label: const Text('設定をコピー'),
            ),
            OutlinedButton.icon(
              onPressed: _dataAction('設定を読み込み', widget.onImportSettings),
              icon: const Icon(Icons.download),
              label: const Text('設定を読み込み'),
            ),
            OutlinedButton.icon(
              onPressed:
                  _dataAction('ファイルから読み込み', widget.onImportSettingsFromFile),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('ファイルから読み込み'),
            ),
            OutlinedButton.icon(
              onPressed:
                  _dataAction('保存先を確認', widget.onCheckDownloadDestination),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('保存先を確認'),
            ),
            OutlinedButton.icon(
              onPressed:
                  _dataAction('エラー報告パッケージ作成', widget.onCreateErrorReport),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('エラー報告パッケージ作成'),
            ),
            TextButton.icon(
              onPressed: _dataAction('診断情報をコピー', widget.onCopyDiagnostics),
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('診断情報をコピー'),
            ),
          ],
        ),
        if (_activeDataAction != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('「$_activeDataAction」を処理しています...')),
            ]),
          ),
      ],
    );
  }
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
        const Text('保存済みデータ、履歴、一覧キャッシュを確認します。'),
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
          '外部連携',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text('Gakujoの情報を外部アプリと連携します。'),
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
