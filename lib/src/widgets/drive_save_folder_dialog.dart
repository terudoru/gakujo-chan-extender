import 'dart:async';

import 'package:flutter/material.dart';

import '../google_drive_file_saver.dart';

class DriveSaveFolderResult {
  const DriveSaveFolderResult(this.folder);

  final GoogleDriveFolder? folder;
}

class DriveSaveFolderDialog extends StatefulWidget {
  const DriveSaveFolderDialog({
    super.key,
    required this.load,
    required this.create,
    required this.currentId,
  });

  final Future<List<GoogleDriveFolder>> Function() load;
  final Future<GoogleDriveFolder> Function(String) create;
  final String? currentId;

  @override
  State<DriveSaveFolderDialog> createState() => _DriveSaveFolderDialogState();
}

class _DriveSaveFolderDialogState extends State<DriveSaveFolderDialog> {
  final _name = TextEditingController();
  List<GoogleDriveFolder> _folders = [];
  String? _selectedId;
  bool _loading = true;
  bool _creating = false;
  bool _loadFailed = false;
  bool _createFailed = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentId;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final folders = await widget.load();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _createFailed = false;
    });
    try {
      final folder = await widget.create(_name.text);
      if (!mounted) return;
      setState(() {
        _folders = [..._folders.where((item) => item.id != folder.id), folder]
          ..sort((a, b) => a.path.compareTo(b.path));
        _selectedId = folder.id;
        _name.clear();
      });
    } on Object {
      if (mounted) setState(() => _createFailed = true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _folders.where((folder) => folder.id == _selectedId);
    return AlertDialog(
      title: const Text('保存先フォルダ'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: RadioGroup<String>(
            groupValue: _selectedId ?? '',
            onChanged: (value) => setState(() {
              _selectedId = value == null || value.isEmpty ? null : value;
            }),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'このアプリで作ったフォルダだけが表示されます。新しく作ったフォルダは、'
                  'Google ドライブ上で好きな場所に移動しても保存先として使えます。',
                ),
                const RadioListTile<String>(
                  title: Text('既定（More Better Gakujo）'),
                  value: '',
                ),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_loadFailed) const Text('フォルダの一覧を読み込めませんでした'),
                for (final folder in _folders)
                  RadioListTile<String>(
                    title: Text(folder.path),
                    value: folder.id,
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'フォルダ名'),
                      ),
                    ),
                    TextButton(
                      onPressed: _loading || _creating ? null : _create,
                      child: const Text('作成'),
                    ),
                  ],
                ),
                if (_createFailed) const Text('フォルダを作成できませんでした'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: _creating || (_selectedId != null && selected.isEmpty)
              ? null
              : () => Navigator.pop(
                  context,
                  DriveSaveFolderResult(
                    _selectedId == null ? null : selected.first,
                  ),
                ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
