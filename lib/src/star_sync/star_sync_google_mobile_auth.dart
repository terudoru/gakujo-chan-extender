import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import 'star_sync_google_auth.dart';

class StarSyncGoogleMobileAuth implements StarSyncGoogleAuth {
  StarSyncGoogleMobileAuth({required this.config});
  final StarSyncGoogleAuthConfig config;
  static Future<void>? _initialization;
  GoogleSignInAccount? _account;
  String? _token;
  final Set<String> _scopes = {...starSyncGoogleScopes};

  Future<void> _initialize() => _initialization ??= GoogleSignIn.instance
      .initialize(
        clientId: Platform.isIOS ? config.iosClientId : null,
        serverClientId: Platform.isAndroid ? config.androidServerClientId : null,
      );

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
  String? get currentEmail => _account?.email;

  @override
  Future<String?> restore() => _guard(() async {
    await _initialize();
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    _account = attempt == null ? null : await attempt;
    _token = null;
    _scopes
      ..clear()
      ..addAll(starSyncGoogleScopes);
    return _account?.email;
  });

  @override
  void cancelPendingSignIn() {}

  @override
  Future<String> signIn() => _guard(() async {
    await _initialize();
    _account = await GoogleSignIn.instance.authenticate(
      scopeHint: starSyncGoogleScopes,
    );
    _token = null;
    _scopes
      ..clear()
      ..addAll(starSyncGoogleScopes);
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
          (await client.authorizationForScopes(_scopes.toList()))?.accessToken;
      if (token != null) {
        await client.clearAuthorizationToken(accessToken: token);
      }
      _token = null;
    }
    final authorization =
        await client.authorizationForScopes(_scopes.toList()) ??
        await client.authorizeScopes(_scopes.toList());
    return _token = authorization.accessToken;
  });

  @override
  Future<bool> hasScope(String scope) => _guard(() async {
    final account = _account;
    if (account == null) return false;
    final authorization = await account.authorizationClient
        .authorizationForScopes([scope]);
    if (authorization != null) _scopes.add(scope);
    return authorization != null;
  });

  @override
  Future<void> requestScopes(List<String> scopes) => _guard(() async {
    final account = _account;
    if (account == null) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
    final requested = {..._scopes, ...scopes}.toList();
    final client = account.authorizationClient;
    final authorization =
        await client.authorizationForScopes(requested) ??
        await client.authorizeScopes(requested);
    _scopes.addAll(scopes);
    _token = authorization.accessToken;
  });

  @override
  Future<void> signOut() async {
    try {
      await _initialize();
      if (_account == null) {
        if (Platform.isAndroid) {
          // Android disconnect only revokes cached accounts; lightweight auth can show UI.
          throw const StarSyncGoogleRevocationException();
        }
        final attempt = GoogleSignIn.instance.attemptLightweightAuthentication(
          reportAllExceptions: true,
        );
        if (attempt == null) throw const StarSyncGoogleRevocationException();
        _account = await attempt;
      }
      if (_account != null) await GoogleSignIn.instance.disconnect();
    } on Object {
      throw const StarSyncGoogleRevocationException();
    } finally {
      _account = null;
      _token = null;
    }
  }
}
