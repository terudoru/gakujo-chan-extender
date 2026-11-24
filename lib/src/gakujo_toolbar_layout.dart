part of 'gakujo_web_app.dart';

class GakujoToolbarLayout {
  GakujoToolbarLayout({
    required Iterable<String> toolbar,
    required Iterable<String> menu,
    required Map<String, GakujoToolbarLink> links,
  }) : links = Map.unmodifiable(links) {
    final known = {...labels.keys, ...links.keys};
    List<String> clean(Iterable<String> input, bool bar) {
      final seen = <String>{};
      return List.unmodifiable(
        input.where(
          (id) =>
              (known.contains(id) || id == (bar ? 'spacer' : 'divider')) &&
              (bar || id != 'menu') &&
              (id == 'divider' || seen.add(id)),
        ),
      );
    }

    this.toolbar = clean(toolbar, true);
    this.menu = clean(menu, false);
  }
  final Map<String, GakujoToolbarLink> links;
  late final List<String> toolbar;
  late final List<String> menu;
  static const labels = <String, String>{
    'gpa': 'GPA',
    'navigation': '前後のページ',
    'reload': '再読み込み',
    'home': '学務のHOMEへ',
    'zoom': '表示倍率',
    'messageStars': 'スター付き連絡通知',
    'akiko': 'AKIKO（空き講義室検索・CIRCLE 運営の外部サービス）',
    'settings': '設定',
    'menu': 'メニュー',
    'hostedPlanner': '履修手帖',
    'coursePlanner': '履修手帖を開く',
    'notificationHistory': '通知履歴',
    'copyCoursePlanner': '学務の照会結果を履修手帖用にコピー',
    'registrationAssist': '履修手帖の時間割を履修登録に入力',
    'addFavorite': 'お気に入りに追加',
    'copyUrl': 'URLをコピー',
    'openExternal': '外部ブラウザで開く',
  };
  String label(String id) =>
      links[id]?.label ?? labels[id] ?? (id == 'spacer' ? '伸縮スペース' : '区切り線');
  String? get validationError =>
      toolbar.contains('settings') ||
          (toolbar.contains('menu') && menu.contains('settings'))
      ? null
      : '設定と編集画面を開けなくなります。設定をツールバーに置くか、ツールバーの︙とメニューの設定を残してください。';
  factory GakujoToolbarLayout.defaults([List<GakujoToolbarLink>? savedLinks]) {
    final links = <String, GakujoToolbarLink>{};
    for (final (i, link)
        in (savedLinks ?? GakujoToolbarLink.defaults).indexed) {
      var id = 'link:${link.destination?.name ?? i.toString()}';
      while (links.containsKey(id)) {
        id += '_';
      }
      links[id] = link;
    }
    return GakujoToolbarLayout(
      toolbar: const [
        'gpa',
        'spacer',
        'navigation',
        'reload',
        'home',
        'zoom',
        'messageStars',
        'akiko',
        'settings',
        'menu',
      ],
      menu: [
        ...links.keys,
        if (links.isNotEmpty) 'divider',
        'hostedPlanner',
        'coursePlanner',
        'notificationHistory',
        'copyCoursePlanner',
        'registrationAssist',
        'addFavorite',
        'messageStars',
        'copyUrl',
        'openExternal',
        'divider',
        'reload',
      ],
      links: links,
    );
  }
  Map<String, Object> toJson() => {
    'version': 1,
    'toolbar': toolbar,
    'menu': menu,
    'links': {
      for (final entry in links.entries) entry.key: entry.value.toJson(),
    },
  };
  factory GakujoToolbarLayout.fromJson(Object? data) {
    if (data is List) {
      return GakujoToolbarLayout.defaults(
        data.map(GakujoToolbarLink._fromJson).nonNulls.toList(),
      );
    }
    if (data is! Map || data['version'] != 1) {
      return GakujoToolbarLayout.defaults();
    }
    final links = <String, GakujoToolbarLink>{};
    if (data['links'] case final Map values) {
      for (final entry in values.entries) {
        final link = GakujoToolbarLink._fromJson(entry.value);
        if (entry.key is String &&
            (entry.key as String).startsWith('link:') &&
            link != null) {
          links[entry.key as String] = link;
        }
      }
    }
    final defaults = GakujoToolbarLayout.defaults();
    return GakujoToolbarLayout(
      toolbar: data['toolbar'] is List
          ? (data['toolbar'] as List).whereType<String>()
          : defaults.toolbar,
      menu: data['menu'] is List
          ? (data['menu'] as List).whereType<String>()
          : defaults.menu,
      links: links,
    );
  }
}
