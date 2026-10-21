import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  const fallback = 'スケジュールページで再実行してください';

  test('calendar import explains an expired login', () {
    expect(
      gakujoCalendarSourceMissingMessage(
        GakujoPortalAuthState.login,
        fallback: fallback,
      ),
      contains('ログインが切れています'),
    );
    expect(
      gakujoCalendarSourceMissingMessage(
        GakujoPortalAuthState.twoFactor,
        fallback: fallback,
      ),
      contains('2段階認証'),
    );
  });

  test('calendar import keeps the page hint when logged in', () {
    for (final state in [
      GakujoPortalAuthState.authenticated,
      GakujoPortalAuthState.unknown,
    ]) {
      expect(
        gakujoCalendarSourceMissingMessage(state, fallback: fallback),
        fallback,
      );
    }
  });
}
