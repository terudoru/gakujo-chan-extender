part of 'gakujo_web_app.dart';

class GakujoToolbarLayoutEditor extends StatefulWidget {
  const GakujoToolbarLayoutEditor({
    super.key,
    required this.initialLayout,
    required this.onSave,
  });
  final GakujoToolbarLayout initialLayout;
  final Future<bool> Function(GakujoToolbarLayout) onSave;
  @override
  State<GakujoToolbarLayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<GakujoToolbarLayoutEditor> {
  late List<String> _toolbar = [...widget.initialLayout.toolbar];
  late List<String> _menu = [...widget.initialLayout.menu];
  late Map<String, GakujoToolbarLink> _links = {...widget.initialLayout.links};
  bool _saving = false;
  String? _error;
  GakujoToolbarLayout get _layout =>
      GakujoToolbarLayout(toolbar: _toolbar, menu: _menu, links: _links);
  Future<void> _editLink([String? id]) async {
    final link = await showDialog<GakujoToolbarLink>(
      context: context,
      builder: (_) => _ToolbarLinkFields(original: _links[id]),
    );
    if (!mounted || link == null) return;
    setState(() {
      if (id != null) {
        _links[id] = link;
      } else {
        final key = 'link:${DateTime.now().microsecondsSinceEpoch}';
        _links[key] = link;
        _menu.add(key);
      }
    });
  }

  Future<void> _save() async {
    final layout = _layout;
    if (layout.validationError case final error?) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var saved = false;
    try {
      saved = await widget.onSave(layout);
    } on Object {
      /* Preserve edits. */
    }
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = '保存できませんでした。編集内容を残しています。';
      });
    }
  }

  Widget _section(String title, List<String> items, bool bar) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(title)),
          PopupMenuButton<String>(
            enabled: !_saving,
            tooltip: '$titleに追加',
            onSelected: (id) => setState(() => items.add(id)),
            itemBuilder: (_) => [
              for (final id in [
                ...GakujoToolbarLayout.labels.keys,
                ..._links.keys,
                if (bar) 'spacer' else 'divider',
              ])
                if ((bar || id != 'menu') &&
                    (id == 'divider' || !items.contains(id)))
                  PopupMenuItem(value: id, child: Text(_layout.label(id))),
            ],
            child: const Padding(padding: EdgeInsets.all(8), child: Text('追加')),
          ),
        ],
      ),
      SizedBox(
        height: 190,
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: items.length,
          onReorderItem: (oldIndex, newIndex) {
            if (!_saving) {
              setState(() => items.insert(newIndex, items.removeAt(oldIndex)));
            }
          },
          itemBuilder: (_, index) {
            final id = items[index];
            final label = _layout.label(id);
            return ListTile(
              key: ValueKey(title + index.toString() + id),
              dense: true,
              onTap: !_saving && _links.containsKey(id)
                  ? () => unawaited(_editLink(id))
                  : null,
              leading: ReorderableDragStartListener(
                index: index,
                enabled: !_saving,
                child: const Icon(Icons.drag_handle),
              ),
              title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: PopupMenuButton<String>(
                enabled: !_saving,
                tooltip: '$title: $labelの操作',
                onSelected: (choice) {
                  if (choice == 'edit') {
                    unawaited(_editLink(id));
                    return;
                  }
                  setState(() {
                    if (choice == 'delete') {
                      _links.remove(id);
                      _toolbar.removeWhere((v) => v == id);
                      _menu.removeWhere((v) => v == id);
                    } else {
                      final value = items.removeAt(index);
                      if (choice == 'up') items.insert(index - 1, value);
                      if (choice == 'down') items.insert(index + 1, value);
                    }
                  });
                },
                itemBuilder: (_) => [
                  if (index > 0)
                    const PopupMenuItem(value: 'up', child: Text('上へ移動')),
                  if (index + 1 < items.length)
                    const PopupMenuItem(value: 'down', child: Text('下へ移動')),
                  if (_links.containsKey(id))
                    const PopupMenuItem(value: 'edit', child: Text('リンクを編集')),
                  const PopupMenuItem(value: 'remove', child: Text('配置から削除')),
                  if (_links.containsKey(id))
                    const PopupMenuItem(value: 'delete', child: Text('リンクを削除')),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('ツールバーとメニューを編集'),
      content: SizedBox(
        width: 560,
        height: 500,
        child: Column(
          children: [
            if (_error != null) Text(_error!),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _section('ツールバー', _toolbar, true),
                    _section('︙メニュー', _menu, false),
                    const Text(
                      '伸縮スペースの前後にボタンを配置できます。狭い画面では横スクロールできます。リンクは学情内または既定のブラウザーで開きます。',
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => unawaited(_editLink()),
                          child: const Text('リンクを追加'),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  final defaults =
                                      GakujoToolbarLayout.defaults();
                                  _toolbar = [...defaults.toolbar];
                                  _menu = [...defaults.menu];
                                  _links = {...defaults.links};
                                  _error = null;
                                }),
                          child: const Text('初期状態に戻す'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
