import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../gakujo_app_settings.dart';
import '../report_form.dart';
import 'report_dialog.dart';
import 'settings_sections.dart';

class SettingsAction {
  const SettingsAction({
    required this.label,
    required this.icon,
    required this._run,
    this.description,
  }) : choices = const [];

  const SettingsAction.chooser({
    required this.label,
    required this.icon,
    required this.choices,
  }) : _run = null,
       description = null;

  final String label;
  final IconData icon;
  final Future<void> Function()? _run;
  final String? description;
  final List<SettingsAction> choices;

  Future<void> run() => _run!();
}

Future<SettingsAction?> chooseSettingsAction(
  BuildContext context, {
  required String title,
  required List<SettingsAction> actions,
}) async {
  final owner = ModalRoute.of(context);
  final choice = await showDialog<SettingsAction>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final action in actions)
          ListTile(
            leading: Icon(action.icon),
            title: Text(action.label),
            subtitle: action.description == null
                ? null
                : Text(action.description!),
            onTap: () => Navigator.of(context).pop(action),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
        ),
      ],
    ),
  );
  return context.mounted && owner?.isCurrent != false ? choice : null;
}

class SettingsActionGroup extends StatefulWidget {
  const SettingsActionGroup({
    super.key,
    required this.actions,
    this.chooser,
    this.chooserIconOnly = false,
    this.enabled = true,
  }) : assert(!chooserIconOnly || chooser != null);
  final List<SettingsAction> actions;
  final bool enabled;
  final ({String label, IconData icon})? chooser;
  final bool chooserIconOnly;
  @override
  State<SettingsActionGroup> createState() => _SettingsActionGroupState();
}

class _SettingsActionGroupState extends State<SettingsActionGroup> {
  String? _activeDataAction;
  bool _choosing = false;

  Future<void> _choose(String label, List<SettingsAction> actions) async {
    if (!widget.enabled || _choosing || _activeDataAction != null) return;
    _choosing = true;
    try {
      final action = await chooseSettingsAction(
        context,
        title: label,
        actions: actions,
      );
      if (mounted && widget.enabled && action != null) {
        await _runDataAction(action.label, action.run);
      }
    } finally {
      _choosing = false;
    }
  }

