import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../star_sync/star_sync_config.dart';
import '../star_sync/star_sync_crypto.dart';
import '../star_sync/star_sync_engine.dart';
import '../star_sync/star_sync_google_auth.dart';
import '../star_sync/star_sync_s3_transport.dart';
import '../star_sync/star_sync_transport.dart';
import '../star_sync/star_sync_webdav_transport.dart';
import 'settings_sections.dart';

String _errorText(Object error) {
  if (error is StarSyncAccountRequiredException) {
    return '同期を使うには、設定の『ログイン』でログインIDを保存してください。';
  }
  if (error is StarSyncPairingMismatchException) return 'コードが一致しません';
  if (error is FormatException || error is StarSyncFormatException) {
    return 'コードの形式が正しくありません';
  }
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

class StarSyncClipboardGuard {
  StarSyncClipboardGuard({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? _readClipboard,
       _write = write ?? _writeClipboard;

  static final instance = StarSyncClipboardGuard();
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  Timer? _timer;
  int _generation = 0;

  static Future<String?> _readClipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  static Future<void> _writeClipboard(String value) =>
      Clipboard.setData(ClipboardData(text: value));

  Future<void> copy(String code) async {
    final generation = ++_generation;
    _timer?.cancel();
    await _write(code);
    if (generation != _generation) return;
    _timer = Timer(const Duration(seconds: 60), () async {
      final contents = await _read();
      if (generation == _generation && contents == code) await _write('');
    });
  }
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
    required this.googleAvailable,
    required this.isGoogleDrive,
    required this.googleEmail,
    required this.onGoogleSignIn,
    required this.onGoogleSignOut,
    required this.onGoogleReSignIn,
    required this.onLocalStarCount,
    required this.onSetUpWithPairing,
    required this.onJoinWithCode,
    required this.onPairingCode,
    required this.onRejoinWithCode,
    required this.onResetWithPairing,
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
  final bool googleAvailable;
  final bool Function() isGoogleDrive;
  final String? Function() googleEmail;
  final Future<StarSyncPairingSetup> Function({required bool clearLocalStars})
  onGoogleSignIn;
  final Future<void> Function() onGoogleSignOut;
  final Future<void> Function() onGoogleReSignIn;
  final Future<int> Function() onLocalStarCount;
  final Future<StarSyncPairingSetup> Function({
    required bool resetExisting,
    required bool clearLocalStars,
  })
  onSetUpWithPairing;
  final Future<void> Function(String, {required bool clearLocalStars})
  onJoinWithCode;
  final Future<String> Function() onPairingCode;
  final Future<void> Function(String) onRejoinWithCode;
  final Future<String> Function() onResetWithPairing;
  final Future<void> Function(
    StarSyncConfig,
    String, {
    required bool resetExisting,
    required bool clearLocalStars,
  })
  onSetUp;
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

  Future<bool?> _chooseLocalStars() async {
    final count = await widget.onLocalStarCount();
    if (!mounted) return null;
    if (count == 0) return false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('この端末のスター（$count件）'),
        content: const Text(
          'この端末に残っているスターも同期されます。他の人が使っていた端末なら『空にして始める』を選んでください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('空にして始める'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('含めて同期する'),
          ),
        ],
      ),
    );
  }

  Future<void> _startAdvanced() async {
    try {
      final clear = await _chooseLocalStars();
      if (clear == null || !mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _SetupDialog(onSetUp: widget.onSetUp, clearLocalStars: clear),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Future<void> _startGoogle() async {
    // Ask before showing progress, or the bar keeps animating behind it.
    final clear = await _chooseLocalStars();
    if (clear == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var needsCleanup = false;
    try {
      final result = await widget.onGoogleSignIn(clearLocalStars: clear);
      needsCleanup = result == StarSyncPairingSetup.needsPairingCode;
      if (!mounted) return;
      if (result == StarSyncPairingSetup.needsPairingCode) {
        // The dialog has its own progress state while it joins.
        setState(() => _busy = false);
        final joined = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PairingJoinDialog(
            onJoin: (code) =>
                widget.onJoinWithCode(code, clearLocalStars: clear),
            onReset: () => widget.onSetUpWithPairing(
              resetExisting: true,
              clearLocalStars: clear,
            ),
          ),
        );
        if (joined != true) return;
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCode([String? code]) async {
    try {
      final value = code ?? await widget.onPairingCode();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _PairingCodeDialog(
          code: value,
          onCopy: StarSyncClipboardGuard.instance.copy,
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Future<void> _resetPairing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同期データをリセット'),
        content: const Text(
          '同期先のデータを削除して作り直します。他の端末では新しいコードが必要です。端末内のスターは残ります。',
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
      final code = await widget.onResetWithPairing();
      await _showCode(code);
    });
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
            if (widget.googleAvailable) ...[
              const Text(
                'スター（IDと件名のみ）を、あなたの Google ドライブのアプリ専用領域に暗号化して保存し、端末間で共有します。',
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _startGoogle,
                child: const Text('Google ドライブで同期'),
              ),
            ],
            if (_error != null) Text(_error!),
            if (_busy) const LinearProgressIndicator(),
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
            const Text('ログインIDが同期を設定したときと違うため、同期を停止しています。'),
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
            if (widget.googleEmail() != null) Text(widget.googleEmail()!),
            if (_error != null) Text(_error!),
            if (_busy) const LinearProgressIndicator(),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(widget.onGoogleReSignIn),
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
      final line = status.syncing
          ? '同期中…'
          : status.lastError ??
                (status.lastSyncAt == null
                    ? 'まだ同期していません'
                    : '最終同期: ${_date(status.lastSyncAt!)}');
      final cooldown = status.cooldownUntil?.toLocal();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line),
          if (cooldown != null && cooldown.isAfter(DateTime.now()))
            Text(
              '混雑のため、${cooldown.hour.toString().padLeft(2, '0')}:${cooldown.minute.toString().padLeft(2, '0')} まで同期を控えています',
            ),
          if (widget.isGoogleDrive() && widget.googleEmail() != null)
            Text(widget.googleEmail()!),
          if (status.status == StarSyncStatus.needsPairingCode) ...[
            const Text('別の端末で同期データがリセットされました。新しいコードを入力してください。'),
            _PairingInput(controller: _rejoin, enabled: !_busy),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => widget.onRejoinWithCode(_rejoin.text)),
              child: const Text('再接続'),
            ),
          ],
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
              if (widget.isGoogleDrive())
                OutlinedButton(
                  onPressed: _busy ? null : () => _showCode(),
                  child: const Text('別の端末を追加'),
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
                    : widget.isGoogleDrive()
                    ? _resetPairing
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

class _PairingInput extends StatelessWidget {
  const _PairingInput({required this.controller, required this.enabled});
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: const InputDecoration(labelText: '同期コード'),
      ),
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS))
        TextButton(
          onPressed: !enabled
              ? null
              : () async {
                  final value = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const _PairingScanner()),
                  );
                  if (value != null) controller.text = value;
                },
          child: const Text('QRコードを読み取る'),
        ),
    ],
  );
}

