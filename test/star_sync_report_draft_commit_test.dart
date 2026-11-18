import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_report_draft_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart'
    show applyGakujoSyncedReportDrafts;
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_adapters.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

import 'support/memory_secure_storage.dart';

class _Storage extends MemorySecureStorage {
  void Function(String?)? beforeStateWrite;
  bool failState = false;
  bool failStateOnce = false;
  bool failStateAfterMutationOnce = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == starSyncStateKey) {
      beforeStateWrite?.call(value);
      if (failState || failStateOnce) {
        failStateOnce = false;
        throw StateError('State save failed');
      }
    }
    await super.write(key: key, value: value);
    if (key == starSyncStateKey && failStateAfterMutationOnce) {
      failStateAfterMutationOnce = false;
      throw StateError('State save failed after mutation');
    }
  }
}

class _Remote implements StarSyncTransport {
  final files = <String, List<int>>{};
  @override
  Future<void> ensureDirectory(String path) async {}
  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async => [
    for (final entry in files.entries)
      if (entry.key.startsWith('$directory/'))
        StarSyncRemoteEntry(path: entry.key, etag: base64Encode(entry.value)),
  ];
  @override
  Future<StarSyncRemoteObject?> get(
    String path, {
    int maxBytes = starSyncDefaultMaxBytes,
  }) async => files.containsKey(path)
      ? StarSyncRemoteObject(bytes: List.of(files[path]!))
      : null;
  @override
  Future<void> put(
    String path,
    List<int> bytes, {
    bool createOnly = false,
  }) async {
    if (createOnly && files.containsKey(path)) {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.alreadyExists,
        'Already exists',
      );
    }
    files[path] = List.of(bytes);
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }

  @override
  void close() {}
}

// The generated scripts and existing fake DOM run in a persistent Node process.
// Native WebView acknowledgement/navigation delivery remains a synthetic boundary.
class _Page {
  _Page(this.process, this.lines);
  final Process process;
  final StreamIterator<String> lines;
  final epoch = DateTime.now().millisecondsSinceEpoch;

  static Future<_Page> start() async {
    final process = await Process.start('node', [
      'test/support/report_draft_dom_harness.cts',
      '--sync-bridge',
    ]);
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    final page = _Page(
      process,
      StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
    );
    addTearDown(() async {
      await process.stdin.close();
      expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
      await page.lines.cancel();
      expect(errors.toString(), isEmpty);
    });
    await page.send({
      'op': 'init',
      'script': GakujoReportDraftScript.build(),
      'now': page.epoch,
    });
    return page;
  }

  Future<dynamic> send(Map<String, Object?> command) async {
    process.stdin.writeln(jsonEncode(command));
    if (!await lines.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('Draft bridge closed');
    }
    final response = jsonDecode(lines.current) as Map;
    if (response['ok'] != true) throw StateError('${response['error']}');
    return response['result'];
  }

  Future<dynamic> evaluate(String script) =>
      send({'op': 'eval', 'script': script});
  Future<Map<String, Object?>> read() async => Map<String, Object?>.from(
    jsonDecode(
      await evaluate(GakujoReportDraftScript.buildExportAll()) as String,
    ),
  );
  Future<void> edit(String text, int offset, {bool flush = true}) async {
    await send({
      'op': 'edit',
      'text': text,
      'now': epoch + offset,
      'flush': flush,
    });
  }

  Future<void> navigate() async {
    await send({'op': 'navigate'});
  }

  Future<void> delete() async {
    final key = (await send({'op': 'snapshot'}))['key'] as String;
    expect(await evaluate(GakujoReportDraftScript.buildDelete(key)), true);
  }

  Future<String?> text() async {
    final values = await read();
    return values.isEmpty
        ? null
        : ((values.values.single as Map)['fields'] as List).first['value']
              as String;
  }
}

