import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'star_sync_google_auth.dart';

class StarSyncGoogleMobileAuth implements StarSyncGoogleAuth {
  StarSyncGoogleMobileAuth({
    required this.config,
    @visibleForTesting bool? isAndroidOverride,
  }) : _isAndroid = isAndroidOverride ?? Platform.isAndroid;
  final StarSyncGoogleAuthConfig config;
  final bool _isAndroid;
  static Future<void>? _initialization;
  GoogleSignInAccount? _account;
  String? _restoredEmail;
  String? _token;
  final Set<String> _scopes = {...starSyncGoogleScopes};

  Future<void> _initialize() => _initialization ??= GoogleSignIn.instance
      .initialize(
        clientId: Platform.isIOS ? config.iosClientId : null,
        serverClientId: _isAndroid ? config.androidServerClientId : null,
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

  Future<GoogleSignInClientAuthorization?> _silentTokens(List<String> scopes) async {
    final account = _account;
    if (account != null) {
      return account.authorizationClient.authorizationForScopes(scopes);
    }
    final email = _restoredEmail;
    if (email == null) return null;
    final tokens = await GoogleSignInPlatform.instance.clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters(
        request: AuthorizationRequestDetails(
          scopes: scopes,
          userId: null,
          email: email,
          promptIfUnauthorized: false,
        ),
      ),
    );
    return tokens == null ? null : GoogleSignInClientAuthorization(accessToken: tokens.accessToken);
  }

  Future<GoogleSignInClientAuthorization?> _promptTokens(List<String> scopes) async {
    final account = _account;
    if (account != null) return account.authorizationClient.authorizeScopes(scopes);
    final email = _restoredEmail;
    if (email == null) return null;
    final tokens = await GoogleSignInPlatform.instance.clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters(
        request: AuthorizationRequestDetails(
          scopes: scopes,
          userId: null,
          email: email,
          promptIfUnauthorized: true,
        ),
      ),
    );
    return tokens == null ? null : GoogleSignInClientAuthorization(accessToken: tokens.accessToken);
  }

  @override
  String? get currentEmail => _account?.email ?? _restoredEmail;

  @override
  Future<String?> restore({String? expectedEmail}) => _guard(() async {
    await _initialize();
    if (_isAndroid) {
      _account = null;
      _restoredEmail = null;
      _token = null;
      _scopes
        ..clear()
        ..addAll(starSyncGoogleScopes);
      if (expectedEmail == null || expectedEmail.trim().isEmpty) return null;
      _restoredEmail = expectedEmail;
      try {
        final authorization = await _silentTokens(starSyncGoogleScopes);
        if (authorization == null) {
          _restoredEmail = null;
          return null;
        }
        _token = authorization.accessToken;
      } on Object {
        // Retain the email so a later token request can report the failure.
      }
      return _restoredEmail;
    }
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    _account = attempt == null ? null : await attempt;
    _restoredEmail = null;
    _token = null;
    _scopes
      ..clear()
      ..addAll(starSyncGoogleScopes);
    return _account?.email;
  });

  @override
  void cancelPendingSignIn() {}

  @override
  Future<String> signIn({
    List<String> optionalScopes = const [],
    String? loginHint,
  }) => _guard(() async {
    await _initialize();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: starSyncGoogleScopes,
    );
    final client = account.authorizationClient;
    final authorization =
        await client.authorizationForScopes(starSyncGoogleScopes) ??
        await client.authorizeScopes(starSyncGoogleScopes);
    // Keep the previous account until this one has been authorized.
    _account = account;
    _restoredEmail = null;
    _token = authorization.accessToken;
    _scopes
      ..clear()
      ..addAll(starSyncGoogleScopes);
    if (optionalScopes.isNotEmpty) {
      final scopes = {..._scopes, ...optionalScopes}.toList();
      try {
        final extended =
            await client.authorizationForScopes(scopes) ??
            await client.authorizeScopes(scopes);
        _token = extended.accessToken;
        _scopes.addAll(optionalScopes);
      } on Object {
        // Refusing an optional scope must not undo the sign-in.
      }
    }
    return account.email;
  });

  @override
  Future<String> accessToken({bool forceRefresh = false}) => _guard(() async {
    if (currentEmail == null) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
    if (forceRefresh) {
      final token =
          _token ??
          (await _silentTokens(_scopes.toList()))?.accessToken;
      if (token != null) {
        final client = _account?.authorizationClient ?? GoogleSignIn.instance.authorizationClient;
        await client.clearAuthorizationToken(accessToken: token);
      }
      _token = null;
    }
    final authorization = await _silentTokens(_scopes.toList());
    if (authorization == null) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
    return _token = authorization.accessToken;
  });

  @override
  Future<bool> hasScope(String scope) => _guard(() async {
    final authorization = await _silentTokens([scope]);
    if (authorization != null) _scopes.add(scope);
    return authorization != null;
  });

  @override
  Future<void> requestScopes(List<String> scopes) => _guard(() async {
    if (currentEmail == null) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
    final requested = {..._scopes, ...scopes}.toList();
    final authorization =
        await _silentTokens(requested) ?? await _promptTokens(requested);
    if (authorization == null) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
    _scopes.addAll(scopes);
    _token = authorization.accessToken;
  });

  @override
  Future<void> signOut() async {
    try {
      await _initialize();
      if (_account == null && _restoredEmail != null && _isAndroid) {
        if (await _silentTokens(starSyncGoogleScopes) == null) return;
        await GoogleSignIn.instance.disconnect();
        return;
      }
      if (_account == null) {
        if (_isAndroid) {
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
      _restoredEmail = null;
      _token = null;
    }
  }
}
