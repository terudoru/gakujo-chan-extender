import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import 'star_sync_google_auth.dart';

class StarSyncGoogleMobileAuth implements StarSyncGoogleAuth {
  StarSyncGoogleMobileAuth({required this.config});
  final StarSyncGoogleAuthConfig config;
  static Future<void>? _initialization;
  GoogleSignInAccount? _account;
  String? _token;

  Future<void> _initialize() => _initialization ??= GoogleSignIn.instance
      .initialize(clientId: Platform.isIOS ? config.iosClientId : null);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on StarSyncGoogleAuthException {
      rethrow;
    } on GoogleSignInException catch (error) {
      final kind = error.code == GoogleSignInExceptionCode.canceled
          ? StarSyncGoogleAuthErrorKind.cancelled
          : StarSyncGoogleAuthErrorKind.failed;
      throw StarSyncGoogleAuthException(kind, error.description ?? '');
    } on SocketException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.network,
      );
    } catch (_) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.failed,
      );
    }
  }

  @override
  Future<String?> restore() => _guard(() async {
    await _initialize();
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    _account = attempt == null ? null : await attempt;
    _token = null;
    return _account?.email;
  });

  @override
  Future<String> signIn() => _guard(() async {
    await _initialize();
    _account = await GoogleSignIn.instance.authenticate(
      scopeHint: starSyncGoogleScopes,
    );
    _token = null;
    return _account!.email;
  });

  @override
  Future<String> accessToken({bool forceRefresh = false}) => _guard(() async {
    final account = _account;
    if (account == null) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
    final client = account.authorizationClient;
    if (forceRefresh) {
      final token =
          _token ??
          (await client.authorizationForScopes(starSyncGoogleScopes))
              ?.accessToken;
      if (token != null) {
        await client.clearAuthorizationToken(accessToken: token);
      }
      _token = null;
    }
    final authorization =
        await client.authorizationForScopes(starSyncGoogleScopes) ??
        await client.authorizeScopes(starSyncGoogleScopes);
    return _token = authorization.accessToken;
  });

  @override
  Future<void> signOut() => _guard(() async {
    await _initialize();
    if (_account != null) await GoogleSignIn.instance.disconnect();
    _account = null;
    _token = null;
  });
}
