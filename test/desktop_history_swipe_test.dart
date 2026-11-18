import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  testWidgets('a vertical or diagonal scroll cannot acquire history in its tail',
      (tester) async {
    final tracker = DesktopHistorySwipeTracker();
    addTearDown(tracker.dispose);
    GakujoHistoryNavigation? scroll(double x, double y) => tracker.add(
      Offset(x, y), positiveIsBack: false, threshold: 120, dominance: 1.25);
    for (final initial in [const Offset(5, 30), const Offset(25, 25)]) {
      tracker.reset();
      expect(scroll(initial.dx, initial.dy), isNull);
      expect(scroll(-140, 0), isNull);
      await tester.pump(const Duration(milliseconds: 200));
      expect(scroll(-140, 0), isNull);
      await tester.pump(const Duration(milliseconds: 251));
      expect(scroll(-140, 0), GakujoHistoryNavigation.back);
    }
    tracker.dispose();
  });

  testWidgets('ownership changes and pinches discard partial travel and momentum',
      (tester) async {
    final tracker = DesktopHistorySwipeTracker();
    addTearDown(tracker.dispose);
    GakujoHistoryNavigation? scroll(double x) => tracker.add(
      Offset(x, 0), positiveIsBack: false, threshold: 120, dominance: 1.25);
    expect(scroll(-100), isNull);
    tracker.suppress();
    expect(scroll(-130), isNull);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(scroll(-130), isNull);
    }
    await tester.pump(const Duration(milliseconds: 251));
    expect(scroll(-30), isNull, reason: 'old partial travel was discarded');
    expect(scroll(-100), GakujoHistoryNavigation.back);
    tracker.dispose();
  });

  testWidgets(
    'one momentum stream moves once and a later gesture moves again',
    (tester) async {
      final tracker = DesktopHistorySwipeTracker();
      addTearDown(tracker.dispose);
      GakujoHistoryNavigation? scroll(double x, [double y = 0]) => tracker.add(
        Offset(x, y),
        positiveIsBack: false,
        threshold: 120,
        dominance: 1.25,
      );

      expect(scroll(-70), isNull);
      expect(scroll(-60), GakujoHistoryNavigation.back);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        expect(
          scroll(-150),
          isNull,
          reason: 'momentum is still the same swipe',
        );
      }
      await tester.pump(const Duration(milliseconds: 251));
      expect(scroll(130), GakujoHistoryNavigation.forward);
      await tester.pump(const Duration(milliseconds: 251));
      expect(
        scroll(20, 100),
        isNull,
        reason: 'vertical scrolling is not history',
      );
      tracker.dispose();
    },
  );
}
