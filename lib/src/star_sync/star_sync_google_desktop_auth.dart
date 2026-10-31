import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'star_sync_google_auth.dart';
import 'star_sync_transport.dart';

const starSyncGoogleTokenKey = 'more_better_gakujo_star_sync_google_token';

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
    Map<String, String> fields,
  ) async {
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
        if (decoded['error'] == 'invalid_grant') {
          await storage.delete(key: starSyncGoogleTokenKey);
          _clear();
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
  Future<String?> restore() async {
    final stored = await storage.read(key: starSyncGoogleTokenKey);
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
      return _email;
    } on FormatException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.failed,
        'Invalid stored credentials',
      );
    }
  }

  @override
  Future<String> signIn() async {
    final verifier = _random();
    final state = _random();
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirect = 'http://127.0.0.1:${server.port}';
      final result = Completer<String>();
      server.listen((request) async {
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
            : valid ? 200 : 400;
        request.response.write(
          valid
              ? '<!doctype html><meta charset="utf-8">接続しました。このタブを閉じてアプリに戻ってください。'
              : '<!doctype html><meta charset="utf-8">接続できませんでした。アプリに戻ってください。',
        );
        await request.response.close();
        if (matching && !result.isCompleted) {
          if (valid) {
            result.complete(params['code']!);
          } else {
            result.completeError(
              StarSyncGoogleAuthException(
                params['error'] == 'access_denied' && params['state'] == state
                    ? StarSyncGoogleAuthErrorKind.cancelled
                    : StarSyncGoogleAuthErrorKind.failed,
              ),
            );
          }
        }
      });
      final uri = authorizationEndpoint.replace(
        queryParameters: {
          'client_id': config.desktopClientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': starSyncGoogleScopes.join(' '),
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
              StarSyncGoogleAuthErrorKind.failed,
              'Could not open browser',
            );
          }
          return opened;
        }),
        result.future,
      ], eagerError: true).timeout(const Duration(minutes: 5));
      final code = results[1] as String;
      final data = await _post(tokenEndpoint, {
        'code': code,
        'client_id': config.desktopClientId,
        'client_secret': config.desktopClientSecret,
        'redirect_uri': redirect,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
      });
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
      _setAccess(data);
      await storage.write(
        key: starSyncGoogleTokenKey,
        value: jsonEncode({'refreshToken': refresh, 'email': payload['email']}),
      );
      _refreshToken = refresh;
      _email = payload['email'] as String;
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
      await server?.close(force: true);
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
    final refresh = _refreshToken;
    try {
      if (refresh != null) await _post(revokeEndpoint, {'token': refresh});
    } catch (_) {
      // Local sign-out must succeed even if revocation is offline.
    } finally {
      _clear();
      await storage.delete(key: starSyncGoogleTokenKey);
    }
  }
}
