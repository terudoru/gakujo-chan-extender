import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';

class _Timer implements Timer {
  _Timer(this.callback);
  final void Function() callback;
  bool active = true;
  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
  @override
  void cancel() => active = false;
  void fire() {
    if (!active) return;
    active = false;
    callback();
  }
}

void main() {
  test('local collection changes and page loads use the correct triggers', () {
    final calls = <StarSyncTrigger>[];
    var allowed = true;
    final scheduler = GakujoCollectionSyncScheduler(
      canSync: () => allowed,
      schedule: (trigger, _) => calls.add(trigger),
    );
    scheduler.localChange(); // favorite
    scheduler.localChange(); // portable setting
    scheduler.pageLoaded();
    expect(calls, [
      StarSyncTrigger.localChange,
      StarSyncTrigger.localChange,
      StarSyncTrigger.resume,
    ]);
    allowed = false;
    scheduler.localChange();
    scheduler.pageLoaded();
    expect(calls, hasLength(3));
    scheduler.dispose();
  });

  test('draft changes coalesce into a single sync after 60 seconds', () {
    final calls = <(StarSyncTrigger, Duration)>[];
    final timers = <_Timer>[];
    final scheduler = GakujoCollectionSyncScheduler(
      canSync: () => true,
      schedule: (trigger, delay) => calls.add((trigger, delay)),
      timerFactory: (duration, callback) {
        expect(duration, const Duration(seconds: 60));
        final timer = _Timer(callback);
        timers.add(timer);
        return timer;
      },
    );
    expect(handleReportDraftSavedMessage('invalid', scheduler.draftChanged), isFalse);
    expect(handleReportDraftSavedMessage('{"type":"other"}', scheduler.draftChanged), isFalse);
    for (var i = 0; i < 3; i++) {
      expect(
        handleReportDraftSavedMessage(
          '{"type":"reportDraftSaved"}',
          scheduler.draftChanged,
        ),
        isTrue,
      );
    }
    for (final timer in timers) {
      timer.fire();
    }
    expect(calls, [(StarSyncTrigger.localChange, Duration.zero)]);
    scheduler.dispose();
  });
}
