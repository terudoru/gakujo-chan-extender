import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../secure_storage_transaction.dart';
import 'star_sync_config.dart';
import 'star_sync_google_auth.dart';
import 'star_sync_transport.dart';

const starSyncGoogleTokenKey = 'more_better_gakujo_star_sync_google_token';

// Google grants the `email` and `profile` scopes under their full URLs.
const _googleScopeAliases = {
  'https://www.googleapis.com/auth/userinfo.email': 'email',
  'https://www.googleapis.com/auth/userinfo.profile': 'profile',
};

class _DesktopAuthorization {
  _DesktopAuthorization({this.isFolderPicker = false});

  final bool isFolderPicker;
  final _cancelled = Completer<void>();
  HttpClient? client;

  static const _cancellation = StarSyncGoogleAuthException(
    StarSyncGoogleAuthErrorKind.cancelled,
  );

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    client?.close(force: true);
  }

  void checkCurrent() {
    if (isCancelled) throw _cancellation;
  }

  Future<T> waitForBrowser<T>(Future<T> result) => Future.any([
    result,
    _cancelled.future.then<T>((_) => throw _cancellation),
  ]).timeout(const Duration(minutes: 5));
}

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
  _DesktopAuthorization? _authorization;
  final _credentials = StorageOperationQueue();
  int _generation = 0;

  @override
  int get generation => _generation;

  void _checkRefresh(int generation, String refresh) {
    if (_generation != generation || _refreshToken != refresh) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.notSignedIn,
      );
    }
  }

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<bool> _openBrowser(Uri uri) async {
    try {
      if (await _launcher(uri)) return true;
    } on PlatformException {
      // The launcher can also report an unavailable browser via the platform.
    }
    throw const StarSyncGoogleAuthException(
      StarSyncGoogleAuthErrorKind.browserUnavailable,
      'Could not open browser',
    );
  }

  String _random() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, String> fields, {
    int? refreshGeneration,
    HttpClient? client,
  }) async {
    final requestClient = client ?? HttpClient();
    try {
      final response = await starSyncRequest(
        requestClient,
        'POST',
        uri,
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: utf8.encode(Uri(queryParameters: fields).query),
      );
      final decoded = response.bytes.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (decoded['error'] == 'invalid_grant' && refreshGeneration != null) {
          await _credentials.run(() async {
            _checkRefresh(refreshGeneration, fields['refresh_token']!);
            try {
              await storage.delete(key: starSyncGoogleTokenKey);
            } catch (_) {
              // The grant is revoked even if local deletion fails.
            } finally {
              _clear();
            }
          });
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
      if (client == null) requestClient.close(force: true);
    }
  }

  void _clear() {
    _generation++;
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
  Future<String?> restore({String? expectedEmail}) =>
      _credentials.run(_restore);

  Future<String?> _restore() async {
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
    final active = _authorization;
    if (active != null && !active.isFolderPicker) active.cancel();
  }

  @override
  void cancelPendingDriveFolderPick() {
    final active = _authorization;
    if (active == null || !active.isFolderPicker) return;
    // Picker grants never write login credentials. Allow a new selection
    // immediately while the cancelled attempt closes its own resources.
    _authorization = null;
    active.cancel();
  }

  @override
  Future<String> signIn({
    List<String> optionalScopes = const [],
    String? loginHint,
  }) => _authorize(
    starSyncGoogleScopes,
    optionalScopes: optionalScopes,
    loginHint: loginHint,
  );

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

  @override
  Future<String?> pickDriveFolder() async {
    final session = StarSyncGoogleAuthSession(this, email: currentEmail);
    try {
      final id = await _authorizeInBrowser(
        _DesktopAuthorization(isFolderPicker: true),
        parameters: {
          'scope': googleDriveFileScope,
          'prompt': 'consent',
          'access_type': 'online',
          'include_granted_scopes': 'false',
          'trigger_onepick': 'true',
          'allow_folder_selection': 'true',
          'mimetypes': 'application/vnd.google-apps.folder',
          'login_hint': ?session.email,
        },
        checkSession: session.checkCurrent,
        onGrant: _pickedFolderId,
      );
      session.checkCurrent();
      return id;
    } on StarSyncGoogleAuthException catch (error) {
      if (error.kind == StarSyncGoogleAuthErrorKind.cancelled) return null;
      rethrow;
    }
  }

  // Exchanging the code finalizes the grant. The caller checks the folder
  // with the signed-in session, so only the selected ID leaves this flow.
  String _pickedFolderId(
    Map<String, String> params,
    Map<String, dynamic> data,
  ) {
    final id = params['picked_file_ids'];
    final token = data['access_token'];
    if (id == null ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
        token is! String ||
        token.trim().isEmpty) {
      throw const FormatException();
    }
    // OAuth permits omitting scope when it is identical to the request.
    for (final scope in [params['scope'], data['scope']]) {
      if (scope != null && scope != googleDriveFileScope) {
        throw const StarSyncGoogleAuthException(
          StarSyncGoogleAuthErrorKind.permissionDenied,
        );
      }
    }
    return id;
  }

  Future<String> _authorize(
    List<String> scopes, {
    String? expectedEmail,
    List<String> optionalScopes = const [],
    String? loginHint,
  }) {
    final hint = expectedEmail ?? loginHint;
    final attempt = _DesktopAuthorization();
    return _authorizeInBrowser(
      attempt,
      parameters: {
        'scope': [...scopes, ...optionalScopes].join(' '),
        'access_type': 'offline',
        // Unbound sign-in must let the student correct the browser account.
        'prompt': hint == null ? 'select_account consent' : 'consent',
        'login_hint': ?hint,
      },
      onGrant: (_, data) =>
          _storeLoginGrant(data, scopes, expectedEmail, attempt),
    );
  }

  Future<String> _authorizeInBrowser(
    _DesktopAuthorization attempt, {
    required Map<String, String> parameters,
    void Function()? checkSession,
    required FutureOr<String> Function(
      Map<String, String> callback,
      Map<String, dynamic> data,
    )
    onGrant,
  }) async {
    if (_authorization != null) {
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
    _authorization = attempt;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      attempt.checkCurrent();
      checkSession?.call();
      final redirect = 'http://127.0.0.1:${server.port}';
      final pending = Completer<Map<String, String>>();
      server.listen((request) async {
        try {
          var params = const <String, String>{};
          var duplicateParams = false;
          try {
            final all = request.uri.queryParametersAll;
            duplicateParams = all.values.any((values) => values.length != 1);
            if (all['state']?.length == 1) params = request.uri.queryParameters;
          } on FormatException {
            // An unidentifiable request cannot settle this authorization.
          }
          final matching =
              request.method == 'GET' &&
              request.uri.path == '/' &&
              params['state'] == state;
          final valid =
              matching &&
              !duplicateParams &&
              !params.containsKey('error') &&
              params['code']?.isNotEmpty == true;
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
          try {
            await request.response.close();
          } finally {
            if (matching && !pending.isCompleted) {
              if (valid) {
                pending.complete(params);
              } else {
                pending.completeError(
                  StarSyncGoogleAuthException(
                    !duplicateParams && params['error'] == 'access_denied'
                        ? StarSyncGoogleAuthErrorKind.cancelled
                        : StarSyncGoogleAuthErrorKind.failed,
                  ),
                );
              }
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
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
          ...parameters,
        },
      );
      final results = await attempt.waitForBrowser(
        Future.wait<Object>([
          _openBrowser(uri),
          pending.future,
        ], eagerError: true),
      );
      final params = results[1] as Map<String, String>;
      await server.close(force: true);
      server = null;
      attempt.checkCurrent();
      checkSession?.call();
      final client = attempt.client = HttpClient();
      late final Map<String, dynamic> data;
      try {
        data = await _post(tokenEndpoint, {
          'code': params['code']!,
          'client_id': config.desktopClientId,
          'client_secret': config.desktopClientSecret,
          'redirect_uri': redirect,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
        }, client: client);
      } finally {
        attempt.checkCurrent();
      }
      checkSession?.call();
      final result = await onGrant(params, data);
      if (attempt.isFolderPicker) attempt.checkCurrent();
      return result;
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
      attempt.client?.close(force: true);
      try {
        if (server != null) await server.close(force: true);
      } finally {
        if (identical(_authorization, attempt)) _authorization = null;
      }
    }
  }

  Future<String> _storeLoginGrant(
    Map<String, dynamic> data,
    List<String> scopes,
    String? expectedEmail,
    _DesktopAuthorization attempt,
  ) async {
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
    if (expectedEmail != null &&
        !sameGoogleAccount(payload['email'] as String, expectedEmail)) {
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
    if (token is! String || token.isEmpty || expires is! num || expires <= 0) {
      throw const FormatException();
    }
    attempt.checkCurrent();
    try {
      await _credentials.run(() async {
        final previous = await storage.read(key: starSyncGoogleTokenKey);
        attempt.checkCurrent();
        await storage.write(
          key: starSyncGoogleTokenKey,
          value: jsonEncode({
            'refreshToken': refresh,
            'email': payload['email'],
            'scopes': granted.toList(),
          }),
        );
        if (attempt.isCancelled) {
          if (previous == null) {
            await storage.delete(key: starSyncGoogleTokenKey);
          } else {
            await storage.write(key: starSyncGoogleTokenKey, value: previous);
          }
          attempt.checkCurrent();
        }
        _generation++;
        _setAccess(data);
        _refreshToken = refresh;
        _email = payload['email'] as String;
        _scopes = granted;
      });
    } on PlatformException {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.storageUnavailable,
      );
    }
    return _email!;
  }

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    final refresh = _refreshToken;
    final generation = _generation;
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
    }, refreshGeneration: generation);
    _checkRefresh(generation, refresh);
    _setAccess(data);
    return _accessToken!;
  }

  @override
  Future<void> signOut() => _credentials.run(() async {
    _generation++;
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
  });
}
