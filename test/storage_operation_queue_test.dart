import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';

void main() {
  test('exclusive scope can await store operations without deadlocking',
      () async {
    final queue = StorageOperationQueue();
    final order = <int>[];
    await queue.runExclusive(() async {
      await queue.run(() async => order.add(1));
      await queue.runExclusive(() async {
        await queue.run(() async => order.add(2));
      });
      await queue.run(() async => order.add(3));
    }).timeout(const Duration(seconds: 2));
    expect(order, [1, 2, 3]);
  });

  test('work inheriting an expired scope does not bypass a later operation',
      () async {
    final queue = StorageOperationQueue();
    final releaseEscaped = Completer<void>();
    final releaseCurrent = Completer<void>();
    final currentStarted = Completer<void>();
    late Future<void> escaped;
    final order = <String>[];
    await queue.runExclusive(() async {
      escaped = releaseEscaped.future.then((_) => queue.run(() async {
            order.add('escaped');
          }));
    });
    final current = queue.run(() async {
      currentStarted.complete();
      await releaseCurrent.future;
      order.add('current');
    });
    await currentStarted.future;
    releaseEscaped.complete();
    await Future<void>.delayed(Duration.zero);
    expect(order, isEmpty);
    releaseCurrent.complete();
    await Future.wait([current, escaped]);
    expect(order, ['current', 'escaped']);
  });

  test('a failed exclusive operation releases the queue', () async {
    final queue = StorageOperationQueue();
    await expectLater(queue.runExclusive(() async {
      await queue.run<void>(() async => throw StateError('failed'));
    }), throwsStateError);
    expect(await queue.run(() async => 7), 7);
  });
}
