import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'star_sync_google_auth.dart';
import 'star_sync_transport.dart';

const starSyncGoogleTokenKey = 'more_better_gakujo_star_sync_google_token';

// Google grants the `email` and `profile` scopes under their full URLs.
const _googleScopeAliases = {
  'https://www.googleapis.com/auth/userinfo.email': 'email',
  'https://www.googleapis.com/auth/userinfo.profile': 'profile',
};

class StarSyncGoogleDesktopAuth implements StarSyncGoogleAuth {
  StarSyncGoogleDesktopAuth({
    required this.config,
    required this.storage,
    Future<bool> Function(Uri)? launcher,
    Uri? authorizationEndpoint,
    Uri? tokenEndpoint,
    Uri? revokeEndpoint,
    DateTime Function()? clock,
  }) : _launcher = launcher ?? _launch,
       authorizationEndpoint =
           authorizationEndpoint ??
           Uri.parse('https://accounts.google.com/o/oauth2/v2/auth'),
       tokenEndpoint =
           tokenEndpoint ?? Uri.parse('https://oauth2.googleapis.com/token'),
       revokeEndpoint =
           revokeEndpoint ?? Uri.parse('https://oauth2.googleapis.com/revoke'),
       _clock = clock ?? DateTime.now {
    validateStarSyncEndpoint(this.authorizationEndpoint);
    validateStarSyncEndpoint(this.tokenEndpoint);
    validateStarSyncEndpoint(this.revokeEndpoint);
  }

  final StarSyncGoogleAuthConfig config;
  final FlutterSecureStorage storage;
  final Future<bool> Function(Uri) _launcher;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri revokeEndpoint;
  final DateTime Function() _clock;
  String? _refreshToken;
  String? _email;
  String? _accessToken;
  DateTime? _expiresAt;
  Set<String> _scopes = {};
  Completer<String>? _pendingAuthorization;
  bool _authorizationInProgress = false;
  bool _authorizationCancelled = false;

