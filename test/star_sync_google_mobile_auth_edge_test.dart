import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_mobile_auth.dart';

class _FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  final requests = <AuthorizationRequestDetails>[];
  final calls = <String>[];
  String? token = 'token';
  Object? error;
  Object? promptError;
  bool denySilent = false;
  int lightweightCalls = 0;

  void reset() {
    requests.clear();
    calls.clear();
    token = 'token';
    error = null;
    promptError = null;
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
    if (request.promptIfUnauthorized && promptError != null) throw promptError!;
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
const _missing = GoogleSignInException(
  code: GoogleSignInExceptionCode.unknownError,
  description: '[28433] Cannot find a matching credential',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = _FakeGoogleSignInPlatform();
  const email = 'bound@example.com';
  late StarSyncGoogleMobileAuth auth;
  late bool reachable;
  setUpAll(() => GoogleSignInPlatform.instance = platform);
  setUp(() {
    platform.reset();
    reachable = true;
    auth = StarSyncGoogleMobileAuth(
      config: const StarSyncGoogleAuthConfig(),
      isAndroidOverride: true,
      isGoogleReachableOverride: () async => reachable,
    );
  });

  test('restore, signIn other account, accessToken uses new account', () async {
    await auth.restore(expectedEmail: email);
    expect(await auth.signIn(), 'new@example.com');
    platform.requests.clear();
    expect(await auth.accessToken(), 'token');
    expect(platform.requests.single.email, 'new@example.com');
    expect(auth.currentEmail, 'new@example.com');
  });

  test('signOut after signIn then accessToken says not signed in', () async {
    await auth.signIn();
    await auth.signOut();
    expect(auth.currentEmail, isNull);
    await expectLater(auth.accessToken(), throwsA(isA<StarSyncGoogleAuthException>()
        .having((e) => e.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn)));
  });

  test('signOut twice: second call after cleared state', () async {
    await auth.restore(expectedEmail: email);
    await auth.signOut();
    Object? second;
    try { await auth.signOut(); } catch (e) { second = e; }
    // documents behaviour: second call on Android with no account
    expect(second, anyOf(isNull, isA<StarSyncGoogleRevocationException>()));
  });

  test('signOut of a restored account that was removed from the device', () async {
    await auth.restore(expectedEmail: email);
    platform.error = _missing;
    // account already gone: nothing left to revoke, must not report failure
    await auth.signOut();
    expect(auth.currentEmail, isNull);
  });

  test('restore concurrent with accessToken leaves consistent state', () async {
    await auth.restore(expectedEmail: email);
    final t = auth.accessToken();
    final r = auth.restore(expectedEmail: email);
    await t; await r;
    expect(auth.currentEmail, email);
    expect(await auth.accessToken(), 'token');
  });

  test('restore(blank) concurrent with in-flight accessToken does not resurrect', () async {
    await auth.restore(expectedEmail: email);
    final t = auth.accessToken().catchError((_) => '');
    await auth.restore(expectedEmail: '');
    await t;
    expect(auth.currentEmail, isNull);
  });

  test('forceRefresh: missing account on first silent call', () async {
    await auth.restore(expectedEmail: email);
    platform.error = _missing;
    await expectLater(auth.accessToken(forceRefresh: true), throwsA(isA<StarSyncGoogleAuthException>()
        .having((e) => e.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn)));
    expect(auth.currentEmail, isNull);
  });

  test('forceRefresh: missing account after signIn clears signed-in account', () async {
    await auth.signIn();
    platform.error = _missing;
    await expectLater(auth.accessToken(forceRefresh: true), throwsA(isA<StarSyncGoogleAuthException>()
        .having((e) => e.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn)));
    expect(auth.currentEmail, isNull);
  });

  test('forceRefresh offline with no cached token reports network', () async {
    await auth.restore(expectedEmail: email);
    platform.denySilent = true;
    reachable = false;
    await expectLater(auth.accessToken(forceRefresh: true), throwsA(isA<StarSyncGoogleAuthException>()
        .having((e) => e.kind, 'kind', StarSyncGoogleAuthErrorKind.network)));
    expect(auth.currentEmail, email);
  });

  test('forceRefresh when silent now null and online => notSignedIn, email kept?', () async {
    await auth.restore(expectedEmail: email);
    platform.denySilent = true;
    await expectLater(auth.accessToken(forceRefresh: true), throwsA(isA<StarSyncGoogleAuthException>()
        .having((e) => e.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn)));
  });

  test('failed second signIn keeps first account usable', () async {
    await auth.signIn();
    platform.error = StateError('boom');
    await expectLater(auth.signIn(), throwsA(isA<StarSyncGoogleAuthException>()));
    platform.error = null;
    expect(auth.currentEmail, 'new@example.com');
    expect(await auth.accessToken(), 'token');
  });
}