  VoidCallback? _dataAction(SettingsAction action) {
    if (!widget.enabled || _activeDataAction != null) return null;
    return () {
      if (_choosing) return;
      if (action.choices.isNotEmpty) {
        unawaited(_choose(action.label, action.choices));
      } else {
        unawaited(_runDataAction(action.label, action.run));
      }
    };
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
  Widget build(BuildContext context) {
    final chooser = widget.chooser;
    final onChoose =
        chooser != null && widget.enabled && _activeDataAction == null
        ? () => unawaited(_choose(chooser.label, widget.actions))
        : null;
    if (widget.chooserIconOnly && chooser != null) {
      return IconButton(
        tooltip: chooser.label,
        onPressed: onChoose,
        icon: _activeDataAction == null
            ? Icon(chooser.icon)
            : SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: '「$_activeDataAction」を処理しています',
                ),
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (chooser != null)
              OutlinedButton.icon(
                onPressed: onChoose,
                icon: Icon(chooser.icon),
                label: Text(chooser.label),
              )
            else
              for (final action in widget.actions)
                OutlinedButton.icon(
                  onPressed: _dataAction(action),
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
}

class AppBackupSection extends StatelessWidget {
  const AppBackupSection({
    super.key,
    this.onCreateBackup,
    this.onImportSettingsFromFile,
    this.onCreateDriveBackup,
    this.onListDriveBackups,
    this.enabled = true,
  });
  final Future<void> Function()? onCreateBackup,
      onImportSettingsFromFile,
      onCreateDriveBackup,
      onListDriveBackups;
  final bool enabled;

  SettingsAction _backupAction(
    String label,
    IconData icon,
    List<SettingsAction> choices,
  ) => choices.length == 1
      ? SettingsAction(label: label, icon: icon, run: choices.single.run)
      : SettingsAction.chooser(label: label, icon: icon, choices: choices);

  @override
  Widget build(BuildContext context) {
    final create = [
      if (onCreateBackup case final run?)
        SettingsAction(
          label: 'ファイルに保存',
          icon: Icons.save_alt,
          run: run,
          description: 'この端末の設定やダウンロード履歴などをJSONに保存します。',
        ),
      if (onCreateDriveBackup case final run?)
        SettingsAction(
          label: 'Google ドライブに保存',
          icon: Icons.cloud_upload_outlined,
          run: run,
          description: '同期対象のデータを暗号化し、この端末のバックアップを更新します。',
        ),
    ];
    final restore = [
      if (onImportSettingsFromFile case final run?)
        SettingsAction(
          label: 'ファイルから読み込み',
          icon: Icons.file_open_outlined,
          run: run,
          description: '端末の設定やダウンロード履歴などを復元します。',
        ),
      if (onListDriveBackups case final run?)
        SettingsAction(
          label: 'Google ドライブから復元',
          icon: Icons.cloud_download_outlined,
          run: run,
          description: '同期対象のデータを復元します。端末固有の設定やダウンロード履歴は保持します。',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('バックアップ', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        const Text('バックアップにログイン情報と2FA秘密鍵は含まれません。'),
        const SizedBox(height: 8),
        SettingsActionGroup(
          enabled: enabled,
          actions: [
            if (create.isNotEmpty)
              _backupAction('バックアップを作成', Icons.backup_outlined, create),
            if (restore.isNotEmpty)
              _backupAction('バックアップから復元', Icons.file_open_outlined, restore),
          ],
        ),
      ],
    );
  }
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

class AppSupportButton extends StatelessWidget {
  const AppSupportButton({
    super.key,
    required this.onCreateErrorReport,
    required this.onOpenUrl,
    this.reportEndpoint,
    this.collectDiagnostics,
    this.reportClient,
    this.loadVersion,
  });
  final Future<void> Function() onCreateErrorReport;
  final Future<void> Function(Uri) onOpenUrl;
  final Uri? reportEndpoint;
  final Future<String> Function()? collectDiagnostics;
  final ReportClient? reportClient;
  final Future<String> Function()? loadVersion;
  @override
  Widget build(BuildContext context) => SettingsActionGroup(
    chooser: (label: '不具合・要望を報告', icon: Icons.bug_report_outlined),
    chooserIconOnly: true,
    actions: [
      if (reportEndpoint case final endpoint?)
        SettingsAction(
          label: 'アプリから報告する',
          icon: Icons.feedback_outlined,
          description: 'GitHub アカウントを使わずに送信します。',
          run: () async {
            unawaited(
              showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ReportDialog(
                  client: reportClient ?? ReportClient(endpoint: endpoint),
                  collectDiagnostics:
                      collectDiagnostics ??
                      () async => throw StateError('Diagnostics unavailable'),
                  onOpenUrl: onOpenUrl,
                  loadVersion: loadVersion,
                ),
              ),
            );
          },
        ),
      SettingsAction(
        label: 'エラー報告パッケージ作成',
        icon: Icons.inventory_2_outlined,
        description: '報告用ファイルを端末に作成します。',
        run: onCreateErrorReport,
      ),
      SettingsAction(
        label: 'GitHub で報告（アカウントが必要）',
        icon: Icons.open_in_new,
        description: 'GitHub の投稿はすぐに公開されます。氏名・学籍番号・ログイン情報・学情の画面内容は書かないでください。',
        run: () => onOpenUrl(
          Uri.parse(
            'https://github.com/terudoru/gakujo-chan-extender/issues/new',
          ),
        ),
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
    required this.onShowFavorites,
    required this.onShowDataManagement,
  });

  final Future<void> Function() onShowDownloadHistory;
  final Future<void> Function() onShowFailedDownloads;
  final Future<void> Function() onShowCourseMaterials;
  final Future<void> Function() onShowCachedReports;
  final Future<void> Function() onShowDrafts;
  final Future<void> Function() onShowFavorites;
  final Future<void> Function() onShowDataManagement;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final choice = await chooseSettingsAction(
                  context,
                  title: 'ダウンロード記録',
                  actions: [
                    SettingsAction(
                      label: 'ダウンロード履歴',
                      icon: Icons.history,
                      run: onShowDownloadHistory,
                    ),
                    SettingsAction(
                      label: '失敗したダウンロード',
                      icon: Icons.error_outline,
                      run: onShowFailedDownloads,
                    ),
                    SettingsAction(
                      label: '授業ごとの資料',
                      icon: Icons.folder_copy_outlined,
                      run: onShowCourseMaterials,
                    ),
                  ],
                );
                await choice?.run();
              },
              icon: const Icon(Icons.history),
              label: const Text('ダウンロード記録'),
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
