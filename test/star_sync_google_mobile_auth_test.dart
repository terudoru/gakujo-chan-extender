import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_mobile_auth.dart';

class _FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  final requests = <AuthorizationRequestDetails>[];
  final calls = <String>[];
  String? token = 'token';
  Object? error;
  bool denySilent = false;
  int lightweightCalls = 0;

  void reset() {
    requests.clear();
    calls.clear();
    token = 'token';
    error = null;
    denySilent = false;
    lightweightCalls = 0;
  }

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async {
    lightweightCalls++;
    return null;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
    calls.add('authenticate');
    return const AuthenticationResults(
      user: GoogleSignInUserData(email: 'new@example.com', id: 'new-id'),
      authenticationTokens: AuthenticationTokenData(idToken: null),
    );
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    final request = params.request;
    requests.add(request);
    calls.add(request.promptIfUnauthorized ? 'prompt' : 'silent');
    if (error != null) throw error!;
    if (denySilent && !request.promptIfUnauthorized) return null;
    final value = token;
    return value == null ? null : ClientAuthorizationTokenData(accessToken: value);
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<void> clearAuthorizationToken(ClearAuthorizationTokenParams params) async {
    calls.add('clear:${params.accessToken}');
  }

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {
    calls.add('disconnect');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = _FakeGoogleSignInPlatform();
  const email = 'bound@example.com';
  late StarSyncGoogleMobileAuth auth;

  setUpAll(() {
    GoogleSignInPlatform.instance = platform;
  });

  setUp(() {
    platform.reset();
    auth = StarSyncGoogleMobileAuth(
      config: const StarSyncGoogleAuthConfig(),
      isAndroidOverride: true,
    );
  });

  test('restore without a saved email does not attempt authentication', () async {
    expect(await auth.restore(), isNull);
    expect(await auth.restore(expectedEmail: '  '), isNull);
    expect(platform.lightweightCalls, 0);
    expect(platform.requests, isEmpty);
  });

  test('restore with a blank email clears a previously restored account', () async {
    await auth.restore(expectedEmail: email);
    platform.requests.clear();
    expect(await auth.restore(expectedEmail: '  '), isNull);
    expect(auth.currentEmail, isNull);
    expect(platform.requests, isEmpty);
    expect(platform.lightweightCalls, 0);
  });

  test('restore uses the saved email without prompting', () async {
    expect(await auth.restore(expectedEmail: email), email);
    expect(auth.currentEmail, email);
    expect(platform.lightweightCalls, 0);
    expect(platform.requests, hasLength(1));
    expect(platform.requests.single.email, email);
    expect(platform.requests.single.userId, isNull);
    expect(platform.requests.single.scopes, starSyncGoogleScopes);
    expect(platform.requests.single.promptIfUnauthorized, isFalse);
  });

  test('restore clears the account when no grant exists', () async {
    await auth.restore(expectedEmail: email);
    platform.token = null;
    expect(await auth.restore(expectedEmail: email), isNull);
    expect(auth.currentEmail, isNull);
    expect(platform.lightweightCalls, 0);
  });

  test('restore retains the email on failure and later reports the error', () async {
    platform.error = const GoogleSignInException(code: GoogleSignInExceptionCode.unknownError);
    expect(await auth.restore(expectedEmail: email), email);
    expect(auth.currentEmail, email);
    await expectLater(auth.accessToken(), throwsA(isA<StarSyncGoogleAuthException>()));
    expect(platform.lightweightCalls, 0);
  });

  test('restore also retains the email for other errors', () async {
    platform.error = StateError('offline');
    expect(await auth.restore(expectedEmail: email), email);
    expect(auth.currentEmail, email);
    await expectLater(auth.accessToken(), throwsA(isA<StarSyncGoogleAuthException>()));
  });

  test('accessToken remains bound and refresh clears the cached token first', () async {
    await auth.restore(expectedEmail: email);
    platform.calls.clear();
    platform.requests.clear();
    expect(await auth.accessToken(), 'token');
    platform.token = 'refreshed';
    expect(await auth.accessToken(forceRefresh: true), 'refreshed');
    expect(platform.calls, ['silent', 'clear:token', 'silent']);
    expect(platform.requests.every((request) =>
        request.email == email && !request.promptIfUnauthorized), isTrue);
  });

  test('accessToken reports notSignedIn when consent is gone', () async {
    await auth.restore(expectedEmail: email);
    platform.token = null;
    await expectLater(
      auth.accessToken(),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      )),
    );
  });

  test('scope checks are silent and scope requests can prompt', () async {
    await auth.restore(expectedEmail: email);
    platform.requests.clear();
    expect(await auth.hasScope(googleDriveFileScope), isTrue);
    expect(platform.requests.single.email, email);
    expect(platform.requests.single.scopes, [googleDriveFileScope]);
    expect(platform.requests.single.promptIfUnauthorized, isFalse);
    platform.requests.clear();
    platform.denySilent = true;
    await auth.requestScopes([googleDriveFileScope]);
    expect(platform.requests, hasLength(2));
    expect(platform.requests.map((request) => request.promptIfUnauthorized), [false, true]);
    expect(platform.requests.every((request) => request.email == email), isTrue);
    expect(platform.requests.last.scopes, contains(googleDriveFileScope));
  });

  test('scope operations handle a missing account or grant', () async {
    expect(await auth.hasScope(googleDriveFileScope), isFalse);
    await expectLater(
      auth.requestScopes([googleDriveFileScope]),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      )),
    );
    await auth.restore(expectedEmail: email);
    platform.token = null;
    expect(await auth.hasScope(googleDriveFileScope), isFalse);
    await expectLater(
      auth.requestScopes([googleDriveFileScope]),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      )),
    );
  });

  test('signOut silently caches the restored account before disconnect', () async {
    await auth.restore(expectedEmail: email);
    platform.calls.clear();
    platform.requests.clear();
    await auth.signOut();
    expect(platform.calls, ['silent', 'disconnect']);
    expect(platform.requests.single.email, email);
    expect(platform.requests.single.promptIfUnauthorized, isFalse);
    expect(auth.currentEmail, isNull);
  });

  test('signOut without an account reports an unconfirmed revocation', () async {
    await expectLater(auth.signOut(), throwsA(isA<StarSyncGoogleRevocationException>()));
    expect(platform.calls, isEmpty);
  });

  test('signOut without a grant clears state without disconnecting', () async {
    await auth.restore(expectedEmail: email);
    platform.calls.clear();
    platform.token = null;
    await auth.signOut();
    expect(platform.calls, ['silent']);
    expect(auth.currentEmail, isNull);
  });

  test('signOut reports a failed silent authorization as unconfirmed', () async {
    await auth.restore(expectedEmail: email);
    platform.calls.clear();
    platform.error = StateError('offline');
    await expectLater(auth.signOut(), throwsA(isA<StarSyncGoogleRevocationException>()));
    expect(platform.calls, ['silent']);
    expect(auth.currentEmail, isNull);
  });

  test('signIn replaces the restored email with the authenticated account', () async {
    await auth.restore(expectedEmail: email);
    platform.requests.clear();
    expect(await auth.signIn(), 'new@example.com');
    expect(auth.currentEmail, 'new@example.com');
    expect(platform.requests.single.email, 'new@example.com');
    expect(platform.requests.single.userId, 'new-id');
    platform.requests.clear();
    await auth.accessToken();
    expect(platform.requests.single.email, 'new@example.com');
    expect(platform.requests.single.userId, 'new-id');
  });
}
