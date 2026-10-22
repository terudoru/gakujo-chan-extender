import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_restore.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/widgets/settings_sections.dart';

void main() {
  test('message JSON round trip retains stable identity and displayed fields',
      () {
    final entry = _message(507762, body: '本文\n次の行');
    final restored = GakujoStarredMessage.fromJson(
      jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
    );
    expect(restored.id, '1|40|507762');
    expect(restored.toJson(), entry.toJson());
    expect(restored.toJson().keys, isNot(contains('_flowExecutionKey')));
    expect(_message(1, body: '文' * 4001).body.length, 4000);
    expect(GakujoStarredMessage.fromJson({}).isValid, isFalse);
  });

  test(
      'toggles serialize, persist across stores, sort newest first and cap at 300',
      () async {
    final storage = _Storage();
    final store = GakujoActivityStore(secureStorage: storage);
    await Future.wait([
      for (var i = 1; i <= 305; i++) store.toggleStarredMessage(_message(i)),
    ]);
    final reloaded = GakujoActivityStore(secureStorage: storage);
    var entries = await reloaded.loadStarredMessages();
    expect(entries.length, 300);
    expect(entries.first.seqNo, '305');
    expect(entries.last.seqNo, '6');
    expect(await reloaded.toggleStarredMessage(_message(305)), isFalse);
    expect(await reloaded.toggleStarredMessage(_message(305)), isTrue);
    await reloaded.upsertStarredMessage(_message(305, body: '更新'));
    entries = await reloaded.loadStarredMessages();
    expect(entries.where((entry) => entry.seqNo == '305').length, 1);
    expect(entries.first.body, '更新');
    await reloaded.removeStarredMessage(entries.first.id);
    expect((await reloaded.loadStarredMessages()).first.seqNo, '304');
  });

  test('detail refresh enriches existing stars without reordering or re-adding',
      () async {
    final store = GakujoActivityStore(secureStorage: _Storage());
    await store.replaceStarredMessages([_message(1), _message(2)]);
    await store.refreshStarredMessage(GakujoStarredMessage(
      keijitype: '1',
      genrecd: '40',
      seqNo: '1',
      title: '新しい表題',
      sender: '新しい送信元',
      period: '更新期間',
      body: '保存した本文',
      starredAt: DateTime.utc(2099),
    ));
    final entries = await store.loadStarredMessages();
    expect(entries.map((entry) => entry.seqNo), ['2', '1']);
    expect(entries.last.title, '新しい表題');
    expect(entries.last.sender, '新しい送信元');
    expect(entries.last.period, '更新期間');
    expect(entries.last.body, '保存した本文');
    expect(entries.last.postedAt, _message(1).postedAt);
    expect(entries.last.starredAt, _message(1).starredAt);
    await store.removeStarredMessage(entries.last.id);
    await store.refreshStarredMessage(_message(1, body: 'あとから届いた詳細'));
    expect(
        (await store.loadStarredMessages()).map((entry) => entry.seqNo), ['2']);
  });

  test('backup export, import and restore retain messages and disabled flag',
      () async {
    final source = _Storage();
    final activity = GakujoActivityStore(secureStorage: source);
    await activity.upsertStarredMessage(_message(1, body: 'バックアップ本文'));
    final payload = await readGakujoBackupPayload(
      currentSettings: () => const GakujoAppSettings(
        disabledFeatureFlags: {GakujoFeatureFlag.messageStars},
      ),
      settingsStore: GakujoAppSettingsStore(secureStorage: source),
      historyStore: GakujoDownloadHistoryStore(secureStorage: source),
      activityStore: activity,
    );
    final backup = parseGakujoBackup(jsonEncode(payload));
    expect(backup.starredMessages!.single.body, 'バックアップ本文');
    final target = _Storage();
    final targetActivity = GakujoActivityStore(secureStorage: target);
    final targetSettings = GakujoAppSettingsStore(secureStorage: target);
    await restoreGakujoBackup(
      backup: backup,
      settingsStore: targetSettings,
      historyStore: GakujoDownloadHistoryStore(secureStorage: target),
      activityStore: targetActivity,
      isAllowedUrl: (_) => true,
      isAllowedNavigationUrl: (_) => true,
    );
    expect((await targetActivity.loadStarredMessages()).single.toJson(),
        (await activity.loadStarredMessages()).single.toJson());
    expect(
        (await targetSettings.load())
            .isFeatureEnabled(GakujoFeatureFlag.messageStars),
        isFalse);
    // Older v2 backups omit this optional key and must preserve saved stars.
    await restoreGakujoBackup(
      backup: parseGakujoBackup('{"version":2}'),
      settingsStore: targetSettings,
      historyStore: GakujoDownloadHistoryStore(secureStorage: target),
      activityStore: targetActivity,
      isAllowedUrl: (_) => true,
      isAllowedNavigationUrl: (_) => true,
    );
    expect((await targetActivity.loadStarredMessages()).length, 1);
  });

  test(
      'failed storage reads cannot overwrite stars or produce a partial backup',
      () async {
    final storage = _Storage();
    final store = GakujoActivityStore(secureStorage: storage);
    await store.upsertStarredMessage(_message(1));
    final original = Map<String, String>.from(storage.values);
    storage.failReads = true;
    expect(await store.loadStarredMessages(), isEmpty);
    await expectLater(
        store.toggleStarredMessage(_message(1)), throwsStateError);
    await expectLater(store.loadStarredMessagesForBackup(), throwsStateError);
    expect(storage.values, original);
  });

  test('a later restore failure rolls back starred messages too', () async {
    final storage = _Storage();
    final activity = GakujoActivityStore(secureStorage: storage);
    await activity.upsertStarredMessage(_message(1));
    final original = Map<String, String>.from(storage.values);
    storage.failWriteOnce = 'more_better_gakujo_cached_report_lists';
    await expectLater(
        restoreGakujoBackup(
          backup: GakujoBackupImport(
              version: 2,
              starredMessages: [_message(2)],
              reportLists: const []),
          settingsStore: GakujoAppSettingsStore(secureStorage: storage),
          historyStore: GakujoDownloadHistoryStore(secureStorage: storage),
          activityStore: activity,
          isAllowedUrl: (_) => true,
          isAllowedNavigationUrl: (_) => true,
        ),
        throwsStateError);
    expect(storage.values, original);
  });

  test('message stars default on and the macOS settings mirror retains opt out',
      () async {
    final storage = _Storage();
    final settings = GakujoAppSettingsStore(secureStorage: storage);
    expect(
        const GakujoAppSettings()
            .isFeatureEnabled(GakujoFeatureFlag.messageStars),
        isTrue);
    expect(
        (await settings.load())
            .isFeatureEnabled(GakujoFeatureFlag.messageStars),
        isTrue);
    expect(GakujoFeatureFlag.messageStars.label, '連絡通知のスター');
    expect(GakujoFeatureFlagLabels.fromStorageValue('message_stars'),
        GakujoFeatureFlag.messageStars);
    final activity = GakujoActivityStore(secureStorage: storage);
    await activity.upsertStarredMessage(_message(1));
    await settings.saveFeatureEnabled(GakujoFeatureFlag.messageStars,
        enabled: false);
    expect((await activity.loadStarredMessages()).length, 1);
    final directory =
        await Directory.systemTemp.createTemp('message-stars-prefs-');
    try {
      final mirror = GakujoLocalPrefsStore(directory: directory);
      await mirror.saveAppSettings(await settings.load());
      expect(
          (await mirror.load())!
              .appSettings!
              .isFeatureEnabled(GakujoFeatureFlag.messageStars),
          isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  testWidgets('settings exposes the default-on star switch and its description',
      (tester) async {
    GakujoFeatureFlag? changedFlag;
    bool? enabled;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SingleChildScrollView(
          child: FeatureFlagsSection(
        settings: const GakujoAppSettings(),
        onChanged: (flag, value) {
          changedFlag = flag;
          enabled = value;
        },
      )),
    )));
    final label = find.text('連絡通知のスター');
    expect(label, findsOneWidget);
    expect(find.text('連絡通知にスターを付け、保存した内容をあとから参照できます。'), findsOneWidget);
    final tile = tester.widget<CheckboxListTile>(find.ancestor(
      of: label,
      matching: find.byType(CheckboxListTile),
    ));
    expect(tile.value, isTrue);
    await tester.ensureVisible(label);
    await tester.tap(label);
    expect(changedFlag, GakujoFeatureFlag.messageStars);
    expect(enabled, isFalse);
  });
}

GakujoStarredMessage _message(int seqNo, {String body = ''}) =>
    GakujoStarredMessage(
      keijitype: '1',
      genrecd: '40',
      seqNo: '$seqNo',
      title: '授業連絡 $seqNo',
      genre: '授業連絡',
      sender: '担当教員',
      period: '2026/10/01～2026/11/01',
      postedAt: '2026/10/01 09:00',
      body: body,
      starredAt: DateTime.utc(2026, 10, 1).add(Duration(seconds: seqNo)),
    );

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failReads = false;
  String? failWriteOnce;

  @override
  Future<String?> read(
      {required String key,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (failReads) throw StateError('unavailable');
    return values[key];
  }

  @override
  Future<void> write(
      {required String key,
      required String? value,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (key == failWriteOnce) {
      failWriteOnce = null;
      throw StateError('write failed');
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete(
      {required String key,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    values.remove(key);
  }
}
