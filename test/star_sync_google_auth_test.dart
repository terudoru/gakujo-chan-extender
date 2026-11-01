import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';

void main() {
  test('config stores the Android server client ID', () {
    const config = StarSyncGoogleAuthConfig(
      androidServerClientId: 'android-server-client',
    );

    expect(config.androidServerClientId, 'android-server-client');
  });
}
