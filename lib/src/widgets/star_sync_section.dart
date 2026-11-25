import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../star_sync/star_sync_config.dart';
import '../star_sync/star_sync_crypto.dart';
import '../star_sync/star_sync_engine.dart';
import '../star_sync/star_sync_google_auth.dart';
import '../star_sync/star_sync_quota_meter.dart';
import '../star_sync/star_sync_transport.dart';
import 'app_data_sections.dart';

String _units(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

String starSyncErrorMessage(Object error) => _errorText(error);

String _errorText(Object error) {
  if (error is StarSyncQuotaExceeded) return starSyncGoogleQuotaMessage;
  if (error is StarSyncActiveAccountRequiredException) {
    return '学務情報システムにログインしてから設定してください';
  }
  if (error is StarSyncAccountRequiredException) {
    return '同期を使うには、設定の「ログイン」でログインIDを保存してください。';
  }
  if (error is StarSyncKeyringMismatchException) return '同期データの鍵が一致しません';
  if (error is FormatException || error is StarSyncFormatException) {
    return '同期データの形式が正しくありません';
  }
  if (error is StarSyncGoogleAuthException) {
    return switch (error.kind) {
      StarSyncGoogleAuthErrorKind.revoked => 'Google のログインが切れました。もう一度ログインしてください',
      StarSyncGoogleAuthErrorKind.permissionDenied => 'Google ドライブへのアクセスが許可されませんでした。同意画面でチェックを入れて、もう一度お試しください',
      StarSyncGoogleAuthErrorKind.browserUnavailable => 'ブラウザを開けませんでした。既定のブラウザの設定を確認してください',
      StarSyncGoogleAuthErrorKind.storageUnavailable => defaultTargetPlatform == TargetPlatform.linux
          ? 'ログイン情報を安全に保管するサービス（GNOME Keyring や KWallet など）を使えないため、Google にログインできません。保管サービスを有効にしてから、もう一度お試しください'
          : 'この端末の安全な保存領域を使えないため、Google にログインできません',
      StarSyncGoogleAuthErrorKind.network => '接続できませんでした',
      StarSyncGoogleAuthErrorKind.notSignedIn => 'Google にログインしてください',
      StarSyncGoogleAuthErrorKind.failed || StarSyncGoogleAuthErrorKind.cancelled => 'Google へのログインに失敗しました',
    };
  }
  if (error is StarSyncTransportException) {
    return switch (error.kind) {
      StarSyncTransportErrorKind.auth => '認証に失敗しました',
      StarSyncTransportErrorKind.storageFull => 'Google ドライブの空き容量が足りません',
      StarSyncTransportErrorKind.driveDisabled => '組織の管理者が Google ドライブの利用を制限しています。別の Google アカウントをお試しください',
      StarSyncTransportErrorKind.server => 'サーバーエラー (HTTP ${error.statusCode})',
      _ => '接続できませんでした',
    };
  }
  return '接続できませんでした';
}

String _date(DateTime date) {
  final d = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

class StarSyncSection extends StatefulWidget {
  const StarSyncSection({
    super.key,
    required this.status,
    this.onBusyChanged,
    this.onCreateFileBackup,
    this.onImportBackupFile,
    this.onBackup,
    this.onListBackups,
    this.onRestoreBackup,
    this.collectionEnabled,
    this.onCollectionChanged,
    required this.googleAvailable,
    required this.googleEmail,
    required this.onGoogleSignIn,
    required this.onGoogleSignOut,
    this.onGoogleSetupAbandoned,
    required this.onGoogleReSignIn,
    this.onGoogleCancelSignIn,
    required this.onLocalStarCount,
    this.onLocalCollectionCounts,
    required this.onSnapshotLocalStars,
    required this.onRequireAccount,
    required this.onAccountGeneration,
    required this.onSetUpWithDrive,
    required this.onResetWithDrive,
    required this.onSyncNow,
    required this.onResumeKeepingLocal,
    required this.onResumeDiscardingLocal,
    required this.onListDevices,
    required this.onDeleteDevice,
    required this.onDisable,
  });

  final ValueListenable<StarSyncStatusSnapshot> status;
  /// The Drive switch elsewhere on the screen must wait while this section
  /// signs in or sets up, or turning it off could sign out mid-setup.
  final ValueChanged<bool>? onBusyChanged;
  final Future<void> Function()? onCreateFileBackup;
  final Future<void> Function()? onImportBackupFile;
  final Future<void> Function()? onBackup;
  final Future<List<StarSyncBackupInfo>> Function()? onListBackups;
  final Future<void> Function(String)? onRestoreBackup;
  final bool Function(String)? collectionEnabled;
  final Future<void> Function(String, bool)? onCollectionChanged;
  final bool googleAvailable;
  final String? Function() googleEmail;
  /// Invoke onSignedIn before Drive setup starts, when cancellation must stop.
  final Future<StarSyncDriveSetup> Function({
    required Map<String, String> clearLocalStars,
    required String expectedAccount,
    required int expectedGeneration,
    required VoidCallback onSignedIn,
  })
  onGoogleSignIn;
  final Future<void> Function() onGoogleSignOut;
  /// Cleanup for incomplete setup, which may preserve an existing Drive session.
  final Future<void> Function()? onGoogleSetupAbandoned;
  final Future<void> Function() onGoogleReSignIn;
  final VoidCallback? onGoogleCancelSignIn;
  final Future<int> Function() onLocalStarCount;
  final Future<Map<String, int?>> Function()? onLocalCollectionCounts;
  final Future<Map<String, String>> Function() onSnapshotLocalStars;
  final String Function() onRequireAccount;
  final int Function() onAccountGeneration;
  final Future<StarSyncDriveSetup> Function({
    required bool resetExisting,
    required Map<String, String> clearLocalStars,
    required String expectedAccount,
    required int expectedGeneration,
  })
  onSetUpWithDrive;
  final Future<void> Function() onResetWithDrive;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onResumeKeepingLocal;
  final Future<void> Function() onResumeDiscardingLocal;
  final Future<List<StarSyncDeviceInfo>> Function() onListDevices;
  final Future<void> Function(String) onDeleteDevice;
  final Future<void> Function({required bool deleteOwnRemoteFile}) onDisable;

  @override
  State<StarSyncSection> createState() => _StarSyncSectionState();
}

class _StarSyncSectionState extends State<StarSyncSection> {
  bool _busyValue = false;
  bool get _busy => _busyValue;
  set _busy(bool value) {
    if (value != _busyValue) widget.onBusyChanged?.call(value);
    _busyValue = value;
  }

  bool _choosingAction = false;
  bool _googleSigningIn = false;
  bool _choosingGoogleSetup = false;
  String? _error;
  List<StarSyncBackupInfo>? _backups;

  @override
  void dispose() {
    if (_busyValue) {
      // The tree is locked here; tell the screen once this frame is done.
      final onBusyChanged = widget.onBusyChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onBusyChanged?.call(false);
      });
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (error is! StarSyncGoogleAuthException ||
          error.kind != StarSyncGoogleAuthErrorKind.cancelled) {
        if (mounted) setState(() => _error = _errorText(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reSignInGoogle() => _run(() async {
    setState(() => _googleSigningIn = true);
    try {
      await widget.onGoogleReSignIn();
    } finally {
      if (mounted) setState(() => _googleSigningIn = false);
    }
  });

  Widget _googleProgress() => Row(
    children: [
      const Expanded(child: LinearProgressIndicator()),
      if (_googleSigningIn && widget.onGoogleCancelSignIn != null &&
          {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}
              .contains(defaultTargetPlatform))
        TextButton(
          onPressed: () {
            // A tap can arrive before the sign-in completion is painted.
            if (_googleSigningIn) widget.onGoogleCancelSignIn?.call();
          },
          child: const Text('キャンセル'),
        ),
    ],
  );

  Future<Map<String, String>?> _chooseLocalStars() async {
    final count = await widget.onLocalStarCount();
    final counts = await widget.onLocalCollectionCounts?.call();
    if (!mounted) return null;
    String collectionCount(String name) => counts?[name]?.toString() ?? '未確認';
    Future<Map<String, String>>? snapshot;
    final clear = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('この端末のスター（$count件）'),
        content: Text(
          'この端末に残っているお気に入り（${collectionCount('favorites')}件）、'
          '設定（${collectionCount('settings')}項目）、'
          '下書き（${collectionCount('report-drafts')}件）、'
          '通知済みの締切（${collectionCount('notified-deadlines')}件）も含まれます。'
          '他の人が使っていた端末や、別の Google アカウントで同期したあとで内容を混ぜたくないときは、「空にして始める」を選んでください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              snapshot = widget.onSnapshotLocalStars();
              Navigator.pop(context, true);
            },
            child: const Text('空にして始める'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('含めて同期する'),
          ),
        ],
      ),
    );
    if (clear == null) return null;
    return clear ? await snapshot! : {};
  }

  Future<void> _startGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _choosingGoogleSetup = true;
      _error = null;
    });
    var needsCleanup = false;
    try {
      final expectedAccount = widget.onRequireAccount();
      final expectedGeneration = widget.onAccountGeneration();
      // Ask before showing progress, or the bar keeps animating behind it.
      final clear = await _chooseLocalStars();
      if (clear == null || !mounted) return;
      setState(() {
        _choosingGoogleSetup = false;
        _googleSigningIn = true;
      });
      final result = await widget.onGoogleSignIn(
        clearLocalStars: clear,
        expectedAccount: expectedAccount,
        expectedGeneration: expectedGeneration,
        onSignedIn: () {
          if (mounted) setState(() => _googleSigningIn = false);
        },
      );
      if (mounted) setState(() => _googleSigningIn = false);
      needsCleanup = result == StarSyncDriveSetup.needsLegacyReset;
      if (!mounted) return;
      if (result == StarSyncDriveSetup.needsLegacyReset) {
        setState(() => _choosingGoogleSetup = true);
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('以前の同期データが見つかりました'),
            content: const Text('古い方式で保存されているか壊れているため、この端末からは読み込めません。同期データを作り直すと、古い同期データは消えます。この端末のスターは残ります。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('作り直す')),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        setState(() => _choosingGoogleSetup = false);
        await widget.onSetUpWithDrive(
          resetExisting: true, clearLocalStars: clear,
          expectedAccount: expectedAccount, expectedGeneration: expectedGeneration,
        );
      }
      needsCleanup = false;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('同期を開始しました')));
      }
    } on StarSyncGoogleAuthException catch (error) {
      if (error.kind != StarSyncGoogleAuthErrorKind.cancelled && mounted) {
        setState(() => _error = _errorText(error));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (needsCleanup && !widget.status.value.enabled) {
        try {
          await (widget.onGoogleSetupAbandoned ?? widget.onGoogleSignOut)();
        } on Object catch (error) {
          if (mounted) setState(() => _error = _errorText(error));
        }
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _googleSigningIn = false;
          _choosingGoogleSetup = false;
        });
      }
    }
  }

  Future<void> _resetDrive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同期データをリセット'),
        content: const Text(
          '同期先のデータを削除して作り直します。他の端末は自動的に追従します。端末内のスターは残ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('リセット'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.onResetWithDrive();
      if (mounted) {
        setState(() => _backups = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('他の端末も自動的に新しい同期データに追従します')));
      }
    });
  }

  Future<void> _restoreBackup(StarSyncBackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('バックアップから復元しますか？'),
        content: const Text('バックアップの内容で上書き・追加します。バックアップ後に他の端末で追加したものは残ります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('復元する'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => widget.onRestoreBackup!(backup.deviceId));
    }
  }

  Future<void> _choose(String title, List<SettingsAction> actions) async {
    if (_choosingAction || _busy) return;
    _choosingAction = true;
    try {
      final choice = await chooseSettingsAction(
        context,
        title: title,
        actions: actions,
      );
      if (mounted && !_busy) await choice?.run();
    } finally {
      _choosingAction = false;
    }
  }

  Future<void> _showDisable() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DisableDialog(onDisable: widget.onDisable),
  );

  Future<void> _showDevices() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DevicesDialog(
      onList: widget.onListDevices,
      onDelete: widget.onDeleteDevice,
    ),
  );

  Future<void> _resumeDiscardingChanges() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('この端末で、その間に付け外ししたスターは元に戻ります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('戻して再開'),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        mounted &&
        widget.status.value.status == StarSyncStatus.accountReturned) {
      await _run(widget.onResumeDiscardingLocal);
    }
  }

  Future<void> _chooseResume() => _choose('同期を再開', [
    SettingsAction(
      label: '含めて再開',
      icon: Icons.sync,
      description: '同期を停止していた間のこの端末の変更も同期します。',
      run: () async {
        if (widget.status.value.status != StarSyncStatus.accountReturned) {
          return;
        }
        await _run(widget.onResumeKeepingLocal);
      },
    ),
    SettingsAction(
      label: '同期データの状態に戻して再開',
      icon: Icons.restore,
      description: '同期を停止していた間のこの端末の変更を取り消します。',
      run: _resumeDiscardingChanges,
    ),
  ]);

  Future<void> _chooseManagement() => _choose('同期の管理', [
    SettingsAction(
      label: '端末の一覧',
      icon: Icons.devices_outlined,
      run: _showDevices,
    ),
    SettingsAction(
      label: '同期を無効にする',
      icon: Icons.sync_disabled,
      description: 'この端末での同期を停止します。',
      run: _showDisable,
    ),
    if (widget.status.value.status != StarSyncStatus.needsLegacyReset)
      SettingsAction(
        label: '同期データをリセット',
        icon: Icons.restart_alt,
        description: 'Google ドライブの同期データを削除して作り直します。',
        run: _resetDrive,
      ),
  ]);

  bool _canUseDriveBackup(StarSyncStatusSnapshot status) =>
      status.enabled &&
      status.status != StarSyncStatus.accountMismatch &&
      status.status != StarSyncStatus.accountReturned &&
      status.status != StarSyncStatus.needsGoogleSignIn &&
      widget.onBackup != null &&
      widget.onListBackups != null &&
      widget.onRestoreBackup != null;

  Future<void> _createDriveBackup() async {
    if (!_canUseDriveBackup(widget.status.value)) return;
    await _run(widget.onBackup!);
  }

  Future<void> _listDriveBackups() async {
    if (!_canUseDriveBackup(widget.status.value)) return;
    await _run(() async {
      final backups = await widget.onListBackups!();
      if (mounted) setState(() => _backups = backups);
    });
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<StarSyncStatusSnapshot>(
        valueListenable: widget.status,
        builder: (context, status, _) {
          final drive = _canUseDriveBackup(status);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSync(context, status),
              if (widget.onCreateFileBackup != null || drive) ...[
                const Divider(height: 32),
                AppBackupSection(
                  onCreateBackup: widget.onCreateFileBackup,
                  onImportSettingsFromFile: widget.onImportBackupFile,
                  onCreateDriveBackup: drive ? _createDriveBackup : null,
                  onListDriveBackups: drive ? _listDriveBackups : null,
                  enabled: !_busy,
                ),
              ],
              if (drive)
                if (_backups case final backups?) ...[
                  if (backups.isEmpty) const Text('バックアップはありません'),
                  for (final backup in backups)
                    ListTile(
                      title: Text(backup.isThisDevice ? 'この端末' : '他の端末'),
                      subtitle: Text(
                        backup.lastModified == null
                            ? '日時不明'
                            : _date(backup.lastModified!),
                      ),
                      onTap: _busy ? null : () => _restoreBackup(backup),
                    ),
                ],
            ],
          );
        },
      );

  Widget _buildSync(BuildContext context, StarSyncStatusSnapshot status) {
    if (!status.enabled) {
      if (!widget.googleAvailable) {
        return const Text('このビルドでは Google ドライブ同期を使えません。');
      }
      return Column(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.googleAvailable) ...[
            const Text(
              'スター（IDと件名のみ）を、あなたの Google ドライブのアプリ専用領域に暗号化して保存し、端末間で共有します。',
            ),
            const Text(
              '同期データは暗号化しますが、鍵も同じ Google アカウントのアプリ専用領域に保存します。同じアカウントでログインするだけで、他の端末と同期できます。',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _startGoogle,
              child: const Text('Google ドライブで同期'),
            ),
          ],
          // Local data is per device, not per Gakujo account.
          const Text('同期した内容は、この端末を使う他の人からも見えます。共用の端末では同期を設定しないでください。'),
          if (_error != null) Text(_error!),
          if (_busy && !_choosingGoogleSetup) _googleProgress(),
          if (status.lastError != null) Text(status.lastError!),
        ],
      );
    }
    if (status.status == StarSyncStatus.accountMismatch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status.activeAccountUnknown
                ? '学務情報システムへのログイン状態を確認できないため、同期を停止しています。学務情報システムにログインすると再開します'
                : 'ログインIDが同期を設定したときと違うため、同期を停止しています。',
          ),
          OutlinedButton(
            onPressed: _busy ? null : _showDisable,
            child: const Text('同期を無効にする'),
          ),
        ],
      );
    }
    if (status.status == StarSyncStatus.accountReturned) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('同期が止まっていた間に、この端末でスターや設定などが変わった可能性があります。その変更を同期に含めますか？'),
          if (_error != null) Text(_error!),
          if (_busy) const LinearProgressIndicator(),
          FilledButton(
            onPressed: _busy ? null : _chooseResume,
            child: const Text('同期を再開'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _showDisable,
            child: const Text('同期を無効にする'),
          ),
        ],
      );
    }
    if (status.status == StarSyncStatus.needsGoogleSignIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Google へのログインが切れました。'),
          if (widget.googleEmail() != null)
            Text('同期に使うアカウント: ${widget.googleEmail()!}'),
          // Settings from before accounts were recorded can never match one.
          if (widget.googleEmail() == null)
            const Text(
              'この同期の設定には Google アカウントの情報がないため、再ログインできません。'
              '「同期を無効にする」を押してから、もう一度設定してください。端末内のスターは残ります。',
            ),
          if (_error != null) Text(_error!),
          if (_busy) _googleProgress(),
          if (widget.googleEmail() != null)
            OutlinedButton(
              onPressed: _busy ? null : _reSignInGoogle,
              child: const Text('Google に再ログイン'),
            ),
          OutlinedButton(
            onPressed: _busy ? null : _showDisable,
            child: const Text('同期を無効にする'),
          ),
        ],
      );
    }
    final warning = status.status == StarSyncStatus.ok
        ? status.lastError
        : null;
    final line = status.syncing
        ? '同期中…'
        : (warning == null ? status.lastError : null) ??
              (status.lastSyncAt == null
                  ? 'まだ同期していません'
                  : '最終同期: ${_date(status.lastSyncAt!)}');
    final cooldown = status.cooldownUntil?.toLocal();
    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line),
        Text(
          '直近24時間の利用量: ${_units(status.googleQuotaUsed)} / '
          '${_units(starSyncGoogleSoftLimit)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (status.googleQuotaSoftLimited)
          const Text('直近24時間の利用量が上限に達したため、自動同期を一時停止しています'),
        if (warning != null)
          Text(
            warning,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (cooldown != null && cooldown.isAfter(DateTime.now()))
          Text(
            '混雑のため、${cooldown.hour.toString().padLeft(2, '0')}:${cooldown.minute.toString().padLeft(2, '0')} まで同期を控えています',
          ),
        if (widget.googleEmail() != null)
          Text('${widget.googleEmail()!}\n別のアカウントにするには、同期を無効にしてから設定し直します。'),
        if (status.status == StarSyncStatus.needsLegacyReset) ...[
          const Text(
            '古い方式で保存されているか壊れているため、この端末からは読み込めません。同期データを作り直すと、古い同期データは消えます。この端末のスターは残ります。',
          ),
          OutlinedButton(
            onPressed: _busy ? null : _resetDrive,
            child: const Text('作り直す'),
          ),
        ],
        if (widget.collectionEnabled != null &&
            widget.onCollectionChanged != null) ...[
          const Text('同期する項目'),
          for (final item in const {
            'favorites': 'お気に入り',
            'settings': '設定',
            'report-drafts': 'レポート下書き',
            'notified-deadlines': '通知済みの締切',
          }.entries)
            SwitchListTile(
              key: ValueKey(item.key),
              title: Text(item.value),
              value: widget.collectionEnabled!(item.key),
              onChanged: _busy || status.syncing
                  ? null
                  : (value) => _run(() async {
                      await widget.onCollectionChanged!(item.key, value);
                    }),
            ),
        ],
        if (_error != null) Text(_error!),
        if (_busy && !_choosingGoogleSetup) _googleProgress(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy || status.syncing
                  ? null
                  : () => _run(widget.onSyncNow),
              child: const Text('今すぐ同期'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _chooseManagement,
              child: const Text('同期の管理'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DisableDialog extends StatefulWidget {
  const _DisableDialog({required this.onDisable});
  final Future<void> Function({required bool deleteOwnRemoteFile}) onDisable;
  @override
  State<_DisableDialog> createState() => _DisableDialogState();
}

class _DisableDialogState extends State<_DisableDialog> {
  bool _delete = false;
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDisable(deleteOwnRemoteFile: _delete);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('同期を無効にする'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('この端末のスターは残ります。同期を無効にしますか？'),
        const Text('同期を無効にしている間に外したスターは、再び有効にしたときに他の端末から戻ることがあります。'),
        CheckboxListTile(
          value: _delete,
          onChanged: _busy
              ? null
              : (value) => setState(() => _delete = value ?? false),
          title: const Text('この端末の同期ファイルも削除する'),
        ),
        if (_error != null) Text(_error!),
        if (_busy) const LinearProgressIndicator(),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: const Text('無効にする'),
      ),
    ],
  );
}

class _DevicesDialog extends StatefulWidget {
  const _DevicesDialog({required this.onList, required this.onDelete});
  final Future<List<StarSyncDeviceInfo>> Function() onList;
  final Future<void> Function(String) onDelete;
  @override
  State<_DevicesDialog> createState() => _DevicesDialogState();
}

class _DevicesDialogState extends State<_DevicesDialog> {
  List<StarSyncDeviceInfo> _devices = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await widget.onList();
      if (mounted) setState(() => _devices = devices);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(StarSyncDeviceInfo device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('端末の同期ファイルを削除'),
        content: Text('${device.deviceId} の同期ファイルを削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDelete(device.deviceId);
      if (mounted) await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = _errorText(error);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('端末の一覧'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (!_busy && _error == null && _devices.isEmpty)
              const Text('端末はありません'),
            for (final device in _devices)
              ListTile(
                title: Text(
                  device.isThisDevice
                      ? '${device.deviceId}（この端末）'
                      : device.deviceId,
                ),
                subtitle: Text(
                  device.lastModified == null
                      ? '更新日時: 不明'
                      : '更新日時: ${_date(device.lastModified!)}',
                ),
                trailing: device.isThisDevice
                    ? null
                    : IconButton(
                        tooltip: '削除',
                        onPressed: _busy ? null : () => _delete(device),
                        icon: const Icon(Icons.delete_outline),
                      ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (_error != null)
        TextButton(onPressed: _busy ? null : _load, child: const Text('再読み込み')),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('閉じる'),
      ),
    ],
  );
}
