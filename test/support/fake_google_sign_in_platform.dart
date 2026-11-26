import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform {
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
