import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
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
