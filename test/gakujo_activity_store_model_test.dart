import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('activity snapshot round-trips through json', () {
    final updatedAt = DateTime.utc(2026, 6, 26, 10);
    final snapshot = GakujoActivitySnapshot(
      category: 'レポート・小テスト',
      title: 'レポート提出',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
      contentHash: 'abc',
      updatedAt: updatedAt,
      hasUpdate: true,
      contentPreview: '新着の掲示があります。',
    );

    final restored = GakujoActivitySnapshot.fromJson(snapshot.toJson());

    expect(restored.category, 'レポート・小テスト');
    expect(restored.title, 'レポート提出');
    expect(restored.contentHash, 'abc');
    expect(restored.updatedAt, updatedAt);
    expect(restored.hasUpdate, isTrue);
    expect(restored.contentPreview, '新着の掲示があります。');
  });

  test('deadline entry key is stable', () {
    final entry = GakujoDeadlineEntry(
      title: '課題',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
      dueText: '提出期限 2099/07/01 17:00',
      detectedAt: DateTime.utc(2026, 6, 26),
    );

    expect(entry.key, contains('提出期限 2099/07/01 17:00'));
    expect(GakujoDeadlineEntry.fromJson(entry.toJson()).key, entry.key);
  });

  test('dated activity entries preserve notice and schedule kinds', () {
    final notice = GakujoDeadlineEntry(
      title: '奨学金説明会',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/keiji',
      dueText: '奨学金説明会を2099/07/01に開催します',
      detectedAt: DateTime.utc(2026, 6, 26),
      kind: 'schedule',
    );
    final restored = GakujoDeadlineEntry.fromJson(notice.toJson());

    expect(restored.kind, 'schedule');
    expect(restored.isDeadline, isFalse);
    expect(restored.key, contains('schedule'));
  });

  test('activity change entries round-trip through json', () {
    final changedAt = DateTime.utc(2026, 6, 26, 13);
    final change = GakujoActivityChangeEntry(
      category: '成績',
      title: '単位修得状況照会',
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=si',
      changedAt: changedAt,
      previousHash: 'before',
      nextHash: 'after',
      previousPreview: '以前の内容',
      nextPreview: '新しい内容',
    );

    final restored = GakujoActivityChangeEntry.fromJson(change.toJson());

    expect(restored.category, '成績');
    expect(restored.title, '単位修得状況照会');
    expect(restored.changedAt, changedAt);
    expect(restored.previousHash, 'before');
    expect(restored.nextHash, 'after');
    expect(restored.previousPreview, '以前の内容');
    expect(restored.nextPreview, '新しい内容');
  });

  test('cached report lists round-trip through json', () {
    final capturedAt = DateTime.utc(2026, 6, 26, 14);
    final reportList = GakujoCachedReportList(
      title: 'レポート',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
      capturedAt: capturedAt,
      items: const ['課題A 提出期限 2099/07/01'],
    );

    final restored = GakujoCachedReportList.fromJson(reportList.toJson());

    expect(restored.title, 'レポート');
    expect(restored.url, reportList.url);
    expect(restored.capturedAt, capturedAt);
    expect(restored.items, ['課題A 提出期限 2099/07/01']);
  });

  test('favorite page round-trips through json', () {
    final addedAt = DateTime.utc(2026, 6, 26, 11);
    final favorite = GakujoFavoritePage(
      title: '成績',
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=si',
      addedAt: addedAt,
    );

    final restored = GakujoFavoritePage.fromJson(favorite.toJson());

    expect(restored.title, '成績');
    expect(restored.url, favorite.url);
    expect(restored.addedAt, addedAt);
  });

  test('recordSnapshot treats the first scan as a baseline', () async {
    final store = GakujoActivityStore();

    final first = await store.recordSnapshot(
      category: '成績',
      title: '単位修得状況照会',
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=si',
      content: 'GP 3.3',
    );
    final second = await store.recordSnapshot(
      category: '成績',
      title: '単位修得状況照会',
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=si',
      content: 'GP 3.7',
    );

    expect(first.hasUpdate, isFalse);
    expect(first.contentPreview, 'GP 3.3');
    expect(second.hasUpdate, isTrue);
    expect(second.contentPreview, 'GP 3.7');
    expect(await store.loadChanges(), hasLength(1));
  });

  test('recordSnapshot stores a readable preview without common page chrome',
      () async {
    final store = GakujoActivityStore();

    await store.recordSnapshot(
      category: '連絡通知',
      title: '掲示',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
      content: [
        '[image]',
        'スマホ版',
        'HOME',
        '残り約20分',
        '授業評価アンケートが登録されました。',
        '【重要】履修登録について',
      ].join('\n'),
    );

    final snapshot = (await store.loadSnapshots()).single;
    expect(snapshot.contentPreview, contains('授業評価アンケート'));
    expect(snapshot.contentPreview, contains('履修登録'));
    expect(snapshot.contentPreview, isNot(contains('スマホ版')));
    expect(snapshot.contentPreview, isNot(contains('残り約20分')));
  });

  test('recordSnapshot keeps separate pages in the same category', () async {
    final store = GakujoActivityStore();

    await store.recordSnapshot(
      category: 'レポート・小テスト',
      title: 'レポート一覧',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list',
      content: '課題A',
    );
    await store.recordSnapshot(
      category: 'レポート・小テスト',
      title: '小テスト一覧',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/quiz/list',
      content: '小テストB',
    );

    final snapshots = await store.loadSnapshots();
    expect(snapshots, hasLength(2));
    expect(snapshots.map((snapshot) => snapshot.url), {
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list',
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/quiz/list',
    });
  });

  test('recordSnapshot caps stored baselines to recent pages', () async {
    final store = GakujoActivityStore();

    for (var i = 0; i < 140; i += 1) {
      await store.recordSnapshot(
        category: 'その他',
        title: 'page $i',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/page-$i',
        content: 'content $i',
      );
    }

    final snapshots = await store.loadSnapshots();
    expect(snapshots, hasLength(120));
  });

  test('recordSnapshot ignores blank activity content', () async {
    final store = GakujoActivityStore();

    final snapshot = await store.recordSnapshot(
      category: 'その他',
      title: '空ページ',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/blank',
      content: '   ',
    );

    expect(snapshot.hasUpdate, isFalse);
    expect(snapshot.contentHash, isEmpty);
    expect(await store.loadSnapshots(), isEmpty);
  });

  test('loadSnapshots drops unusable legacy baselines', () async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'more_better_gakujo_activity_snapshots',
      value: jsonEncode([
        {
          'category': 'その他',
          'title': '',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/bad',
          'contentHash': 'abc',
          'updatedAt': '2099-06-26T00:00:00.000Z',
          'hasUpdate': true,
        },
        {
          'category': 'その他',
          'title': 'valid',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/valid',
          'contentHash': 'def',
          'updatedAt': '2099-06-26T00:00:00.000Z',
          'hasUpdate': false,
        },
      ]),
    );

    final snapshots = await GakujoActivityStore().loadSnapshots();
    expect(snapshots, hasLength(1));
    expect(snapshots.single.title, 'valid');
  });

  test('loadSnapshots drops noisy generic home portal baselines', () async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'more_better_gakujo_activity_snapshots',
      value: jsonEncode([
        {
          'category': 'スケジュール',
          'title': 'CampusSquare for WEB [CampusSquare]',
          'url':
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main',
          'contentHash': 'abc',
          'updatedAt': DateTime.now().toIso8601String(),
          'hasUpdate': true,
          'contentPreview': '吉田 皓彦 さん\nMYスケジュール',
        },
        {
          'category': 'Gakujo',
          'title': 'CampusSquare for WEB [CampusSquare]',
          'url':
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
          'contentHash': 'def',
          'updatedAt': DateTime.now().toIso8601String(),
          'hasUpdate': true,
          'contentPreview': 'now loading...',
        },
        {
          'category': 'スケジュール',
          'title': 'CampusSquare for WEB [CampusSquare]',
          'url':
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
          'contentHash': 'old-main',
          'updatedAt': DateTime.now().toIso8601String(),
          'hasUpdate': true,
          'contentPreview': '吉田 皓彦 さん\n前回ログイン日時:\n出欠管理\nフォーラム\n新着情報',
        },
        {
          'category': '成績',
          'title': '単位修得状況照会',
          'url':
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=si',
          'contentHash': 'ghi',
          'updatedAt': DateTime.now().toIso8601String(),
          'hasUpdate': true,
          'contentPreview': 'GP 3.3',
        },
      ]),
    );

    final snapshots = await GakujoActivityStore().loadSnapshots();
    expect(snapshots, hasLength(1));
    expect(snapshots.single.title, '単位修得状況照会');
  });

  test('loadSnapshots drops stale legacy baselines', () async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'more_better_gakujo_activity_snapshots',
      value: jsonEncode([
        {
          'category': 'その他',
          'title': 'old',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/old',
          'contentHash': 'abc',
          'updatedAt': DateTime.now()
              .subtract(const Duration(days: 220))
              .toIso8601String(),
          'hasUpdate': true,
        },
        {
          'category': 'その他',
          'title': 'recent',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/recent',
          'contentHash': 'def',
          'updatedAt': DateTime.now()
              .subtract(const Duration(days: 20))
              .toIso8601String(),
          'hasUpdate': false,
        },
      ]),
    );

    final snapshots = await GakujoActivityStore().loadSnapshots();
    expect(snapshots, hasLength(1));
    expect(snapshots.single.title, 'recent');
  });

  test('compact removes stale stored activity entries and keeps newest first',
      () async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'more_better_gakujo_activity_snapshots',
      value: jsonEncode([
        {
          'category': 'その他',
          'title': 'old',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/old',
          'contentHash': 'abc',
          'updatedAt': DateTime.now()
              .subtract(const Duration(days: 220))
              .toIso8601String(),
          'hasUpdate': true,
        },
        {
          'category': 'その他',
          'title': 'newer',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/newer',
          'contentHash': 'def',
          'updatedAt': DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
          'hasUpdate': false,
        },
        {
          'category': 'その他',
          'title': 'older',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/older',
          'contentHash': 'ghi',
          'updatedAt': DateTime.now()
              .subtract(const Duration(days: 20))
              .toIso8601String(),
          'hasUpdate': false,
        },
      ]),
    );

    final store = GakujoActivityStore();
    await store.compact();

    final snapshots = await store.loadSnapshots();
    expect(snapshots.map((entry) => entry.title), ['newer', 'older']);
    final raw = await storage.read(
      key: 'more_better_gakujo_activity_snapshots',
    );
    expect(raw, isNot(contains('"title":"old"')));
  });

  test('clearSnapshots removes update badges without touching deadlines',
      () async {
    final store = GakujoActivityStore();
    await store.recordSnapshot(
      category: '連絡通知',
      title: '掲示',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
      content: '掲示があります',
    );
    await store.mergeDeadlines([
      GakujoDeadlineEntry(
        title: '課題',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
        dueText: '提出期限 2099/07/01',
        detectedAt: DateTime.utc(2026, 6, 26),
      ),
    ]);

    await store.clearSnapshots();

    expect(await store.loadSnapshots(), isEmpty);
    expect(await store.loadDeadlines(), hasLength(1));
  });

  test('loadDeadlines drops expired due dates after the grace period',
      () async {
    final store = GakujoActivityStore();

    await store.replaceDeadlines([
      GakujoDeadlineEntry(
        title: '期限切れ課題',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/old-report',
        dueText: '提出期限 2000/01/01 17:00',
        detectedAt: DateTime.utc(2000, 1, 1),
      ),
      GakujoDeadlineEntry(
        title: '今後の課題',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/new-report',
        dueText: '提出期限 2099/01/01 17:00',
        detectedAt: DateTime.now(),
      ),
    ]);

    final deadlines = await store.loadDeadlines();
    expect(deadlines, hasLength(1));
    expect(deadlines.single.title, '今後の課題');
  });

  test('loadDeadlines uses the end of a submission period as the due date',
      () async {
    final store = GakujoActivityStore();

    await store.replaceDeadlines([
      GakujoDeadlineEntry(
        title: '提出期間つき課題',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
        dueText: '提出期間 2000/01/01 00:00～2099/01/01 17:00',
        detectedAt: DateTime.now(),
      ),
      GakujoDeadlineEntry(
        title: '和暦表記ではない年月日課題',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report2',
        dueText: '提出期間 2000年01月01日 00:00～2099年01月02日 17:00',
        detectedAt: DateTime.now(),
      ),
      GakujoDeadlineEntry(
        title: '全角数字の案内',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/message1',
        dueText: '履修登録期間は２０９９年０７月０１日（火）２３：５９までです。',
        detectedAt: DateTime.now(),
      ),
      GakujoDeadlineEntry(
        title: '元号表記の予定',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/message2',
        dueText: '令和81年7月29日（水）13：00より開催します。',
        detectedAt: DateTime.now(),
        kind: 'schedule',
      ),
    ]);

    final deadlines = await store.loadDeadlines();
    expect(deadlines.map((entry) => entry.title), contains('提出期間つき課題'));
    expect(deadlines.map((entry) => entry.title), contains('和暦表記ではない年月日課題'));
    expect(deadlines.map((entry) => entry.title), contains('全角数字の案内'));
    expect(deadlines.map((entry) => entry.title), contains('元号表記の予定'));
  });

  test('loadDeadlines drops stale undated entries', () async {
    final store = GakujoActivityStore();

    await store.replaceDeadlines([
      GakujoDeadlineEntry(
        title: '古い未解析期限',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/old',
        dueText: '提出期限 調整中',
        detectedAt: DateTime.now().subtract(const Duration(days: 120)),
      ),
      GakujoDeadlineEntry(
        title: '最近の未解析期限',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/recent',
        dueText: '提出期限 調整中',
        detectedAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
    ]);

    final deadlines = await store.loadDeadlines();
    expect(deadlines, hasLength(1));
    expect(deadlines.single.title, '最近の未解析期限');
  });

  test('loadChanges and report lists drop stale entries', () async {
    final store = GakujoActivityStore();

    await store.replaceChanges([
      GakujoActivityChangeEntry(
        category: '連絡通知',
        title: '古い更新',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/old-change',
        changedAt: DateTime.now().subtract(const Duration(days: 120)),
        previousHash: 'before-old',
        nextHash: 'after-old',
      ),
      GakujoActivityChangeEntry(
        category: '連絡通知',
        title: '最近の更新',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/recent-change',
        changedAt: DateTime.now().subtract(const Duration(days: 10)),
        previousHash: 'before-recent',
        nextHash: 'after-recent',
      ),
    ]);
    await store.replaceReportLists([
      GakujoCachedReportList(
        title: '古いレポート',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/old-report-list',
        capturedAt: DateTime.now().subtract(const Duration(days: 90)),
        items: const ['課題A'],
      ),
      GakujoCachedReportList(
        title: '最近のレポート',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/recent-report-list',
        capturedAt: DateTime.now().subtract(const Duration(days: 10)),
        items: const ['課題B'],
      ),
    ]);

    final changes = await store.loadChanges();
    final reportLists = await store.loadReportLists();
    expect(changes, hasLength(1));
    expect(changes.single.title, '最近の更新');
    expect(reportLists, hasLength(1));
    expect(reportLists.single.title, '最近のレポート');
  });

  test('replace methods keep newest imported activity entries', () async {
    final store = GakujoActivityStore();
    final base = DateTime.now().subtract(const Duration(days: 1));

    await store.replaceDeadlines([
      for (var i = 0; i < 85; i += 1)
        GakujoDeadlineEntry(
          title: '課題$i',
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report-$i',
          dueText: '提出期限 2099/07/01',
          detectedAt: base.add(Duration(minutes: i)),
        ),
    ]);
    await store.replaceFavorites([
      for (var i = 0; i < 35; i += 1)
        GakujoFavoritePage(
          title: 'ページ$i',
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/page-$i',
          addedAt: base.add(Duration(minutes: i)),
        ),
    ]);
    await store.replaceReportLists([
      for (var i = 0; i < 25; i += 1)
        GakujoCachedReportList(
          title: 'レポート$i',
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report-list-$i',
          capturedAt: base.add(Duration(minutes: i)),
          items: const ['課題A'],
        ),
    ]);
    await store.replaceChanges([
      for (var i = 0; i < 125; i += 1)
        GakujoActivityChangeEntry(
          category: '連絡通知',
          title: '更新$i',
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/change-$i',
          changedAt: base.add(Duration(minutes: i)),
          previousHash: 'before-$i',
          nextHash: 'after-$i',
        ),
    ]);

    final deadlines = await store.loadDeadlines();
    final favorites = await store.loadFavorites();
    final reportLists = await store.loadReportLists();
    final changes = await store.loadChanges();
    expect(deadlines, hasLength(80));
    expect(deadlines.first.title, '課題84');
    expect(deadlines.last.title, '課題5');
    expect(favorites, hasLength(30));
    expect(favorites.first.title, 'ページ34');
    expect(favorites.last.title, 'ページ5');
    expect(reportLists, hasLength(20));
    expect(reportLists.first.title, 'レポート24');
    expect(reportLists.last.title, 'レポート5');
    expect(changes, hasLength(120));
    expect(changes.first.title, '更新124');
    expect(changes.last.title, '更新5');
  });

  test('replace methods drop unusable imported activity entries', () async {
    final store = GakujoActivityStore();

    await store.replaceDeadlines([
      GakujoDeadlineEntry(
        title: '課題',
        url: '',
        dueText: '提出期限 2099/07/01',
        detectedAt: DateTime.utc(2026, 6, 26),
      ),
      GakujoDeadlineEntry(
        title: '課題',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
        dueText: '',
        detectedAt: DateTime.utc(2026, 6, 26),
      ),
      GakujoDeadlineEntry(
        title: '課題',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
        dueText: '提出期限 2099/07/01',
        detectedAt: DateTime.utc(2026, 6, 26),
      ),
    ]);
    await store.replaceFavorites([
      GakujoFavoritePage(
        title: '',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
        addedAt: DateTime.utc(2026, 6, 26),
      ),
    ]);
    await store.replaceReportLists([
      GakujoCachedReportList(
        title: 'レポート',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
        capturedAt: DateTime.utc(2026, 6, 26),
        items: const ['   '],
      ),
    ]);

    expect(await store.loadDeadlines(), hasLength(1));
    expect(await store.loadFavorites(), isEmpty);
    expect(await store.loadReportLists(), isEmpty);
  });

  test('load methods drop unusable legacy activity entries', () async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'more_better_gakujo_deadlines',
      value: jsonEncode([
        {
          'title': '課題',
          'url': '',
          'dueText': '提出期限 2099/07/01',
          'detectedAt': '2099-06-26T00:00:00.000Z',
        },
        {
          'title': '課題',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
          'dueText': '提出期限 2099/07/01',
          'detectedAt': '2099-06-26T00:00:00.000Z',
        },
      ]),
    );
    await storage.write(
      key: 'more_better_gakujo_favorites',
      value: jsonEncode([
        {
          'title': '',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
          'addedAt': '2099-06-26T00:00:00.000Z',
        },
      ]),
    );
    await storage.write(
      key: 'more_better_gakujo_activity_changes',
      value: jsonEncode([
        {
          'category': '成績',
          'title': '単位修得状況照会',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/grades',
          'changedAt': '2099-06-26T00:00:00.000Z',
          'previousHash': '',
          'nextHash': 'next',
        },
      ]),
    );
    await storage.write(
      key: 'more_better_gakujo_cached_report_lists',
      value: jsonEncode([
        {
          'title': 'レポート',
          'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
          'capturedAt': '2099-06-26T00:00:00.000Z',
          'items': ['   '],
        },
      ]),
    );

    final store = GakujoActivityStore();
    expect(await store.loadDeadlines(), hasLength(1));
    expect(await store.loadFavorites(), isEmpty);
    expect(await store.loadChanges(), isEmpty);
    expect(await store.loadReportLists(), isEmpty);
  });
}