class _Device {
  _Device(this.remote, this.page, {_Storage? persisted})
    : storage = persisted ?? _Storage() {
    engine = StarSyncEngine(
      loginId: () => login,
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      collections: [
        StarSyncReportDraftsCollection(
          read: () async {
            final values = await page.read();
            readRevision = navigationRevision;
            return values;
          },
          apply: (values, {required basedOn, stillCurrent}) =>
              applyGakujoSyncedReportDrafts(
                drafts: values,
                basedOn: basedOn,
                readRevision: readRevision,
                navigationRevision: () => navigationRevision,
                canSync: () async => true,
                stillCurrent: stillCurrent,
                evaluate: (script) async {
                  imports++;
                  final before = beforeImport;
                  beforeImport = null;
                  await before?.call();
                  final applied = await page.evaluate(script) as bool;
                  final after = afterImport;
                  afterImport = null;
                  await after?.call();
                  return '$applied';
                },
              ),
        ),
      ],
    );
    addTearDown(engine.dispose);
  }
  final _Remote remote;
  final _Page page;
  final _Storage storage;
  late final StarSyncEngine engine;
  String login = 'student';
  int imports = 0;
  int navigationRevision = 0;
  int? readRevision;
  Future<void> Function()? beforeImport;
  Future<void> Function()? afterImport;
  Map get state => jsonDecode(storage.values[starSyncStateKey]!);
  Map get baseline => state['collectionStates']['report-drafts'];
  List<int> get uploaded =>
      remote.files['sync/report-drafts/${state['deviceId']}']!;
  Future<_Device> restart() async {
    engine.dispose();
    await page.navigate();
    final next = _Device(remote, page, persisted: storage);
    await next.engine.load();
    return next;
  }
}

Future<({_Device source, _Device receiver})> _pair() async {
  final remote = _Remote();
  final source = _Device(remote, await _Page.start());
  final receiver = _Device(remote, await _Page.start());
  await source.page.edit('base', 1000);
  await source.engine.setUpWithDrive(const StarSyncConfig());
  await receiver.engine.setUpWithDrive(const StarSyncConfig());
  expect(await receiver.page.text(), 'base');
  return (source: source, receiver: receiver);
}

