import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Serializes a store's operations, including a group that calls its public APIs.
class StorageOperationQueue {
  Future<void> _pending = Future<void>.value();
  final Object _scopeKey = Object();

  bool get _ownsScope =>
      (Zone.current[_scopeKey] as _QueueLease?)?.active == true;

  Future<T> run<T>(Future<T> Function() operation) {
    if (_ownsScope) return Future<T>.sync(operation);
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<T> runExclusive<T>(Future<T> Function() operation) => run(() async {
        final lease = _QueueLease();
        try {
          return await runZoned(operation, zoneValues: {_scopeKey: lease});
        } finally {
          // Futures escaping the callback must queue normally after it ends.
          lease.active = false;
        }
      });
}

class _QueueLease {
  bool active = true;
}

class BackupStorageParticipant {
  const BackupStorageParticipant(this.queue, this.storage, this.keys);

  final StorageOperationQueue queue;
  final FlutterSecureStorage storage;
  final List<String> keys;
}

class BackupRollbackException implements Exception {
  const BackupRollbackException(this.cause, this.rollbackErrors);

  final Object cause;
  final List<Object> rollbackErrors;

  @override
  String toString() =>
      'Backup restore failed and some previous values could not be restored';
}

/// Acquires stores in the same order for both backup reads and restores.
Future<T> runWithBackupStorageLocks<T>(
  List<BackupStorageParticipant> participants,
  Future<T> Function() operation,
) {
  Future<T> acquire(int index) async {
    if (index < participants.length) {
      return participants[index].queue.runExclusive(() => acquire(index + 1));
    }
    return operation();
  }

  return acquire(0);
}

/// Holds all participating stores until either the import or its rollback ends.
/// This handles storage errors during a running import, not process termination.
Future<void> runBackupStorageTransaction(
  List<BackupStorageParticipant> participants,
  Future<void> Function() operation,
) =>
    runWithBackupStorageLocks(participants, () async {
      // Read exact raw values before any writes. Tolerant cache loaders can hide
      // read errors or discard expired data, so cannot provide a rollback image.
      final snapshots = <(FlutterSecureStorage, String, String?)>[];
      for (final participant in participants) {
        for (final key in participant.keys) {
          snapshots.add((
            participant.storage,
            key,
            await participant.storage.read(key: key)
          ));
        }
      }
      try {
        await operation();
      } on Object catch (error) {
        final rollbackErrors = <Object>[];
        for (final (storage, key, value) in snapshots.reversed) {
          try {
            if (value == null) {
              await storage.delete(key: key);
            } else {
              await storage.write(key: key, value: value);
            }
          } on Object catch (rollbackError) {
            rollbackErrors.add(rollbackError);
          }
        }
        if (rollbackErrors.isNotEmpty) {
          throw BackupRollbackException(
              error, List.unmodifiable(rollbackErrors));
        }
        rethrow;
      }
    });
