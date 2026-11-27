import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/drive_planner_handoff.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_quota_meter.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_drive_transport.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

import 'support/fake_google_drive.dart';
import 'support/memory_secure_storage.dart';

class _GatedQuotaMeter extends StarSyncQuotaMeter {
  _GatedQuotaMeter() : super(storage: MemorySecureStorage());
  Future<void> Function()? beforeCharge;

  @override
  Future<void> charge(int units, {bool automatic = false}) async {
    await beforeCharge?.call();
    await super.charge(units, automatic: automatic);
  }
}

void main() {
  late StarSyncQuotaMeter meter;
  late FakeGoogleDrive drive;
  late StarSyncGoogleDriveTransport transport;

  setUp(() async {
    meter = StarSyncQuotaMeter(storage: MemorySecureStorage());
    drive = FakeGoogleDrive(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    transport = StarSyncGoogleDriveTransport(
      quotaMeter: meter,
      apiBase: drive.base,
      accessToken: ({bool forceRefresh = false}) async => 'token',
      delay: (_) async {},
    );
  });

  tearDown(() async {
    transport.close();
    await drive.server.close(force: true);
  });

  int uploadCount() => drive.counts.entries
      .where(
        (entry) =>
            entry.key.startsWith('POST /upload/') ||
            entry.key.startsWith('PATCH /upload/'),
      )
      .fold(0, (total, entry) => total + entry.value);

  test(
    'planner writes update the newest inspected file and retain other copies',
    () async {
      const name = drivePlannerHandoffName;
      final older = drive.add(name, [1], created: DateTime.utc(2020));
      final latest = drive.add(name, [2], created: DateTime.utc(2019))
        ..modified = DateTime.utc(2026);
      final outside = drive.add(name, [9], created: DateTime.utc(2027))
        ..spaces = ['drive'];
      final other = drive.add('mbg-planner-keep', [3]);
      final result = await transport.get(name);
      expect(result!.bytes, [2]);
      await transport.put(name, [4]);
      expect(
        drive.files
            .where((f) => f.name == name && f.spaces.contains('appDataFolder'))
            .map((file) => file.id),
        [older.id, latest.id],
      );
      expect(older.bytes, [1]);
      expect(drive.files.contains(outside), isTrue);
      expect(latest.bytes, [4]);
      expect(drive.files.contains(other), isTrue);
    },
  );

  for (final name in [drivePlannerHandoffName, drivePlannerTimetableName]) {
    test('planner retries a changed Drive revision by reading and merging again: $name', () async {
      final file = drive.add(name, [1]);
      final peer = StarSyncGoogleDriveTransport(
        quotaMeter: meter,
        apiBase: drive.base,
        accessToken: ({bool forceRefresh = false}) async => 'token',
      );
      addTearDown(peer.close);
      await transport.get(name);
      await peer.get(name);
      await peer.put(name, [1, 2]);
      final priorUploads = uploadCount();
      await expectLater(
        transport.put(name, [1, 4]),
        throwsA(isA<PlannerDriveConflict>()),
      );
      expect(uploadCount(), priorUploads);
      expect(file.bytes, [1, 2]);

      var attempts = 0;
      await retryPlannerDriveConflict(() async {
        final current = await transport.get(name);
        if (++attempts == 1) {
          await peer.get(name);
          await peer.put(name, [1, 2, 3]);
        }
        await transport.put(name, [...current!.bytes, 4]);
      });
      expect(attempts, 2);
      expect(file.bytes, [1, 2, 3, 4]);
    });
  }

  test('a planner create race keeps both uploaded copies', () async {
    const name = drivePlannerTimetableName;
    drive.afterUpload = () async {
      drive.add(name, [2]).modified = DateTime.utc(2027);
    };
    await expectLater(
      transport.put(name, [1], createOnly: true),
      throwsA(isA<PlannerDriveConflict>()),
    );
    expect(drive.files.map((file) => file.bytes), [[1], [2]]);
    expect((await transport.get(name))?.bytes, [2]);
    expect(drive.counts.keys.where((key) => key.startsWith('DELETE ')), isEmpty);
  });

  for (final reason in ['signed out', 'switch OFF', 'account changed']) {
    test('planner guard cancels after token wait: $reason', () async {
      var allowed = true;
      final guarded = StarSyncGoogleDriveTransport(
        quotaMeter: meter,
        apiBase: drive.base,
        checkCurrent: () {
          if (!allowed) throw StateError('cancelled');
        },
        accessToken: ({bool forceRefresh = false}) async {
          allowed = false;
          return 'token';
        },
      );
      try {
        await expectLater(
          guarded.put(drivePlannerHandoffName, [1], createOnly: true),
          throwsStateError,
        );
        expect(uploadCount(), 0);
      } finally {
        guarded.close();
      }
    });
  }

  for (final existing in [false, true]) {
    test(
      'automatic backup stops during write token wait, existing=$existing',
      () async {
        final storage = MemorySecureStorage();
        final entered = Completer<void>();
        final release = Completer<void>();
        var allowed = true;
        var holdNextToken = false;
        var now = DateTime.utc(2026, 11, 18);
        final engine = StarSyncEngine(
          activityStore: GakujoActivityStore(secureStorage: storage),
          secureStorage: storage,
          loginId: () => 'synthetic-login',
          canSync: () => false,
          canUploadAutomaticBackup: () => allowed,
          now: () => now,
          quotaMeter: meter,
          googleDriveTransport: () => StarSyncGoogleDriveTransport(
            quotaMeter: meter,
            apiBase: drive.base,
            accessToken: ({bool forceRefresh = false}) async {
              if (holdNextToken) {
                holdNextToken = false;
                entered.complete();
                await release.future;
              }
              return 'token';
            },
          ),
        );
        addTearDown(engine.dispose);
        await engine.setUpWithDrive(const StarSyncConfig());
        if (existing) await engine.uploadBackup([1]);
        final backup = drive.files
            .where((file) => file.name.startsWith('backups/'))
            .firstOrNull;
        final original = backup == null ? null : List<int>.of(backup.bytes);
        final previousTime = jsonDecode(
          storage.values[starSyncStateKey]!,
        )['lastBackupUploadAt'];
        now = now.add(const Duration(hours: 25));
        drive.beforeReadResponse = (file) {
          if (file.name == 'stars/keyring.json') holdNextToken = true;
        };
        final count = uploadCount();
        final pending = engine.uploadAutomaticBackupIfDue(() async => [2]);
        await entered.future;
        expect(uploadCount(), count);
        allowed = false;
        release.complete();
        expect(await pending, isFalse);
        expect(uploadCount(), count);
        expect(
          jsonDecode(storage.values[starSyncStateKey]!)['lastBackupUploadAt'],
          previousTime,
        );
        expect(
          jsonDecode(storage.values[starSyncStateKey]!)['lastError'],
          isNull,
        );
        if (existing) {
          expect(backup!.bytes, original);
        } else {
          expect(
            drive.files.where((file) => file.name.startsWith('backups/')),
            isEmpty,
          );
        }
      },
    );
  }

  for (final phase in ['token', 'quota', 'refresh', 'retry']) {
    for (final cancel in [false, true]) {
      test('guarded put after $phase wait, cancel=$cancel', () async {
        transport.close();
        final entered = Completer<void>();
        final release = Completer<void>();
        final gatedMeter = _GatedQuotaMeter();
        var armed = false;
        var allowed = true;
        final cancelled = StateError('cancelled by current policy');
        Future<void> hold() async {
          entered.complete();
          await release.future;
        }

        transport = StarSyncGoogleDriveTransport(
          quotaMeter: gatedMeter,
          apiBase: drive.base,
          accessToken: ({bool forceRefresh = false}) async {
            if (armed &&
                (phase == 'token' || phase == 'refresh' && forceRefresh)) {
              await hold();
            }
            return phase == 'refresh' && armed && !forceRefresh
                ? 'old'
                : 'token';
          },
          delay: (_) async {
            if (armed && phase == 'retry') await hold();
          },
        );
        final file = drive.add('backups/test', [1]);
        await transport.get(file.name);
        armed = true;
        if (phase == 'quota') gatedMeter.beforeCharge = hold;
        if (phase == 'refresh') drive.rejectOldToken = true;
        if (phase == 'retry') drive.failures = 1;
        final pending = transport.put(
          file.name,
          [2],
          beforeSend: () {
            if (!allowed) throw cancelled;
          },
        );
        final result = cancel
            ? expectLater(pending, throwsA(same(cancelled)))
            : pending;
        await entered.future;
        allowed = !cancel;
        release.complete();
        // Only one asynchronous boundary is held; later successful retries run normally.
        gatedMeter.beforeCharge = null;
        await result;
        final attempts = phase == 'refresh' || phase == 'retry' ? 1 : 0;
        expect(uploadCount(), attempts + (cancel ? 0 : 1));
        expect(file.bytes, cancel ? [1] : [2]);
      });
    }
  }

  test(
    'guarded accepted upload remains successful after policy changes',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var allowed = true;
      drive.afterUpload = () async {
        entered.complete();
        await release.future;
      };
      final pending = transport.put(
        'backups/test',
        [2],
        beforeSend: () {
          if (!allowed) throw StateError('cancelled');
        },
      );
      await entered.future;
      allowed = false;
      release.complete();
      await pending;
      expect(drive.files.single.bytes, [2]);
      expect(uploadCount(), 1);
    },
  );

  test('storage quota failure is distinct from authentication', () async {
    drive.failures = 1;
    drive.failureStatus = 403;
    drive.failureBody = jsonEncode({
      'error': {
        'errors': [
          {'reason': 'storageQuotaExceeded'},
        ],
      },
    });
    await expectLater(
      transport.list('stars'),
      throwsA(
        isA<StarSyncTransportException>().having(
          (error) => error.kind,
          'kind',
          StarSyncTransportErrorKind.storageFull,
        ),
      ),
    );
  });

  for (final (reason, kind) in [
    ('dailyLimitExceeded', StarSyncTransportErrorKind.server),
    ('domainPolicy', StarSyncTransportErrorKind.driveDisabled),
  ]) {
    test('$reason is not an authentication failure', () async {
      drive.failures = 1;
      drive.failureStatus = 403;
      drive.failureBody = jsonEncode({
        'error': {
          'errors': [
            {'reason': reason},
          ],
        },
      });
      await expectLater(
        transport.list('stars'),
        throwsA(
          isA<StarSyncTransportException>()
              .having((error) => error.kind, 'kind', kind)
              .having((error) => error.statusCode, 'statusCode', 403),
        ),
      );
    });
  }

  test('large object requires an increased response limit', () async {
    drive.add('backup/device', List.filled(5 * 1024 * 1024, 7));
    await expectLater(
      transport.get('backup/device'),
      throwsA(isA<StarSyncTransportException>()),
    );
    expect(
      (await transport.get(
        'backup/device',
        maxBytes: 32 * 1024 * 1024,
      ))!.bytes.length,
      5 * 1024 * 1024,
    );
  });

  test('create, update, get and delete', () async {
    await transport.ensureDirectory('stars/devices');
    await transport.put('stars/devices/a', [0, 255, 1]);
    expect((await transport.get('stars/devices/a'))!.bytes, [0, 255, 1]);
    await transport.put('stars/devices/a', [2, 3]);
    expect((await transport.get('stars/devices/a'))!.bytes, [2, 3]);
    expect((await transport.get('stars/devices/a'))!.etag, '1:2');
    await transport.delete('stars/devices/a');
    expect(await transport.get('stars/devices/a'), isNull);
    await transport.delete('stars/devices/a');
    expect(drive.counts['POST /upload/drive/v3/files'], 1);
    expect(drive.counts['PATCH /upload/drive/v3/files/1'], 1);
  });

  test(
    'paginates, filters direct children and chooses oldest duplicate',
    () async {
      drive.pageSize = 2;
      drive.add('stars/devices/a', [1], created: DateTime.utc(2025));
      drive.add('stars/devices/a', [2], created: DateTime.utc(2024));
      drive.add('stars/devices/b', [3]);
      drive.add('stars/devices/sub/c', [4]);
      drive.add('stars/devices2/x', [5]);
      final entries = await transport.list('stars/devices');
      expect(entries.map((e) => e.path).toSet(), {
        'stars/devices/a',
        'stars/devices/b',
      });
      expect((await transport.get('stars/devices/a'))!.bytes, [2]);
      expect(drive.counts['GET /drive/v3/files'], 3);
      await transport.delete('stars/devices/a');
      expect(drive.files.where((f) => f.name == 'stars/devices/a'), isEmpty);
    },
  );

  test('shares one listing across reads and writes', () async {
    drive.add('stars/keyring.json', [1]);
    drive.add('stars/devices/other', [2]);
    final own = drive.add('stars/devices/own', [3]);
    await transport.list('stars');
    await transport.list('stars/devices');
    await transport.get('stars/keyring.json');
    await transport.get('stars/devices/other');
    await transport.put('stars/devices/own', [4]);
    expect((await transport.get('stars/devices/own'))!.etag, '${own.id}:2');
    expect(own.bytes, [4]);
    expect(drive.counts['GET /drive/v3/files'], 1);
  });

  test('createOnly refreshes the listing for duplicate detection', () async {
    await transport.list('stars');
    drive.add('stars/keyring.json', [1]);
    await expectLater(
      transport.put('stars/keyring.json', [2], createOnly: true),
      throwsA(isA<StarSyncTransportException>()),
    );
    expect(drive.counts['GET /drive/v3/files'], 2);
    expect(await meter.currentUsage(), 200);
  });

  test('createOnly rejects an existing file without uploading', () async {
    drive.add('stars/keyring.json', [1]);
    await expectLater(
      transport.put('stars/keyring.json', [2], createOnly: true),
      throwsA(
        isA<StarSyncTransportException>().having(
          (e) => e.kind,
          'kind',
          StarSyncTransportErrorKind.alreadyExists,
        ),
      ),
    );
    expect(drive.counts['POST /upload/drive/v3/files'], isNull);
  });

  test('createOnly removes its own file after a duplicate race', () async {
    drive.insertRace = true;
    await expectLater(
      transport.put('stars/keyring.json', [2], createOnly: true),
      throwsA(
        isA<StarSyncTransportException>().having(
          (e) => e.kind,
          'kind',
          StarSyncTransportErrorKind.alreadyExists,
        ),
      ),
    );
    expect(drive.files.single.bytes, [99]);
    expect(drive.counts['DELETE /drive/v3/files/1'], 1);
  });

  test('refreshes the token once after 401', () async {
    transport.close();
    drive.rejectOldToken = true;
    var refreshes = 0;
    transport = StarSyncGoogleDriveTransport(
      quotaMeter: meter,
      apiBase: drive.base,
      accessToken: ({bool forceRefresh = false}) async {
        if (forceRefresh) refreshes++;
        return forceRefresh ? 'fresh' : 'old';
      },
    );
    expect(await transport.list('stars'), isEmpty);
    expect(refreshes, 1);
    expect(drive.counts['GET /drive/v3/files'], 2);
    expect(await meter.currentUsage(), 200);
  });

  test('retries 429 with exponential delays', () async {
    transport.close();
    drive.failures = 3;
    final delays = <Duration>[];
    transport = StarSyncGoogleDriveTransport(
      quotaMeter: meter,
      apiBase: drive.base,
      accessToken: ({bool forceRefresh = false}) async => 'token',
      delay: (duration) async => delays.add(duration),
      random: Random(42),
    );
    expect(await transport.list('stars'), isEmpty);
    expect(await meter.currentUsage(), 400);
    final random = Random(42);
    expect(delays, [
      for (final seconds in [1, 2, 4])
        Duration(seconds: seconds, milliseconds: random.nextInt(1001)),
    ]);
  });

  test('allows requests up to the hard limit', () async {
    await meter.charge(starSyncGoogleHardLimit - 100);
    expect(await transport.list('stars'), isEmpty);
    expect(await meter.currentUsage(), starSyncGoogleHardLimit);
    await expectLater(
      transport.put('stars/device', [1]),
      throwsA(isA<StarSyncQuotaExceeded>()),
    );
    expect(drive.counts['GET /drive/v3/files'], 1);
    expect(drive.counts['POST /upload/drive/v3/files'], isNull);
  });

  test('stops before sending a request that crosses the hard limit', () async {
    await meter.charge(starSyncGoogleHardLimit - 50);
    await expectLater(
      transport.list('stars'),
      throwsA(isA<StarSyncQuotaExceeded>()),
    );
    expect(drive.counts, isEmpty);
    expect(await meter.currentUsage(), starSyncGoogleHardLimit - 50);
  });

  test('automatic requests stop at the soft limit mid-operation', () async {
    transport.automatic = true;
    await meter.charge(starSyncGoogleSoftLimit - 100);
    expect(await transport.list('stars'), isEmpty);
    await expectLater(
      transport.put('stars/device', [1]),
      throwsA(isA<StarSyncQuotaExceeded>()),
    );
    expect(drive.counts['POST /upload/drive/v3/files'], isNull);
    expect(await meter.currentUsage(), starSyncGoogleSoftLimit);
  });

  test('plain 403 is an auth error', () async {
    drive.failures = 1;
    drive.failureStatus = 403;
    await expectLater(
      transport.list('stars'),
      throwsA(
        isA<StarSyncTransportException>().having(
          (e) => e.kind,
          'kind',
          StarSyncTransportErrorKind.auth,
        ),
      ),
    );
    expect(drive.counts['GET /drive/v3/files'], 1);
  });

  test('rate-limited 403 exhausts retries as a server error', () async {
    drive.failures = 4;
    drive.failureStatus = 403;
    drive.failureBody = jsonEncode({
      'error': {
        'errors': [
          {'reason': 'userRateLimitExceeded'},
        ],
      },
    });
    await expectLater(
      transport.list('stars'),
      throwsA(
        isA<StarSyncTransportException>().having(
          (e) => e.kind,
          'kind',
          StarSyncTransportErrorKind.server,
        ),
      ),
    );
    expect(drive.counts['GET /drive/v3/files'], 4);
  });
}