  void _throwIfAuthorizationCancelled() {
    if (_authorizationCancelled) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.cancelled,
      );
    }
  }

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
  String _random() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, String> fields, {
    bool clearOnInvalidGrant = true,
  }) async {
    final client = HttpClient();
    try {
      final response = await starSyncRequest(
        client,
        'POST',
        uri,
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: utf8.encode(Uri(queryParameters: fields).query),
      );
      final decoded = jsonDecode(utf8.decode(response.bytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (decoded['error'] == 'invalid_grant' && clearOnInvalidGrant) {
          try {
            await storage.delete(key: starSyncGoogleTokenKey);
          } catch (_) {
            // The grant is revoked even if local deletion fails.
          } finally {
            _clear();
          }
          throw const StarSyncGoogleAuthException(
            StarSyncGoogleAuthErrorKind.revoked,
          );
        }
        throw const StarSyncGoogleAuthException(
          StarSyncGoogleAuthErrorKind.failed,
        );
      }
      return decoded;
    } on StarSyncTransportException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.network,
      );
    } on FormatException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.failed,
      );
    } finally {
      client.close(force: true);
    }
  }

  void _clear() {
    _refreshToken = null;
    _email = null;
    _accessToken = null;
    _expiresAt = null;
    _scopes = {};
  }

  void _setAccess(Map<String, dynamic> data) {
    final token = data['access_token'];
    final expires = data['expires_in'];
    if (token is! String || token.isEmpty || expires is! num || expires <= 0) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.failed,
        'Invalid token response',
      );
    }
    _accessToken = token;
    _expiresAt = _clock().add(Duration(seconds: expires.toInt()));
  }

  @override
  String? get currentEmail => _email;

  @override
  Future<String?> restore() async {
    String? stored;
    try {
      stored = await storage.read(key: starSyncGoogleTokenKey);
    } on PlatformException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.storageUnavailable,
      );
    }
    if (stored == null) {
      _clear();
      return null;
    }
    try {
      final data = jsonDecode(stored);
      if (data is! Map ||
          data['refreshToken'] is! String ||
          (data['refreshToken'] as String).isEmpty ||
          data['email'] is! String ||
          (data['email'] as String).isEmpty) {
        throw const FormatException();
      }
      _clear();
      _refreshToken = data['refreshToken'] as String;
      _email = data['email'] as String;
      final scopes = data['scopes'];
      if (scopes != null &&
          (scopes is! List || scopes.any((scope) => scope is! String))) {
        _clear();
        throw const FormatException();
      }
      _scopes = scopes == null
          ? starSyncGoogleScopes.toSet()
          : (scopes as List).cast<String>().toSet();
      return _email;
    } on FormatException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.failed,
        'Invalid stored credentials',
      );
    }
  }

  @override
  void cancelPendingSignIn() {
    if (!_authorizationInProgress) return;
    _authorizationCancelled = true;
    final pending = _pendingAuthorization;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const StarSyncGoogleAuthException(
          StarSyncGoogleAuthErrorKind.cancelled,
        ),
      );
    }
  }

  @override
  Future<String> signIn() => _authorize(starSyncGoogleScopes);

  @override
  Future<bool> hasScope(String scope) async => _scopes.contains(scope);

  @override
  Future<void> requestScopes(List<String> scopes) async {
    if (_refreshToken == null || _email == null) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
    if (_scopes.containsAll(scopes)) return;
    await _authorize(
      {...starSyncGoogleScopes, ..._scopes, ...scopes}.toList(),
      expectedEmail: _email,
    );
  }

  Future<String> _authorize(
    List<String> scopes, {
    String? expectedEmail,
  }) async {
    if (_authorizationInProgress) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.failed,
        'Authorization already in progress',
      );
    }
    final verifier = _random();
    final state = _random();
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    HttpServer? server;
    Completer<String>? result;
    _authorizationInProgress = true;
    _authorizationCancelled = false;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _throwIfAuthorizationCancelled();
      final redirect = 'http://127.0.0.1:${server.port}';
      final pending = Completer<String>();
      result = pending;
      _pendingAuthorization = pending;
      server.listen((request) async {
        try {
          final params = request.uri.queryParameters;
          final matching = request.uri.path == '/' && params['state'] == state;
          final valid = matching && params['code']?.isNotEmpty == true;
          request.response.headers.contentType = ContentType(
            'text',
            'html',
            charset: 'utf-8',
          );
          request.response.statusCode = request.uri.path != '/'
              ? 404
              : valid
              ? 200
              : 400;
          request.response.write(
            valid
                ? '<!doctype html><meta charset="utf-8">接続しました。このタブを閉じてアプリに戻ってください。'
                : '<!doctype html><meta charset="utf-8">接続できませんでした。アプリに戻ってください。',
          );
          await request.response.close();
          if (matching && !pending.isCompleted) {
            if (valid) {
              pending.complete(params['code']!);
            } else {
              pending.completeError(
                StarSyncGoogleAuthException(
                  params['error'] == 'access_denied' && params['state'] == state
                      ? StarSyncGoogleAuthErrorKind.cancelled
                      : StarSyncGoogleAuthErrorKind.failed,
                ),
              );
            }
          }
        } on HttpException {
          // The browser may close the connection before receiving the page.
        } on SocketException {
          // The browser may close the connection before receiving the page.
        }
      });
      final uri = authorizationEndpoint.replace(
        queryParameters: {
          'client_id': config.desktopClientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': scopes.join(' '),
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );
      final results = await Future.wait<Object>([
        _launcher(uri).then((opened) {
          if (!opened) {
            throw const StarSyncGoogleAuthException(
              StarSyncGoogleAuthErrorKind.browserUnavailable,
              'Could not open browser',
            );
          }
          return opened;
        }),
        pending.future,
      ], eagerError: true).timeout(const Duration(minutes: 5));
      final code = results[1] as String;
      late final Map<String, dynamic> data;
      try {
        data = await _post(tokenEndpoint, {
          'code': code,
          'client_id': config.desktopClientId,
          'client_secret': config.desktopClientSecret,
          'redirect_uri': redirect,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
        }, clearOnInvalidGrant: false);
      } finally {
        _throwIfAuthorizationCancelled();
      }
      final refresh = data['refresh_token'];
      final idToken = data['id_token'];
      if (refresh is! String || refresh.isEmpty || idToken is! String) {
        throw const FormatException();
      }
      final parts = idToken.split('.');
      if (parts.length != 3) throw const FormatException();
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map ||
          payload['email'] is! String ||
          (payload['email'] as String).isEmpty) {
        throw const FormatException();
      }
      if (expectedEmail != null && payload['email'] != expectedEmail) {
        throw const StarSyncGoogleAuthException(
          StarSyncGoogleAuthErrorKind.failed,
          'account changed',
        );
      }
      final scopeField = data['scope'];
      if (expectedEmail != null && scopeField == null) {
        throw const FormatException();
      }
      if (scopeField != null && scopeField is! String) {
        throw const FormatException();
      }
      final granted = scopeField is String
          ? scopeField
                .split(' ')
                .where((s) => s.isNotEmpty)
                .map((s) => _googleScopeAliases[s] ?? s)
                .toSet()
          : scopes.map((s) => _googleScopeAliases[s] ?? s).toSet();
      final requested = scopes.map((s) => _googleScopeAliases[s] ?? s).toSet();
      if (!granted.containsAll(requested)) {
        throw const StarSyncGoogleAuthException(
          StarSyncGoogleAuthErrorKind.permissionDenied,
        );
      }
      final token = data['access_token'];
      final expires = data['expires_in'];
      if (token is! String ||
          token.isEmpty ||
          expires is! num ||
          expires <= 0) {
        throw const FormatException();
      }
      await server.close(force: true);
      server = null;
      _throwIfAuthorizationCancelled();
      try {
        final previous = await storage.read(key: starSyncGoogleTokenKey);
        _throwIfAuthorizationCancelled();
        await storage.write(
          key: starSyncGoogleTokenKey,
          value: jsonEncode({
            'refreshToken': refresh,
            'email': payload['email'],
            'scopes': granted.toList(),
          }),
        );
        if (_authorizationCancelled) {
          if (previous == null) {
            await storage.delete(key: starSyncGoogleTokenKey);
          } else {
            await storage.write(key: starSyncGoogleTokenKey, value: previous);
          }
          _throwIfAuthorizationCancelled();
        }
      } on PlatformException {
        throw const StarSyncGoogleAuthException(
          StarSyncGoogleAuthErrorKind.storageUnavailable,
        );
      }
      _setAccess(data);
      _refreshToken = refresh;
      _email = payload['email'] as String;
      _scopes = granted;
      return _email!;
    } on TimeoutException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.cancelled,
        'Sign-in timed out',
      );
    } on SocketException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.network,
      );
    } on FormatException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.failed,
        'Invalid identity response',
      );
    } finally {
      if (identical(_pendingAuthorization, result)) {
        _pendingAuthorization = null;
      }
      try {
        if (server != null) await server.close(force: true);
      } finally {
        _authorizationInProgress = false;
      }
    }
  }

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    final refresh = _refreshToken;
    if (refresh == null) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
    if (!forceRefresh &&
        _accessToken != null &&
        _expiresAt != null &&
        _clock().isBefore(_expiresAt!.subtract(const Duration(seconds: 60)))) {
      return _accessToken!;
    }
    final data = await _post(tokenEndpoint, {
      'client_id': config.desktopClientId,
      'client_secret': config.desktopClientSecret,
      'refresh_token': refresh,
      'grant_type': 'refresh_token',
    });
    _setAccess(data);
    return _accessToken!;
  }

  @override
  Future<void> signOut() async {
    var revocationFailed = false;
    var deleteFailed = false;
    try {
      var refresh = _refreshToken;
      if (refresh == null) {
        final stored = await storage.read(key: starSyncGoogleTokenKey);
        if (stored != null) {
          final data = jsonDecode(stored);
          if (data is! Map ||
              data['refreshToken'] is! String ||
              (data['refreshToken'] as String).isEmpty) {
            throw const FormatException('Invalid stored credentials');
          }
          refresh = data['refreshToken'] as String;
        }
      }
      if (refresh != null) await _post(revokeEndpoint, {'token': refresh});
    } catch (_) {
      revocationFailed = true;
    } finally {
      try {
        await storage.delete(key: starSyncGoogleTokenKey);
      } catch (_) {
        deleteFailed = true;
      } finally {
        _clear();
      }
    }
    if (deleteFailed) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.storageUnavailable,
      );
    }
    if (revocationFailed) throw const StarSyncGoogleRevocationException();
  }
}
