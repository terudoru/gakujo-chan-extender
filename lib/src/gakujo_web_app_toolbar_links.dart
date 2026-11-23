part of 'gakujo_web_app.dart';

class GakujoToolbarLink {
  const GakujoToolbarLink._(this.label, this.destination, this.url);

  factory GakujoToolbarLink.standard(GakujoQuickJumpDestination destination) =>
      GakujoToolbarLink._('${destination.label}へ移動', destination, null);

  static final defaults = List<GakujoToolbarLink>.unmodifiable(
    GakujoQuickJumpDestination.values.map(GakujoToolbarLink.standard),
  );

  final String label;
  final GakujoQuickJumpDestination? destination;
  final Uri? url;

  String get address => destination?.portalUrl ?? url.toString();

  static Uri? parseUrl(String value) {
    final text = value.trim();
    if (RegExp(r'[\s\u0000-\u001f\u007f\\]').hasMatch(text)) return null;
    final authority = RegExp(
      r'^https?://([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(text)?.group(1);
    if (authority == null || authority.contains('@')) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        !uri.hasAuthority ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  static GakujoToolbarLink? fromInput({
    required String name,
    required String address,
    GakujoQuickJumpDestination? standardDestination,
  }) {
    final label = name.trim();
    final url = parseUrl(address);
    if (label.isEmpty || url == null) return null;
    if (url.toString() == standardDestination?.portalUrl) {
      return GakujoToolbarLink._(label, standardDestination, null);
    }
    return GakujoToolbarLink._(label, null, url);
  }

  Map<String, String> toJson() {
    final standard = destination;
    return {
      'label': label,
      if (standard != null)
        'destination': standard.name
      else
        'url': url.toString(),
    };
  }

  static GakujoToolbarLink? _fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final label = value['label'];
    if (label is! String || label.trim().isEmpty) return null;
    final name = value['destination'];
    if (name is String) {
      for (final destination in GakujoQuickJumpDestination.values) {
        if (destination.name == name) {
          return GakujoToolbarLink._(label.trim(), destination, null);
        }
      }
    }
    final url = value['url'];
    return url is String ? fromInput(name: label, address: url) : null;
  }
}

class GakujoToolbarLinksStore {
  GakujoToolbarLinksStore({this._directory});

  final Directory? _directory;

  Future<File> _file() async {
    final directory = _directory ?? await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}toolbar_links.json');
  }

  Future<List<GakujoToolbarLink>> load() async {
    final file = await _file();
    if (!await file.exists()) return GakujoToolbarLink.defaults;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is List) {
        final links = data.map(GakujoToolbarLink._fromJson).nonNulls.toList();
        if (data.isEmpty || links.isNotEmpty) return links;
      }
    } on FormatException {
      // Invalid stored menu data can be replaced from the editor.
    }
    return GakujoToolbarLink.defaults;
  }

  Future<void> save(List<GakujoToolbarLink> links) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await writeDownloadFileAtomically(
      file.path,
      Stream.value(utf8.encode(jsonEncode(links))),
    );
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

class GakujoToolbarLinksDialog extends StatefulWidget {
  const GakujoToolbarLinksDialog({
    super.key,
    required this.initialLinks,
    required this.onSave,
  });

  final List<GakujoToolbarLink> initialLinks;
  final Future<bool> Function(List<GakujoToolbarLink>) onSave;

  @override
  State<GakujoToolbarLinksDialog> createState() =>
      _GakujoToolbarLinksDialogState();
}

class _GakujoToolbarLinksDialogState extends State<GakujoToolbarLinksDialog> {
  late final _links = widget.initialLinks
      .map((link) => (id: UniqueKey(), link: link))
      .toList();
  bool _saving = false;
  bool _saveFailed = false;

  Future<void> _edit([int? index]) async {
    final original = index == null ? null : _links[index].link;
    final edited = await showDialog<GakujoToolbarLink>(
      context: context,
      builder: (_) => _ToolbarLinkFields(original: original),
    );
    if (!mounted || edited == null) return;
    setState(() {
      if (index == null) {
        _links.add((id: UniqueKey(), link: edited));
      } else {
        _links[index] = (id: _links[index].id, link: edited);
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    var saved = false;
    try {
      saved = await widget.onSave(_links.map((row) => row.link).toList());
    } on Object {
      // Keep the current edits available for another attempt.
    }
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('︙メニューを編集'),
        content: SizedBox(
          width: 480,
          height: 340,
          child: Column(
            children: [
              const Text('学情のリンクはアプリ内、それ以外は既定のブラウザーで開きます。'),
              Expanded(
                child: _links.isEmpty
                    ? const Center(child: Text('移動先がありません'))
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: _links.length,
                        onReorderItem: (oldIndex, newIndex) {
                          if (_saving) return;
                          setState(() {
                            _links.insert(newIndex, _links.removeAt(oldIndex));
                          });
                        },
                        itemBuilder: (context, index) {
                          final row = _links[index];
                          return ListTile(
                            key: row.id,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: ReorderableDragStartListener(
                              index: index,
                              enabled: !_saving,
                              child: const Icon(Icons.drag_handle),
                            ),
                            title: Text(
                              row.link.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: _saving
                                ? null
                                : () => unawaited(_edit(index)),
                            trailing: PopupMenuButton<String>(
                              enabled: !_saving,
                              tooltip: '${row.link.label}の操作',
                              onSelected: (choice) {
                                if (choice == 'edit') {
                                  unawaited(_edit(index));
                                } else {
                                  setState(() {
                                    final item = _links.removeAt(index);
                                    if (choice == 'up') {
                                      _links.insert(index - 1, item);
                                    }
                                    if (choice == 'down') {
                                      _links.insert(index + 1, item);
                                    }
                                  });
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('編集'),
                                ),
                                if (index > 0)
                                  const PopupMenuItem(
                                    value: 'up',
                                    child: Text('上へ移動'),
                                  ),
                                if (index + 1 < _links.length)
                                  const PopupMenuItem(
                                    value: 'down',
                                    child: Text('下へ移動'),
                                  ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('削除'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (_saveFailed) const Text('保存できませんでした。編集内容を残しています。'),
              Wrap(
                runSpacing: 4,
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _saving ? null : () => unawaited(_edit()),
                    icon: const Icon(Icons.add),
                    label: const Text('リンクを追加'),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _links
                              ..clear()
                              ..addAll(
                                GakujoToolbarLink.defaults.map(
                                  (link) => (id: UniqueKey(), link: link),
                                ),
                              );
                          }),
                    child: const Text('初期状態に戻す'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarLinkFields extends StatefulWidget {
  const _ToolbarLinkFields({this.original});
  final GakujoToolbarLink? original;

  @override
  State<_ToolbarLinkFields> createState() => _ToolbarLinkFieldsState();
}

class _ToolbarLinkFieldsState extends State<_ToolbarLinkFields> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.original?.label);
  late final _url = TextEditingController(text: widget.original?.address);

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.original == null ? 'リンクを追加' : 'リンクを編集'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: '表示名'),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? '表示名を入力してください' : null,
              ),
              TextFormField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: (value) =>
                    GakujoToolbarLink.parseUrl(value ?? '') == null
                    ? 'http:// または https:// で始まるURLを入力してください'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              GakujoToolbarLink.fromInput(
                name: _label.text,
                address: _url.text,
                standardDestination: widget.original?.destination,
              ),
            );
          },
          child: const Text('適用'),
        ),
      ],
    );
  }
}