class _PairingScanner extends StatefulWidget {
  const _PairingScanner();
  @override
  State<_PairingScanner> createState() => _PairingScannerState();
}

class _PairingScannerState extends State<_PairingScanner> {
  bool _found = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QRコードを読み取る')),
    body: MobileScanner(
      onDetect: (capture) {
        if (_found) return;
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null && value.startsWith('mbgstar:')) {
            _found = true;
            Navigator.pop(context, value);
            break;
          }
        }
      },
    ),
  );
}

class _PairingJoinDialog extends StatefulWidget {
  const _PairingJoinDialog({required this.onJoin, required this.onReset});
  final Future<void> Function(String) onJoin;
  final Future<StarSyncPairingSetup> Function() onReset;
  @override
  State<_PairingJoinDialog> createState() => _PairingJoinDialogState();
}

class _PairingJoinDialogState extends State<_PairingJoinDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      decodeStarSyncPairingCode(_code.text);
      await widget.onJoin(_code.text);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await _confirmReset(
      context,
      '同期データをリセットすると、他の端末ではコードの入力し直しが必要になります。この端末のスターはそのまま残ります。',
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onReset();
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('同期コードを入力'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'この Google アカウントには、すでに別の端末の同期データがあります。その端末の「別の端末を追加」に表示されるコードを入力してください。',
          ),
          _PairingInput(controller: _code, enabled: !_busy),
          TextButton(
            onPressed: _busy ? null : _reset,
            child: const Text('コードがない場合：同期データをリセットして新しく始める'),
          ),
          if (_error != null) Text(_error!),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('キャンセル'),
      ),
      FilledButton(onPressed: _busy ? null : _submit, child: const Text('接続')),
    ],
  );
}

class _PairingCodeDialog extends StatefulWidget {
  const _PairingCodeDialog({required this.code, required this.onCopy});
  final String code;
  final Future<void> Function(String) onCopy;

  @override
  State<_PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<_PairingCodeDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('別の端末を追加'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: 'mbgstar:${widget.code}', size: 220),
            SelectableText(
              widget.code,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            TextButton.icon(
              onPressed: () async {
                await widget.onCopy(widget.code);
                if (mounted) setState(() => _copied = true);
              },
              icon: const Icon(Icons.copy),
              label: const Text('コピー'),
            ),
            if (_copied) const Text('コピーしました。60秒後にクリップボードから消去します。'),
            const Text('このコードを知っている人は同期データを読めます。共有しないでください。'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('閉じる'),
      ),
    ],
  );
}

class _SetupDialog extends StatefulWidget {
  const _SetupDialog({required this.onSetUp, required this.clearLocalStars});
  final bool clearLocalStars;
  final Future<void> Function(
    StarSyncConfig,
    String, {
    required bool resetExisting,
    required bool clearLocalStars,
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
      '同期データをリセットすると、他の端末ではパスフレーズの入力し直しが必要になります。この端末のスターはそのまま残ります。',
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
