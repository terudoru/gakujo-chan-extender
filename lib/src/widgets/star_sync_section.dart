import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../star_sync/star_sync_config.dart';
import '../star_sync/star_sync_crypto.dart';
import '../star_sync/star_sync_engine.dart';
import '../star_sync/star_sync_google_auth.dart';
import '../star_sync/star_sync_quota_meter.dart';
import '../star_sync/star_sync_s3_transport.dart';
import '../star_sync/star_sync_transport.dart';
import '../star_sync/star_sync_webdav_transport.dart';
import 'settings_sections.dart';

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
  if (error is StarSyncWrongPassphraseException) return 'パスフレーズが違います';
  if (error is ArgumentError) {
    return 'URLを確認してください（https のみ使えます）';
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
      StarSyncTransportErrorKind.tls => '証明書を確認できませんでした',
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

Future<bool?> _confirmReset(BuildContext context, String message) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同期データをリセット'),
        content: Text(message),
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

class StarSyncSection extends StatefulWidget {
  const StarSyncSection({
    super.key,
    required this.status,
    this.driveDownloadsEnabled = false,
    this.onDriveDownloadsChanged,
    this.onBackup,
    this.onListBackups,
    this.onRestoreBackup,
    this.collectionEnabled,
    this.onCollectionChanged,
    required this.googleAvailable,
    required this.isGoogleDrive,
    required this.googleEmail,
    required this.onGoogleSignIn,
    required this.onGoogleSignOut,
    required this.onGoogleReSignIn,
    this.onGoogleCancelSignIn,
    required this.onLocalStarCount,
    this.onLocalCollectionCounts,
    required this.onSnapshotLocalStars,
    required this.onRequireAccount,
    required this.onAccountGeneration,
    required this.onSetUpWithDrive,
    required this.onResetWithDrive,
    required this.onSetUp,
    required this.onSyncNow,
    required this.onResumeKeepingLocal,
    required this.onResumeDiscardingLocal,
    required this.onChangePassphrase,
    required this.onListDevices,
    required this.onDeleteDevice,
    required this.onDisable,
    required this.onReset,
    required this.onRejoin,
  });

  final ValueListenable<StarSyncStatusSnapshot> status;
  final bool driveDownloadsEnabled;
  final Future<void> Function(bool)? onDriveDownloadsChanged;
  final Future<void> Function()? onBackup;
  final Future<List<StarSyncBackupInfo>> Function()? onListBackups;
  final Future<void> Function(String)? onRestoreBackup;
  final bool Function(String)? collectionEnabled;
  final Future<void> Function(String, bool)? onCollectionChanged;
  final bool googleAvailable;
  final bool Function() isGoogleDrive;
  final String? Function() googleEmail;
  final Future<StarSyncDriveSetup> Function({
    required Map<String, String> clearLocalStars,
    required String expectedAccount,
    required int expectedGeneration,
  })
  onGoogleSignIn;
  final Future<void> Function() onGoogleSignOut;
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
  final Future<void> Function(
    StarSyncConfig,
    String, {
    required bool resetExisting,
    required Map<String, String> clearLocalStars,
    required String expectedAccount,
    required int expectedGeneration,
  })
  onSetUp;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onResumeKeepingLocal;
  final Future<void> Function() onResumeDiscardingLocal;
  final Future<void> Function(String, String) onChangePassphrase;
  final Future<List<StarSyncDeviceInfo>> Function() onListDevices;
  final Future<void> Function(String) onDeleteDevice;
  final Future<void> Function({required bool deleteOwnRemoteFile}) onDisable;
  final Future<void> Function(String) onReset;
  final Future<void> Function(String) onRejoin;

  @override
  State<StarSyncSection> createState() => _StarSyncSectionState();
}

class _StarSyncSectionState extends State<StarSyncSection> {
  final _rejoinPassphrase = TextEditingController();
  bool _busy = false;
  bool _googleSigningIn = false;
  String? _error;
  List<StarSyncBackupInfo>? _backups;

  @override
  void initState() {
    super.initState();
    widget.status.addListener(_clearRejoinWhenNotAsked);
  }

  @override
  void didUpdateWidget(StarSyncSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      oldWidget.status.removeListener(_clearRejoinWhenNotAsked);
      widget.status.addListener(_clearRejoinWhenNotAsked);
    }
  }

  /// Whatever path leaves the rejoin state (disable, reset, re-sign-in), a
  /// A typed passphrase must not wait there for the next person.
  void _clearRejoinWhenNotAsked() {
    final status = widget.status.value.status;
    if (status != StarSyncStatus.needsPassphrase) _rejoinPassphrase.clear();
  }

  @override
  void dispose() {
    widget.status.removeListener(_clearRejoinWhenNotAsked);
    _rejoinPassphrase.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
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
        TextButton(onPressed: widget.onGoogleCancelSignIn, child: const Text('キャンセル')),
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

  Future<void> _startAdvanced() async {
    try {
      final expectedAccount = widget.onRequireAccount();
      final expectedGeneration = widget.onAccountGeneration();
      final clear = await _chooseLocalStars();
      if (clear == null || !mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SetupDialog(
          onSetUp: widget.onSetUp,
          clearLocalStars: clear,
          expectedAccount: expectedAccount,
          expectedGeneration: expectedGeneration,
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Future<void> _startGoogle() async {
    // Ask before showing progress, or the bar keeps animating behind it.
    String expectedAccount;
    int expectedGeneration;
    try {
      expectedAccount = widget.onRequireAccount();
      expectedGeneration = widget.onAccountGeneration();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
      return;
    }
    Map<String, String>? choice;
    try {
      choice = await _chooseLocalStars();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
      return;
    }
    if (choice == null || !mounted) return;
    final clear = choice;
    setState(() {
      _busy = true;
      _googleSigningIn = true;
      _error = null;
    });
    var needsCleanup = false;
    try {
      final result = await widget.onGoogleSignIn(
        clearLocalStars: clear,
        expectedAccount: expectedAccount,
        expectedGeneration: expectedGeneration,
      );
      if (mounted) setState(() => _googleSigningIn = false);
      needsCleanup = result == StarSyncDriveSetup.needsLegacyReset;
      if (!mounted) return;
      if (result == StarSyncDriveSetup.needsLegacyReset) {
        // Ask before showing progress, or the bar keeps animating behind it.
        setState(() => _busy = false);
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
        if (confirmed != true) return;
        if (mounted) setState(() => _busy = true);
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
          await widget.onGoogleSignOut();
        } on Object catch (error) {
          if (mounted) setState(() => _error = _errorText(error));
        }
      }
      if (mounted) setState(() { _busy = false; _googleSigningIn = false; });
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('他の端末も自動的に新しい同期データに追従します')));
      }
    });
  }

  Widget _driveDownloadsSwitch() => SwitchListTile(
    title: const Text('ダウンロードしたファイルを Google ドライブにも保存する'),
    subtitle: widget.driveDownloadsEnabled && widget.googleEmail() != null
        ? Text(
            widget.isGoogleDrive()
                ? '保存先: ${widget.googleEmail()!}'
                : '保存先: ${widget.googleEmail()!}\n別のアカウントにするには、一度オフにします',
          )
        : null,
    value: widget.driveDownloadsEnabled,
    onChanged: _busy
        ? null
        : (value) => _run(() async {
            if (value) setState(() => _googleSigningIn = true);
            try {
              await widget.onDriveDownloadsChanged!(value);
            } finally {
              if (mounted && value) setState(() => _googleSigningIn = false);
            }
          }),
  );

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

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<StarSyncStatusSnapshot>(
    valueListenable: widget.status,
    builder: (context, status, _) {
      if (!status.enabled) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.googleAvailable &&
                widget.onDriveDownloadsChanged != null)
              _driveDownloadsSwitch(),
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
            const Text(
              '同期した内容は、この端末を使う他の人からも見えます。共用の端末では同期を設定しないでください。',
            ),
            if (_error != null) Text(_error!),
            if (_busy) _googleProgress(),
            if (status.lastError != null) Text(status.lastError!),
            ExpansionTile(
              title: const Text('詳細設定：自分のサーバーを使う（WebDAV / S3互換）'),
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _startAdvanced,
                  child: const Text('同期を設定'),
                ),
              ],
            ),
          ],
        );
      }
      if (status.status == StarSyncStatus.accountMismatch) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status.activeAccountUnknown
                ? '学務情報システムへのログイン状態を確認できないため、同期を停止しています。学務情報システムにログインすると再開します'
                : 'ログインIDが同期を設定したときと違うため、同期を停止しています。'),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          _DisableDialog(onDisable: widget.onDisable),
                    ),
              child: const Text('同期を無効にする'),
            ),
          ],
        );
      }
      if (status.status == StarSyncStatus.accountReturned) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ログインIDが一時的に変わっていました。その間にこの端末で付け外ししたスターを同期に含めますか？'),
            if (_error != null) Text(_error!),
            if (_busy) const LinearProgressIndicator(),
            FilledButton(
              onPressed: _busy ? null : () => _run(widget.onResumeKeepingLocal),
              child: const Text('含めて再開'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
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
                      if (confirmed == true && mounted) {
                        await _run(widget.onResumeDiscardingLocal);
                      }
                    },
              child: const Text('同期データの状態に戻して再開'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          _DisableDialog(onDisable: widget.onDisable),
                    ),
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
            if (widget.isGoogleDrive() && widget.googleEmail() == null)
              const Text(
                'この同期の設定には Google アカウントの情報がないため、再ログインできません。'
                '「同期を無効にする」を押してから、もう一度設定してください。端末内のスターは残ります。',
              ),
            if (_error != null) Text(_error!),
            if (_busy) _googleProgress(),
            if (!widget.isGoogleDrive() || widget.googleEmail() != null)
              OutlinedButton(
                onPressed: _busy ? null : _reSignInGoogle,
                child: const Text('Google に再ログイン'),
              ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          _DisableDialog(onDisable: widget.onDisable),
                    ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line),
          if (widget.isGoogleDrive()) ...[
            Text(
              '本日の利用量: ${status.googleQuotaUsed} / 15,000',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (status.googleQuotaSoftLimited)
              const Text('直近24時間の利用量が上限に達したため、自動同期を一時停止しています'),
          ],
          if (warning != null)
            Text(
              warning,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (cooldown != null && cooldown.isAfter(DateTime.now()))
            Text(
              '混雑のため、${cooldown.hour.toString().padLeft(2, '0')}:${cooldown.minute.toString().padLeft(2, '0')} まで同期を控えています',
            ),
          if (widget.isGoogleDrive() && widget.googleEmail() != null)
            Text('${widget.googleEmail()!}\n別のアカウントにするには、同期を無効にしてから設定し直します。'),
          if (status.status == StarSyncStatus.needsLegacyReset) ...[
            const Text('古い方式で保存されているか壊れているため、この端末からは読み込めません。同期データを作り直すと、古い同期データは消えます。この端末のスターは残ります。'),
            OutlinedButton(onPressed: _busy ? null : _resetDrive, child: const Text('作り直す')),
          ],
          if (status.status == StarSyncStatus.needsPassphrase) ...[
            const Text('別の端末で同期データがリセットされたか、鍵が変更されました。'),
            TextField(
              controller: _rejoinPassphrase,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'パスフレーズ'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final passphrase = _rejoinPassphrase.text;
                      _rejoinPassphrase.clear();
                      await widget.onRejoin(passphrase);
                    }),
              child: const Text('再接続'),
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
          if (widget.googleAvailable && widget.onDriveDownloadsChanged != null)
            _driveDownloadsSwitch(),
          if (widget.onBackup != null &&
              widget.onListBackups != null &&
              widget.onRestoreBackup != null) ...[
            const Text('バックアップ'),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(widget.onBackup!),
                  child: const Text('今すぐバックアップ'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final backups = await widget.onListBackups!();
                          if (mounted) setState(() => _backups = backups);
                        }),
                  child: const Text('バックアップから復元'),
                ),
              ],
            ),
            if (widget.isGoogleDrive())
              const Text(
                'バックアップは同期の鍵で暗号化されます。',
              ),
            if (_backups != null && _backups!.isEmpty)
              const Text('バックアップはありません'),
            for (final backup in _backups ?? <StarSyncBackupInfo>[])
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
          if (_error != null) Text(_error!),
          if (_busy) _googleProgress(),
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
              if (!widget.isGoogleDrive())
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => _PassphraseDialog(
                            title: 'パスフレーズを変更',
                            currentRequired: true,
                            action: (current, next) =>
                                widget.onChangePassphrase(current, next),
                          ),
                        ),
                  child: const Text('パスフレーズを変更'),
                ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _DevicesDialog(
                          onList: widget.onListDevices,
                          onDelete: widget.onDeleteDevice,
                        ),
                      ),
                child: const Text('端末の一覧'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        _rejoinPassphrase.clear();
                        unawaited(showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) =>
                              _DisableDialog(onDisable: widget.onDisable),
                        ));
                      },
                child: const Text('同期を無効にする'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : widget.isGoogleDrive()
                    ? _resetDrive
                    : () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _PassphraseDialog(
                          title: '同期データをリセット',
                          warning: '同期先のデータを削除して作り直します。他の端末はパスフレーズの再入力が必要になります。端末内のスターは残ります。',
                          action: (_, next) => widget.onReset(next),
                        ),
                      ),
                child: const Text('同期データをリセット'),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _SetupDialog extends StatefulWidget {
  const _SetupDialog({
    required this.onSetUp,
    required this.clearLocalStars,
    required this.expectedAccount,
    required this.expectedGeneration,
  });
  final Map<String, String> clearLocalStars;
  final String expectedAccount;
  final int expectedGeneration;
  final Future<void> Function(
    StarSyncConfig,
    String, {
    required bool resetExisting,
    required Map<String, String> clearLocalStars,
    required String expectedAccount,
    required int expectedGeneration,
  })
  onSetUp;
  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends State<_SetupDialog> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _region = TextEditingController();
  final _bucket = TextEditingController();
  final _prefix = TextEditingController();
  final _access = TextEditingController();
  final _secret = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  StarSyncBackend _backend = StarSyncBackend.webDav;
  bool _pathStyle = true;
  bool _wrongPassphrase = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _url,
      _user,
      _password,
      _region,
      _bucket,
      _prefix,
      _access,
      _secret,
      _pass,
      _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit({bool resetExisting = false}) async {
    final validation = _validatePassphrase(_pass.text, _confirm.text);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Uri uri;
      try {
        uri = Uri.parse(_url.text.trim());
      } on FormatException {
        throw ArgumentError('Invalid URL');
      }
      validateStarSyncEndpoint(uri);
      final config = _backend == StarSyncBackend.webDav
          ? StarSyncConfig(
              backend: _backend,
              webDav: StarSyncWebDavConfig(
                baseUrl: uri,
                username: _user.text,
                password: _password.text,
              ),
            )
          : StarSyncConfig(
              backend: _backend,
              s3: StarSyncS3Config(
                endpoint: uri,
                region: _region.text.trim(),
                bucket: _bucket.text.trim(),
                prefix: _prefix.text.trim(),
                accessKeyId: _access.text,
                secretAccessKey: _secret.text,
                pathStyle: _pathStyle,
              ),
            );
      await widget.onSetUp(
        config,
        _pass.text,
        resetExisting: resetExisting,
        clearLocalStars: widget.clearLocalStars,
        expectedAccount: widget.expectedAccount,
        expectedGeneration: widget.expectedGeneration,
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = _errorText(error);
          _wrongPassphrase = error is StarSyncWrongPassphraseException;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await _confirmReset(
      context,
      '同期データをリセットすると、他の端末ではパスフレーズを入力し直す必要があります。この端末のスターはそのまま残ります。',
    );
    if (confirmed == true && mounted) await _submit(resetExisting: true);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    String? helper,
  }) => TextField(
    controller: controller,
    enabled: !_busy,
    obscureText: obscure,
    decoration: InputDecoration(labelText: label, helperText: helper),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('同期を設定'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IgnorePointer(
              ignoring: _busy,
              child: SettingsRadioGroup<StarSyncBackend>(
                groupValue: _backend,
                values: const [StarSyncBackend.webDav, StarSyncBackend.s3],
                labelFor: (value) =>
                    value == StarSyncBackend.webDav ? 'WebDAV' : 'S3互換',
                onChanged: (value) {
                  if (value != null) setState(() => _backend = value);
                },
                decoration: const InputDecoration(labelText: '接続方式'),
              ),
            ),
            _field(
              _url,
              _backend == StarSyncBackend.webDav ? 'URL' : 'エンドポイント',
            ),
            if (_backend == StarSyncBackend.webDav) ...[
              _field(_user, 'ユーザー名'),
              _field(_password, 'パスワード', obscure: true),
            ] else ...[
              _field(_region, 'リージョン', helper: 'Cloudflare R2 は auto'),
              _field(_bucket, 'バケット'),
              _field(_prefix, 'プレフィックス（任意）'),
              _field(_access, 'アクセスキーID'),
              _field(_secret, 'シークレットアクセスキー', obscure: true),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('パス形式のURLを使う'),
                value: _pathStyle,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _pathStyle = value ?? true),
              ),
            ],
            _field(_pass, 'パスフレーズ', obscure: true),
            _field(_confirm, 'パスフレーズ（確認）', obscure: true),
            const SizedBox(height: 12),
            const Text('パスフレーズを忘れると同期データは復元できません。端末内のスターは残ります。'),
            if (_wrongPassphrase)
              TextButton(
                onPressed: _busy ? null : _reset,
                child: const Text('パスフレーズを忘れた場合：同期データをリセットして新しく始める'),
              ),
            if (_error != null) Text(_error!),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(onPressed: _busy ? null : _submit, child: const Text('接続')),
    ],
  );
}

String? _validatePassphrase(String pass, String confirmation) {
  if (pass.length < 10) return 'パスフレーズは10文字以上で入力してください';
  if (pass != confirmation) return 'パスフレーズが一致しません';
  return null;
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({
    required this.title,
    required this.action,
    this.currentRequired = false,
    this.warning,
  });
  final String title;
  final bool currentRequired;
  final String? warning;
  final Future<void> Function(String, String) action;
  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validation = _validatePassphrase(_next.text, _confirm.text);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.action(_current.text, _next.text);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.warning != null) Text(widget.warning!),
            if (widget.currentRequired)
              TextField(
                controller: _current,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: '現在のパスフレーズ'),
              ),
            TextField(
              controller: _next,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新しいパスフレーズ'),
            ),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新しいパスフレーズ（確認）'),
            ),
            if (_error != null) Text(_error!),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(widget.title),
      ),
    ],
  );
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
