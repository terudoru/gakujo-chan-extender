import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_mobile_auth.dart';

import 'support/fake_google_sign_in_platform.dart';

class _StartingGooglePlatform extends FakeGoogleSignInPlatform {
  int initializationAttempts = 0;

  @override
  Future<void> init(InitParameters params) async {
    if (++initializationAttempts == 1) {
      throw PlatformException(code: 'startup-unavailable');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the saved Google login can recover after SDK startup fails', () async {
    const email = 'saved@example.invalid';
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_google_signed_in_email': email,
    });
    final platform = _StartingGooglePlatform();
    GoogleSignInPlatform.instance = platform;
    final first = StarSyncGoogleMobileAuth(
      config: const StarSyncGoogleAuthConfig(),
      isAndroidOverride: true,
    );
    final second = StarSyncGoogleMobileAuth(
      config: const StarSyncGoogleAuthConfig(),
      isAndroidOverride: true,
    );
    final failed = throwsA(isA<StarSyncGoogleAuthException>());
    await Future.wait([
      expectLater(first.restore(), failed),
      expectLater(second.restore(), failed),
    ]);
    expect(platform.initializationAttempts, 1);
    expect(platform.requests, isEmpty);

    expect(await first.restore(), email);
    expect(await second.restore(), email);
    expect(platform.initializationAttempts, 2);
    expect(platform.requests.map((request) => request.email), [email, email]);
    expect(platform.requests.every((request) => !request.promptIfUnauthorized), isTrue);
  });
}
