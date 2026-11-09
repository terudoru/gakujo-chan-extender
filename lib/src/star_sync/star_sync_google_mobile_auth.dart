import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'star_sync_google_auth.dart';

class StarSyncGoogleMobileAuth implements StarSyncGoogleAuth {
  StarSyncGoogleMobileAuth({
    required this.config,
    @visibleForTesting bool? isAndroidOverride,
    @visibleForTesting Future<bool> Function()? isGoogleReachableOverride,
  }) : _isAndroid = isAndroidOverride ?? Platform.isAndroid,
       _isGoogleReachable = isGoogleReachableOverride ?? _lookupGoogle;
  final StarSyncGoogleAuthConfig config;
  final bool _isAndroid;
  final Future<bool> Function() _isGoogleReachable;
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

  static Future<bool> _lookupGoogle() async {
    try {
      final addresses = await InternetAddress.lookup('www.googleapis.com')
          .timeout(const Duration(seconds: 3));
      return addresses.isNotEmpty;
    } on Object {
      return false;
    }
  }

  bool _accountMissing(GoogleSignInException error) {
    final description = error.description ?? '';
    return _isAndroid && (description.contains('28433') ||
        description.contains('Cannot find a matching credential'));
  }

  void _clearAccount() {
    _restoredEmail = null;
    _account = null;
    _token = null;
  }

  Future<void> _throwIfOffline() async {
    if (_isAndroid && currentEmail != null && !await _isGoogleReachable()) {
      throw const StarSyncGoogleAuthException(StarSyncGoogleAuthErrorKind.network);
    }
  }

  Future<T> _guard<T>(Future<T> Function() action, {bool detectMissingAccount = false}) async {
    try {
      return await action();
    } on StarSyncGoogleAuthException {
      rethrow;
    } on GoogleSignInException catch (error) {
      if (detectMissingAccount && _accountMissing(error)) {
        _clearAccount();
        throw const StarSyncGoogleAuthException(StarSyncGoogleAuthErrorKind.notSignedIn);
      }
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
          if (!await _isGoogleReachable()) return _restoredEmail;
          _clearAccount();
          return null;
        }
        _token = authorization.accessToken;
      } on GoogleSignInException catch (error) {
        if (_accountMissing(error)) {
          _clearAccount();
          return null;
        }
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
      var token = _token;
      if (token == null) {
        token = (await _silentTokens(_scopes.toList()))?.accessToken;
        if (token == null) await _throwIfOffline();
      }
      if (token != null) {
        final client = _account?.authorizationClient ?? GoogleSignIn.instance.authorizationClient;
        await client.clearAuthorizationToken(accessToken: token);
      }
      _token = null;
    }
    final authorization = await _silentTokens(_scopes.toList());
    if (authorization == null) {
      await _throwIfOffline();
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
    return _token = authorization.accessToken;
  }, detectMissingAccount: true);

  @override
  Future<bool> hasScope(String scope) => _guard(() async {
    final authorization = await _silentTokens([scope]);
    if (authorization != null) {
      _scopes.add(scope);
    } else {
      await _throwIfOffline();
    }
    return authorization != null;
  }, detectMissingAccount: true);

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
  }, detectMissingAccount: true);

  @override
  Future<void> signOut() async {
    try {
      await _initialize();
      if (_account == null && _restoredEmail != null && _isAndroid) {
        GoogleSignInClientAuthorization? authorization;
        try {
          authorization = await _silentTokens(starSyncGoogleScopes);
        } on GoogleSignInException catch (error) {
          if (_accountMissing(error)) return;
          rethrow;
        }
        if (authorization == null) {
          if (!await _isGoogleReachable()) {
            throw const StarSyncGoogleRevocationException();
          }
          return;
        }
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
