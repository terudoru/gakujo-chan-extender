import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  group('waitForResolvedGakujoAuthState', () {
    var elapsed = Duration.zero;
    var probes = 0;

    setUp(() {
      elapsed = Duration.zero;
      probes = 0;
    });

    Future<void> advance(Duration duration) async {
      elapsed += duration;
    }

    test('returns authenticated after unknown and stops', () async {
      final states = [
        GakujoPortalAuthState.unknown,
        GakujoPortalAuthState.unknown,
        GakujoPortalAuthState.authenticated,
        GakujoPortalAuthState.login,
      ];
      final result = await waitForResolvedGakujoAuthState(
        probe: (_) async => states[probes++],
        delay: advance,
        stillCurrent: () => true,
        elapsed: () => elapsed,
      );
      expect(result, GakujoPortalAuthState.authenticated);
      expect(probes, 3);
      expect(elapsed, const Duration(milliseconds: 1500));
    });

    test('stops at the deadline when state stays unknown', () async {
      final result = await waitForResolvedGakujoAuthState(
        probe: (_) async {
          probes++;
          return GakujoPortalAuthState.unknown;
        },
        delay: advance,
        stillCurrent: () => true,
        elapsed: () => elapsed,
      );
      expect(result, isNull);
      expect(probes, 29);
      expect(elapsed, const Duration(seconds: 15));
    });

    test('does not probe after the page changes during a wait', () async {
      var current = true;
      final result = await waitForResolvedGakujoAuthState(
        probe: (_) async {
          probes++;
          return GakujoPortalAuthState.unknown;
        },
        delay: (duration) async {
          await advance(duration);
          current = false;
        },
        stillCurrent: () => current,
        elapsed: () => elapsed,
      );
      expect(result, isNull);
      expect(probes, 0);
    });

    test('ignores a probe result after the page changes', () async {
      var current = true;
      final result = await waitForResolvedGakujoAuthState(
        probe: (valid) async {
          probes++;
          current = false;
          expect(valid(), isFalse);
          return GakujoPortalAuthState.authenticated;
        },
        delay: advance,
        stillCurrent: () => current,
        elapsed: () => elapsed,
      );
      expect(result, isNull);
      expect(probes, 1);
    });

    test('returns login on the first probe', () async {
      final result = await waitForResolvedGakujoAuthState(
        probe: (_) async {
          probes++;
          return GakujoPortalAuthState.login;
        },
        delay: advance,
        stillCurrent: () => true,
        elapsed: () => elapsed,
      );
      expect(result, GakujoPortalAuthState.login);
      expect(probes, 1);
    });
  });
}
