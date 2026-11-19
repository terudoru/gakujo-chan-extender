import 'dart:async';

import 'package:flutter/material.dart';

import '../google_drive_file_saver.dart';
import '../star_sync/star_sync_google_auth.dart';
import '../star_sync/star_sync_quota_meter.dart';
import '../star_sync/star_sync_transport.dart';
import 'star_sync_section.dart';

typedef DriveFolderCommit = Future<void> Function(
  Future<void> Function() write,
);

class DriveSaveFolderDialog extends StatefulWidget {
  const DriveSaveFolderDialog({
    super.key,
    required this.load,
    required this.pick,
    required this.create,
    required this.save,
    required this.currentId,
  });

  final Future<List<GoogleDriveFolder>> Function() load;
  final Future<GoogleDriveFolder?> Function() pick;
  final Future<GoogleDriveFolder> Function(String) create;
  final Future<void> Function(String?, DriveFolderCommit) save;
  final String? currentId;

  @override
  State<DriveSaveFolderDialog> createState() => _DriveSaveFolderDialogState();
}

enum _Action { load, pick, create, save }

class _FolderCommitGuard extends PopEntry<void> {
  @override
  final canPopNotifier = const AlwaysStoppedAnimation<bool>(false);
}

class _DriveSaveFolderDialogState extends State<DriveSaveFolderDialog> {
  final _name = TextEditingController();
  List<GoogleDriveFolder> _folders = [];
  String? _selectedId;
  _Action? _action;
  bool _committing = false;
  String? _loadError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentId;
    unawaited(_run(_Action.load));
  }

  Future<void> _run(_Action action) async {
    if (_action != null) return;
    setState(() {
      _action = action;
      _error = null;
      if (action == _Action.load) _loadError = null;
    });
    try {
      switch (action) {
        case _Action.load:
          final folders = await widget.load();
          if (!mounted) return;
          // A just-picked folder may not have appeared in files.list yet.
          final byId = {
            for (final f in [..._folders, ...folders]) f.id: f,
          };
          _folders = byId.values.toList()
            ..sort((a, b) => a.path.compareTo(b.path));
        case _Action.pick:
        case _Action.create:
          final folder = action == _Action.pick
              ? await widget.pick()
              : await widget.create(_name.text);
          if (!mounted || folder == null) return;
          _folders = [..._folders.where((f) => f.id != folder.id), folder]
            ..sort((a, b) => a.path.compareTo(b.path));
          _selectedId = folder.id;
          if (action == _Action.create) _name.clear();
        case _Action.save:
          await widget.save(_selectedId, _commit);
          if (mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.pop(context);
          }
      }
    } catch (error) {
      if (!mounted) return;
      final message = _message(error, action);
      if (action == _Action.load) {
        _loadError = message;
      } else {
        _error = message;
      }
    } finally {
      if (mounted) setState(() => _action = null);
    }
  }

  Future<void> _commit(Future<void> Function() write) async {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    // The save can leave the queue between frames. Guard Back synchronously
    // when the storage write starts, including before the button rebuilds.
    final guard = _FolderCommitGuard();
    route.registerPopEntry(guard);
    setState(() => _committing = true);
    try {
      await write();
    } finally {
      route.unregisterPopEntry(guard);
      if (mounted) setState(() => _committing = false);
    }
  }

  String _message(Object error, _Action action) => switch (error) {
    GoogleDriveSaveFolderShared() => 'ご自身が所有し、誰とも共有していないフォルダを選んでください',
    GoogleDriveSaveFolderMissing() =>
      'この Google アカウントでフォルダを確認できません。保存先を選び直してください',
    GoogleDriveDisabled() => '組織の管理者が Google ドライブの利用を制限しています',
    GoogleDriveStorageFull() => 'Google ドライブの空き容量が足りません',
    StarSyncGoogleAuthException(
      kind: StarSyncGoogleAuthErrorKind.notSignedIn,
    ) =>
      'ログイン状態が変わりました。保存先の設定を開き直してください',
    StarSyncTransportException(kind: StarSyncTransportErrorKind.auth) =>
      'Google ドライブへのアクセスが許可されていません。保存先のアカウントで選び直してください',
    StarSyncGoogleAuthException(kind: != StarSyncGoogleAuthErrorKind.failed) ||
    StarSyncTransportException() ||
    StarSyncQuotaExceeded() => starSyncErrorMessage(error),
    _ => switch (action) {
      _Action.load => 'フォルダの一覧を読み込めませんでした',
      _Action.pick => 'Google ドライブでフォルダを選べませんでした。もう一度お試しください',
      _Action.create => 'フォルダを作成できませんでした',
      _Action.save => '保存先を変更できませんでした',
    },
  };

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idle = _action == null;
    final selected = _folders.where((f) => f.id == _selectedId).firstOrNull;
    final knownSelection = _selectedId == null || selected != null;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('保存先フォルダ'),
          if (selected != null)
            Text(
              '選択中: ${selected.path}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (_error != null)
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: RadioGroup<String>(
            groupValue: _selectedId ?? '',
            onChanged: (value) {
              if (_action != null) return;
              setState(() {
                _selectedId = value == null || value.isEmpty ? null : value;
                _error = null;
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '保存先の中に科目ごとのフォルダを作ります。'
                  'ご自身が所有し、誰とも共有していないフォルダを選んでください。',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: idle ? () => _run(_Action.pick) : null,
                    child: const Text('Google ドライブから選ぶ'),
                  ),
                ),
                if (!idle) const LinearProgressIndicator(),
                RadioListTile<String>(
                  title: const Text('既定（More Better Gakujo）'),
                  enabled: idle,
                  value: '',
                ),
                if (_loadError != null) ...[
                  Text(_loadError!),
                  TextButton(
                    onPressed: idle ? () => _run(_Action.load) : null,
                    child: const Text('一覧を再読み込み'),
                  ),
                ] else if (idle && !knownSelection)
                  const Text('前回選んだフォルダを確認できません。保存先を選び直してください'),
                for (final folder in _folders)
                  RadioListTile<String>(
                    title: Text(folder.path),
                    enabled: idle,
                    value: folder.id,
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        enabled: idle,
                        decoration: const InputDecoration(labelText: 'フォルダ名'),
                      ),
                    ),
                    TextButton(
                      onPressed: idle ? () => _run(_Action.create) : null,
                      child: const Text('作成'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _committing
              ? null
              : () {
                  if (!_committing &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.pop(context);
                  }
                },
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: idle && knownSelection ? () => _run(_Action.save) : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
