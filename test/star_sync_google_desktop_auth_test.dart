import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_desktop_auth.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  late HttpServer server;
  late Uri endpoint;
  late _Storage storage;
  late DateTime now;
  var refreshes = 0;
  var revoked = false;
  var strayRequests = false;
  String? verifier;
  String? challenge;

  setUp(() async {
    storage = _Storage();
    now = DateTime.utc(2026);
    refreshes = 0;
    revoked = false;
    strayRequests = false;
    verifier = null;
    challenge = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final fields = Uri.splitQueryString(body);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/revoke') {
        request.response.write('{}');
      } else if (fields['grant_type'] == 'refresh_token') {
        refreshes++;
        if (revoked) {
          request.response.statusCode = 400;
          request.response.write(jsonEncode({'error': 'invalid_grant'}));
        } else {
          request.response.write(
            jsonEncode({
              'access_token': 'refresh$refreshes',
              'expires_in': 3600,
            }),
          );
        }
      } else {
        verifier = fields['code_verifier'];
        expect(fields['client_secret'], 'secret');
        expect(fields['code'], 'test-code');
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({'email': 'user@example.com'})))
            .replaceAll('=', '');
        request.response.write(
          jsonEncode({
            'access_token': 'initial',
            'expires_in': 3600,
            'refresh_token': 'refresh-secret',
            'id_token': 'header.$payload.signature',
          }),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  StarSyncGoogleDesktopAuth makeAuth() => StarSyncGoogleDesktopAuth(
    config: const StarSyncGoogleAuthConfig(
      desktopClientId: 'client',
      desktopClientSecret: 'secret',
    ),
    storage: storage,
    authorizationEndpoint: endpoint.resolve('/auth'),
    tokenEndpoint: endpoint.resolve('/token'),
    revokeEndpoint: endpoint.resolve('/revoke'),
    clock: () => now,
    launcher: (url) async {
      final p = url.queryParameters;
      expect(p['client_id'], 'client');
      expect(p['response_type'], 'code');
      expect(p['scope'], starSyncGoogleScopes.join(' '));
      expect(p['code_challenge_method'], 'S256');
      expect(p['access_type'], 'offline');
      expect(p['prompt'], 'consent');
      expect(p['state'], isNotEmpty);
      challenge = p['code_challenge'];
      final redirect = Uri.parse(
        p['redirect_uri']!,
      ).replace(queryParameters: {'code': 'test-code', 'state': p['state']!});
      final client = HttpClient();
      try {
        if (strayRequests) {
          final wrong = redirect.replace(
            queryParameters: {'state': 'wrong', 'code': 'test-code'},
          );
          final favicon = redirect.replace(path: '/favicon.ico');
          for (final uri in [wrong, favicon]) {
            final response = await (await client.getUrl(uri)).close();
            expect(response.statusCode, uri == wrong ? 400 : 404);
            await response.drain<void>();
          }
        }
        final response = await (await client.getUrl(redirect)).close();
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
      return true;
    },
  );

  test('sign in stores refresh token and parses email', () async {
    final auth = makeAuth();
    expect(await auth.signIn(), 'user@example.com');
    expect(jsonDecode(storage.values[starSyncGoogleTokenKey]!), {
      'refreshToken': 'refresh-secret',
      'email': 'user@example.com',
    });
    expect(verifier, isNotEmpty);
    expect(
      challenge,
      base64Url
          .encode(sha256.convert(ascii.encode(verifier!)).bytes)
          .replaceAll('=', ''),
    );
    expect(await auth.accessToken(), 'initial');
  });

  test('stray requests do not abort sign in', () async {
    strayRequests = true;
    expect(await makeAuth().signIn(), 'user@example.com');
  });

  test('refreshes 60 seconds before expiry and on demand', () async {
    final auth = makeAuth();
    await auth.signIn();
    now = now.add(const Duration(seconds: 3540));
    expect(await auth.accessToken(), 'refresh1');
    expect(await auth.accessToken(), 'refresh1');
    expect(await auth.accessToken(forceRefresh: true), 'refresh2');
  });

  test('invalid grant removes credentials', () async {
    final auth = makeAuth();
    await auth.signIn();
    revoked = true;
    await expectLater(
      auth.accessToken(forceRefresh: true),
      throwsA(
        isA<StarSyncGoogleAuthException>().having(
          (e) => e.kind,
          'kind',
          StarSyncGoogleAuthErrorKind.revoked,
        ),
      ),
    );
    expect(storage.values, isEmpty);
  });

  test('sign out deletes credentials', () async {
    final auth = makeAuth();
    await auth.signIn();
    await auth.signOut();
    expect(storage.values, isEmpty);
  });

  test('restore uses persisted refresh token', () async {
    await makeAuth().signIn();
    final auth = makeAuth();
    expect(await auth.restore(), 'user@example.com');
    expect(await auth.accessToken(), 'refresh1');
  });
}