void main() {
  for (final navigation in [false, true]) {
    for (final restart in [false, true]) {
      test('uncertain import cannot delete recreated text '
          '(navigation=$navigation, restart=$restart)', () async {
        final (:source, :receiver) = await _pair();
        await source.page.delete();
        await source.page.navigate();
        await source.engine.syncNow();
        final uploaded = List.of(receiver.uploaded);
        receiver.afterImport = () async {
          if (navigation) {
            receiver.navigationRevision++;
            await receiver.page.navigate();
            return;
          }
          receiver.storage.failStateOnce = true;
        };
        await receiver.engine.syncNow();
        expect(await receiver.page.text(), isNull);
        await source.page.edit('newly-recreated-answer', 3000);
        await source.page.navigate();
        await source.engine.syncNow();
        final receiving = restart ? await receiver.restart() : receiver;
        await receiving.engine.syncNow();
        await source.engine.syncNow();
        expect(await source.page.text(), 'newly-recreated-answer');
        expect(receiving.uploaded, uploaded);
        expect(receiving.engine.collectionEnabled('report-drafts'), false);
        expect(receiving.baseline['pendingLocalCommit'], true);
        await expectLater(
          receiving.engine.setCollectionEnabled('report-drafts', true),
          throwsStateError,
        );
      });

      test('uncertain import cannot resurrect deleted text '
          '(navigation=$navigation, restart=$restart)', () async {
        final (:source, :receiver) = await _pair();
        await source.page.edit('imported', 2000);
        await source.engine.syncNow();
        final uploaded = List.of(receiver.uploaded);
        receiver.afterImport = () async {
          if (navigation) {
            receiver.navigationRevision++;
            await receiver.page.navigate();
          } else {
            receiver.storage.failStateOnce = true;
          }
        };
        await receiver.engine.syncNow();
        expect(await receiver.page.text(), 'imported');
        await source.page.delete();
        await source.page.navigate();
        await source.engine.syncNow();
        final receiving = restart ? await receiver.restart() : receiver;
        await receiving.engine.syncNow();
        await source.engine.syncNow();
        expect(await source.page.text(), isNull);
        expect(receiving.uploaded, uploaded);
        expect(receiving.engine.collectionEnabled('report-drafts'), false);
      });
    }
  }

  for (final afterMutation in [false, true]) {
    for (final completion in [false, true]) {
      test('continuing state outage retains a safe restart boundary '
          '(afterMutation=$afterMutation, completion=$completion)', () async {
        final (:source, :receiver) = await _pair();
        await source.page.edit('imported', 2000);
        await source.engine.syncNow();
        final uploaded = List.of(receiver.uploaded);
        receiver.afterImport = () async {
          var writes = 0;
          receiver.storage.beforeStateWrite = (_) {
            if (++writes == (completion ? 2 : 1)) {
              if (afterMutation) {
                receiver.storage.failStateAfterMutationOnce = true;
              } else {
                receiver.storage.failStateOnce = true;
              }
            } else {
              receiver.storage.failState = writes > (completion ? 2 : 1);
            }
          };
        };
        await expectLater(receiver.engine.syncNow(), throwsStateError);
        expect(await receiver.page.text(), 'imported');
        expect(receiver.uploaded, uploaded);
        expect(receiver.engine.collectionEnabled('report-drafts'), false);
        receiver.storage.beforeStateWrite = null;
        receiver.storage.failState = false;
        final receiving = await receiver.restart();
        await source.page.delete();
        await source.page.navigate();
        await source.engine.syncNow();
        await receiving.engine.syncNow();
        await source.engine.syncNow();
        expect(await source.page.text(), isNull);
        if (completion && afterMutation) {
          // The clear mutated before throwing: the durable pair is consistent.
          expect(await receiving.page.text(), isNull);
          expect(receiving.engine.collectionEnabled('report-drafts'), true);
        } else {
          expect(receiving.baseline['pendingLocalCommit'], true);
          expect(receiving.engine.collectionEnabled('report-drafts'), false);
          expect(receiving.uploaded, uploaded);
        }
      });
    }

    test('failed initial journal save never invokes import '
        '(afterMutation=$afterMutation)', () async {
      final (:source, :receiver) = await _pair();
      await source.page.edit('remote', 2000);
      await source.engine.syncNow();
      final imports = receiver.imports;
      receiver.storage.beforeStateWrite = (value) {
        final collection = jsonDecode(
          value!,
        )['collectionStates']['report-drafts'];
        if (collection?['pendingLocalCommit'] != true) return;
        receiver.storage.beforeStateWrite = null;
        if (afterMutation) {
          receiver.storage.failStateAfterMutationOnce = true;
        } else {
          receiver.storage.failStateOnce = true;
        }
      };
      await receiver.engine.syncNow();
      expect(receiver.imports, imports);
      expect(await receiver.page.text(), 'base');
      final receiving = await receiver.restart();
      await receiving.engine.syncNow();
      expect(await receiving.page.text(), 'remote');
      expect(receiving.engine.collectionEnabled('report-drafts'), true);
    });
  }

  test(
    'lost import acknowledgement retains later explicit local input',
    () async {
      final (:source, :receiver) = await _pair();
      await source.page.edit('remote', 2000);
      await source.engine.syncNow();
      final uploaded = List.of(receiver.uploaded);
      receiver.afterImport = () async {
        throw StateError('Bridge closed');
      };
      await receiver.engine.syncNow();
      await receiver.page.edit('explicit-local', 4000, flush: false);
      final receiving = await receiver.restart();
      await source.page.edit('later-remote', 5000);
      await source.page.navigate();
      await source.engine.syncNow();
      await receiving.engine.syncNow();
      await source.engine.syncNow();
      expect(await receiving.page.text(), 'explicit-local');
      expect(await source.page.text(), 'later-remote');
      expect(receiving.uploaded, uploaded);
      expect(receiving.engine.collectionEnabled('report-drafts'), false);
    },
  );

  test(
    'account change after import never uploads the uncertain local value',
    () async {
      final (:source, :receiver) = await _pair();
      await source.page.edit('remote', 2000);
      await source.engine.syncNow();
      final uploaded = List.of(receiver.uploaded);
      receiver.afterImport = () async {
        receiver.login = 'another-student';
      };
      await receiver.engine.syncNow();
      expect(await receiver.page.text(), 'remote');
      expect(receiver.uploaded, uploaded);
      expect(receiver.state['localReviewRequired'], true);
      expect(receiver.baseline['pendingLocalCommit'], true);
    },
  );

  test(
    'pre-invocation navigation refuses safely and retries on a fresh read',
    () async {
      final (:source, :receiver) = await _pair();
      await source.page.edit('remote', 2000);
      await source.engine.syncNow();
      final imports = receiver.imports;
      receiver.storage.beforeStateWrite = (value) {
        final collection = jsonDecode(
          value!,
        )['collectionStates']['report-drafts'];
        if (collection?['pendingLocalCommit'] != true) return;
        receiver.storage.beforeStateWrite = null;
        receiver.navigationRevision++;
      };
      await receiver.engine.syncNow();
      expect(receiver.imports, imports);
      expect(await receiver.page.text(), 'base');
      expect(receiver.baseline['pendingLocalCommit'], isNull);
      expect(receiver.engine.collectionEnabled('report-drafts'), true);
      await receiver.engine.syncNow();
      expect(await receiver.page.text(), 'remote');
    },
  );

  group('draft apply acknowledgement', () {
    for (final mode in [
      'stale',
      'unavailable',
      'check throws',
      'navigates',
      'account',
    ]) {
      test('$mode does not invoke JavaScript', () async {
        var revision = 1;
        var invoked = false;
        final applying = applyGakujoSyncedReportDrafts(
          drafts: const {},
          basedOn: const {},
          readRevision: mode == 'stale' ? 0 : 1,
          navigationRevision: () => revision,
          canSync: () async {
            if (mode == 'check throws') throw StateError('Page destroyed');
            if (mode == 'navigates') revision++;
            return mode != 'unavailable';
          },
          stillCurrent: () => mode != 'account',
          evaluate: (_) async {
            invoked = true;
            return 'true';
          },
        );
        if (mode == 'account') {
          await expectLater(
            applying,
            throwsA(isA<StarSyncAccountMismatchException>()),
          );
        } else {
          expect(await applying, false);
        }
        expect(invoked, false);
      });
    }
    for (final result in ['true', 'false', 'unexpected']) {
      test('post-invocation navigation with $result acknowledgement', () async {
        var revision = 1;
        final applying = applyGakujoSyncedReportDrafts(
          drafts: const {},
          basedOn: const {},
          readRevision: 1,
          navigationRevision: () => revision,
          canSync: () async => true,
          evaluate: (_) async {
            revision++;
            return result;
          },
        );
        if (result == 'false') {
          expect(await applying, false);
        } else {
          await expectLater(applying, throwsStateError);
        }
      });
    }
  });

  test(
    'acknowledged import allows later recreation and genuine deletion',
    () async {
      final (:source, :receiver) = await _pair();
      await source.page.delete();
      await source.page.navigate();
      await source.engine.syncNow();
      await receiver.engine.syncNow();
      expect(await receiver.page.text(), isNull);
      await source.page.edit('recreated', 3000);
      await source.page.navigate();
      await source.engine.syncNow();
      final receiving = await receiver.restart();
      await receiving.engine.syncNow();
      expect(await receiving.page.text(), 'recreated');
      expect(receiving.baseline['pendingLocalCommit'], isNull);
      await receiving.page.delete();
      await receiving.page.navigate();
      await receiving.engine.syncNow();
      await source.engine.syncNow();
      expect(await source.page.text(), isNull);
      expect(receiving.engine.collectionEnabled('report-drafts'), true);
    },
  );

  test(
    'CAS refusal preserves pending input and permits a genuine edit retry',
    () async {
      final (:source, :receiver) = await _pair();
      await source.page.edit('remote', 2000);
      await source.engine.syncNow();
      final records = jsonEncode(receiver.baseline['records']);
      final uploaded = List.of(receiver.uploaded);
      receiver.beforeImport = () =>
          receiver.page.edit('pending-user', 4000, flush: false);
      await receiver.engine.syncNow();
      final snapshot = await receiver.page.send({'op': 'snapshot'});
      expect(
        [snapshot['field'], snapshot['dirty'], snapshot['pending']],
        ['pending-user', true, true],
      );
      expect(jsonEncode(receiver.baseline['records']), records);
      expect(receiver.uploaded, uploaded);
      expect(receiver.baseline['pendingLocalCommit'], isNull);
      expect(receiver.baseline['pendingApplyRetry'], true);
      await receiver.engine.syncNow();
      await source.page.navigate();
      await source.engine.syncNow();
      expect(await source.page.text(), 'pending-user');
      expect(receiver.engine.collectionEnabled('report-drafts'), true);
    },
  );
}
