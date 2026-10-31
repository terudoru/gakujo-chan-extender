import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../star_sync/star_sync_config.dart';
import '../star_sync/star_sync_crypto.dart';
import '../star_sync/star_sync_engine.dart';
import '../star_sync/star_sync_s3_transport.dart';
import '../star_sync/star_sync_transport.dart';
import '../star_sync/star_sync_webdav_transport.dart';
import 'settings_sections.dart';

String _errorText(Object error) {
  if (error is StarSyncWrongPassphraseException) return 'パスフレーズが違います';
  if (error is ArgumentError) {
    return 'URLを確認してください（https のみ使えます）';
  }
  if (error is StarSyncTransportException) {
    return switch (error.kind) {
      StarSyncTransportErrorKind.auth => '認証に失敗しました',
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

class StarSyncSection extends StatefulWidget {
  const StarSyncSection({
    super.key,
    required this.status,
    required this.onSetUp,
    required this.onSyncNow,
    required this.onChangePassphrase,
    required this.onListDevices,
    required this.onDeleteDevice,
    required this.onDisable,
    required this.onReset,
    required this.onRejoin,
  });

  final ValueListenable<StarSyncStatusSnapshot> status;
  final Future<void> Function(StarSyncConfig, String) onSetUp;
  final Future<void> Function() onSyncNow;
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
  final _rejoin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _rejoin.dispose();
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
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<StarSyncStatusSnapshot>(
        valueListenable: widget.status,
        builder: (context, status, _) {
          if (!status.enabled) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'スター（IDと件名のみ）を、自分で用意したWebDAVまたはS3互換ストレージを通して端末間で共有します。内容はパスフレーズで暗号化され、保存先からは読めません。',
                ),
                if (status.lastError != null) Text(status.lastError!),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _SetupDialog(onSetUp: widget.onSetUp),
                  ),
                  child: const Text('同期を設定'),
                ),
              ],
            );
          }
          final line = status.syncing
              ? '同期中…'
              : status.lastError ??
                    (status.lastSyncAt == null
                        ? 'まだ同期していません'
                        : '最終同期: ${_date(status.lastSyncAt!)}');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line),
              if (status.status == StarSyncStatus.needsPassphrase) ...[
                const Text('別の端末で同期データがリセットされたか、鍵が変更されました。'),
                TextField(
                  controller: _rejoin,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'パスフレーズ'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.onRejoin(_rejoin.text)),
                  child: const Text('再接続'),
                ),
              ],
              if (_error != null) Text(_error!),
              if (_busy) const LinearProgressIndicator(),
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
                        : () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) =>
                                _DisableDialog(onDisable: widget.onDisable),
                          ),
                    child: const Text('同期を無効にする'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
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
  const _SetupDialog({required this.onSetUp});
  final Future<void> Function(StarSyncConfig, String) onSetUp;
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

  Future<void> _submit() async {
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
      await widget.onSetUp(config, _pass.text);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                values: StarSyncBackend.values,
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
