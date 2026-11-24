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

  Future<GakujoToolbarLayout> loadLayout() async {
    final file = await _file();
    if (!await file.exists()) return GakujoToolbarLayout.defaults();
    try {
      return GakujoToolbarLayout.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } on FormatException {
      return GakujoToolbarLayout.defaults();
    }
  }

  Future<void> saveLayout(GakujoToolbarLayout layout) async {
    if (layout.validationError case final error?) throw ArgumentError(error);
    final file = await _file();
    await file.parent.create(recursive: true);
    await writeDownloadFileAtomically(
      file.path,
      Stream.value(utf8.encode(jsonEncode(layout.toJson()))),
    );
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
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
