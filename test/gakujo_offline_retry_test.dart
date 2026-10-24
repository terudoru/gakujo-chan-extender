import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_offline_retry.dart';

void main() {
  testWidgets('starts once and checks every five seconds', (tester) async {
    var probes = 0;
    final retry = GakujoOfflineRetry(
      probe: () async {
        probes += 1;
        return false;
      },
      onReachable: () => fail('offline'),
      now: tester.binding.clock.now,
    );
    addTearDown(retry.cancel);

    retry.start();
    await tester.pump(const Duration(seconds: 3));
    retry.start();
    expect(probes, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(probes, 1);
    retry.start();
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 2);
    expect(retry.isActive, isTrue);
    retry.cancel();
  });

  testWidgets('stops on success and reloads once', (tester) async {
    var online = false;
    var probes = 0;
    var reloads = 0;
    bool? activeDuringReload;
    late GakujoOfflineRetry retry;
    retry = GakujoOfflineRetry(
      probe: () async {
        probes += 1;
        return online;
      },
      onReachable: () {
        activeDuringReload = retry.isActive;
        reloads += 1;
      },
      now: tester.binding.clock.now,
    );
    addTearDown(retry.cancel);

    retry.start();
    await tester.pump(const Duration(seconds: 5));
    expect(reloads, 0);
    online = true;
    await tester.pump(const Duration(seconds: 5));
    expect(reloads, 1);
    expect(activeDuringReload, isFalse);
    expect(retry.isActive, isFalse);
    await tester.pump(const Duration(minutes: 11));
    expect(probes, 2);
    expect(reloads, 1);
  });

  testWidgets('gives up after ten minutes without extending on another start',
      (tester) async {
    var probes = 0;
    final retry = GakujoOfflineRetry(
      probe: () async {
        probes += 1;
        return false;
      },
      onReachable: () => fail('offline'),
      now: tester.binding.clock.now,
    );
    addTearDown(retry.cancel);

    retry.start();
    await tester.pump(const Duration(minutes: 9, seconds: 55));
    expect(retry.isActive, isTrue);
    expect(probes, greaterThan(0));
    final beforeDeadline = probes;
    retry.start();
    await tester.pump(const Duration(seconds: 5));
    expect(retry.isActive, isFalse);
    await tester.pump(const Duration(minutes: 1));
    expect(probes, beforeDeadline);
  });

  testWidgets('cancel stops checks and permits a fresh retry', (tester) async {
    var probes = 0;
    final retry = GakujoOfflineRetry(
      probe: () async {
        probes += 1;
        return false;
      },
      onReachable: () => fail('offline'),
      now: tester.binding.clock.now,
    );
    addTearDown(retry.cancel);

    retry.start();
    retry.cancel();
    retry.cancel();
    await tester.pump(const Duration(minutes: 11));
    expect(retry.isActive, isFalse);
    expect(probes, 0);
    retry.start();
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 1);
    retry.cancel();
  });

  testWidgets('a cancelled probe cannot reload a new navigation',
      (tester) async {
    final pending = Completer<bool>();
    var probes = 0;
    var reloads = 0;
    final retry = GakujoOfflineRetry(
      probe: () {
        probes += 1;
        return probes == 1 ? pending.future : Future.value(false);
      },
      onReachable: () => reloads += 1,
      now: tester.binding.clock.now,
    );
    addTearDown(retry.cancel);

    retry.start();
    await tester.pump(const Duration(seconds: 5));
    retry.cancel();
    retry.start();
    pending.complete(true);
    await tester.pump();
    expect(reloads, 0);
    expect(retry.isActive, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 2);
    expect(reloads, 0);
    retry.cancel();
  });

  testWidgets('does not overlap probes', (tester) async {
    final pending = Completer<bool>();
    var probes = 0;
    final retry = GakujoOfflineRetry(
      probe: () {
        probes += 1;
        return pending.future;
      },
      onReachable: () => fail('offline'),
      now: tester.binding.clock.now,
    );
    addTearDown(retry.cancel);

    retry.start();
    await tester.pump(const Duration(seconds: 15));
    expect(probes, 1);
    pending.complete(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 2);
    retry.cancel();
  });

  testWidgets('ignores a successful probe completed after the deadline',
      (tester) async {
    final pending = Completer<bool>();
    var reloads = 0;
    final retry = GakujoOfflineRetry(
      probe: () => pending.future,
      onReachable: () => reloads += 1,
      now: tester.binding.clock.now,
    );
    addTearDown(retry.cancel);

    retry.start();
    await tester.pump(const Duration(minutes: 10));
    expect(retry.isActive, isFalse);
    pending.complete(true);
    await tester.pump();
    expect(reloads, 0);
  });

  testWidgets('a delayed timer observes the wall-clock deadline',
      (tester) async {
    var now = DateTime(2026, 10, 24);
    var probes = 0;
    final retry = GakujoOfflineRetry(
      probe: () async {
        probes += 1;
        return true;
      },
      onReachable: () => fail('deadline has passed'),
      now: () => now,
    );
    addTearDown(retry.cancel);

    retry.start();
    now = now.add(const Duration(minutes: 11));
    await tester.pump(const Duration(seconds: 5));
    expect(retry.isActive, isFalse);
    expect(probes, 0);
  });

  testWidgets('a throwing probe leaves the next check active', (tester) async {
    var probes = 0;
    var reloads = 0;
    final retry = GakujoOfflineRetry(
      probe: () async {
        probes += 1;
        if (probes == 1) throw TimeoutException('lookup');
        return true;
      },
      onReachable: () => reloads += 1,
      now: tester.binding.clock.now,
    );
    addTearDown(retry.cancel);

    retry.start();
    await tester.pump(const Duration(seconds: 5));
    expect(retry.isActive, isTrue);
    expect(reloads, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(retry.isActive, isFalse);
    expect(reloads, 1);
  });
}
