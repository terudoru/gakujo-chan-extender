import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_desktop_auth.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failRead) throw PlatformException(code: 'KeyringLocked');
    return values[key];
  }

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
    if (failWrite) throw PlatformException(code: 'KeyringLocked');
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
    if (failDelete) throw PlatformException(code: 'KeyringLocked');
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
  var revokeFails = false;
  String? revokedToken;
  var strayRequests = false;
  var malformedQuery = false;
  String? verifier;
  String? challenge;
  var incremental = false;
  Map<String, String>? lastAuthParams;
  var changedAccount = false;
  var omitScope = false;
  Completer<void>? tokenStarted;
  Completer<void>? tokenContinue;
  Completer<void>? refreshStarted;
  Completer<void>? refreshContinue;
  late Future<void> Function(HttpRequest, Map<String, String>) pickerRequest;

  setUp(() async {
    storage = _Storage();
    now = DateTime.utc(2026);
    refreshes = 0;
    revoked = false;
    revokeFails = false;
    revokedToken = null;
    strayRequests = false;
    malformedQuery = false;
    verifier = null;
    challenge = null;
    incremental = false;
    changedAccount = false;
    omitScope = false;
    tokenStarted = null;
    tokenContinue = null;
    refreshStarted = null;
    refreshContinue = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final fields = Uri.splitQueryString(body);
      request.response.headers.contentType = ContentType.json;
      if (fields['code'] == 'picker-code') {
        await pickerRequest(request, fields);
      } else if (request.uri.path == '/revoke') {
        revokedToken = fields['token'];
        if (revokeFails) {
          request.response.statusCode = 500;
          request.response.write('{}');
        }
      } else if (fields['grant_type'] == 'refresh_token') {
        refreshes++;
        expect(
          fields['refresh_token'],
          incremental ? 'new-refresh-secret' : 'refresh-secret',
        );
        final wasRevoked = revoked;
        refreshStarted?.complete();
        if (refreshContinue != null) await refreshContinue!.future;
        if (wasRevoked) {
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
        tokenStarted?.complete();
        if (tokenContinue != null) await tokenContinue!.future;
        verifier = fields['code_verifier'];
        expect(fields['client_secret'], 'secret');
        expect(fields['code'], 'test-code');
        final payload = base64Url
            .encode(
              utf8.encode(
                jsonEncode({
                  'email': changedAccount
                      ? 'other@example.com'
                      : 'user@example.com',
                }),
              ),
            )
            .replaceAll('=', '');
        request.response.write(
          jsonEncode({
            'access_token': 'initial',
            'expires_in': 3600,
            'refresh_token': incremental
                ? 'new-refresh-secret'
                : 'refresh-secret',
            // Google returns `email` as its full URL.
            'scope': [
              for (final scope in starSyncGoogleScopes)
                if (!omitScope || scope != 'email')
                  scope == 'email'
                      ? 'https://www.googleapis.com/auth/userinfo.email'
                      : scope,
              if (incremental) googleDriveFileScope,
            ].join(' '),
            'id_token': 'header.$payload.signature',
          }),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  StarSyncGoogleDesktopAuth makeAuth({
    Future<bool> Function(Uri)? pickerLauncher,
  }) => StarSyncGoogleDesktopAuth(
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
      if (p.containsKey('trigger_onepick')) return pickerLauncher!(url);
      expect(p['client_id'], 'client');
      expect(p['response_type'], 'code');
      expect(
        p['scope']!.split(' '),
        containsAll([
          ...starSyncGoogleScopes,
          if (incremental) googleDriveFileScope,
        ]),
      );
      expect(p.containsKey('include_granted_scopes'), isFalse);
      expect(p['code_challenge_method'], 'S256');
      expect(p['access_type'], 'offline');
      lastAuthParams = p;
      expect(
        p['prompt'],
        p['login_hint'] == null ? 'select_account consent' : 'consent',
      );
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
        if (malformedQuery) {
          final malformed = redirect.replace(query: 'state=%FF');
          final response = await (await client.getUrl(malformed)).close();
          expect(response.statusCode, 400);
          expect(response.headers.contentType?.mimeType, 'text/html');
          expect(
            await utf8.decoder.bind(response).join(),
            contains('接続できませんでした。アプリに戻ってください。'),
          );
        }
        final response = await (await client.getUrl(redirect)).close();
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
      return true;
    },
  );

  test('an optional scope that is not granted does not fail sign-in', () async {
    final auth = makeAuth();
    expect(
      await auth.signIn(optionalScopes: const [googleDriveFileScope]),
      isNotEmpty,
    );
    expect(await auth.hasScope(googleDriveFileScope), isFalse);
  });

  test('sign-in lets the student choose an account', () async {
    await makeAuth().signIn();
    expect(lastAuthParams!['prompt'], 'select_account consent');
    expect(lastAuthParams!.containsKey('login_hint'), isFalse);
  });

  test('a bound re-login preselects the only account it accepts', () async {
    await makeAuth().signIn(loginHint: 'bound@example.test');
    expect(lastAuthParams!['prompt'], 'consent');
    expect(lastAuthParams!['login_hint'], 'bound@example.test');
  });

  group('desktop OnePick', () {
    late Map<String, String> callback;
    late Map<String, Object?> token;
    late List<Uri> launches;
    late int exchanges;
    late int tokenStatus;

    Matcher failsWith(StarSyncGoogleAuthErrorKind kind) => throwsA(
      isA<StarSyncGoogleAuthException>().having((e) => e.kind, 'kind', kind),
    );

    Future<int> sendCallback(Uri target, {String method = 'GET'}) async {
      final client = HttpClient();
      try {
        final response = await (await client.openUrl(method, target)).close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    Uri callbackUri(Uri url) => Uri.parse(url.queryParameters['redirect_uri']!)
        .replace(
          queryParameters: {
            'state': url.queryParameters['state']!,
            ...callback,
          },
        );

    StarSyncGoogleDesktopAuth pickerAuth({
      Future<bool> Function(Uri)? launch,
    }) => makeAuth(
      pickerLauncher: (url) async {
        launches.add(url);
        if (launch != null) return launch(url);
        await sendCallback(callbackUri(url));
        return true;
      },
    );

    setUp(() {
      launches = [];
      exchanges = 0;
      callback = {
        'code': 'picker-code',
        'scope': googleDriveFileScope,
        'picked_file_ids': 'folder_123-X',
      };
      token = {'access_token': 'onepick-only', 'scope': googleDriveFileScope};
      tokenStatus = HttpStatus.ok;
      pickerRequest = (request, fields) async {
        exchanges++;
        final p = launches.last.queryParameters;
        tokenStarted?.complete();
        await tokenContinue?.future;
        expect(request.uri.path, '/token');
        expect(request.method, 'POST');
        expect(fields['client_id'], 'client');
        expect(fields['client_secret'], 'secret');
        expect(fields['redirect_uri'], p['redirect_uri']);
        expect(fields['grant_type'], 'authorization_code');
        expect(fields['code'], 'picker-code');
        final digest = sha256.convert(ascii.encode(fields['code_verifier']!));
        expect(
          base64Url.encode(digest.bytes).replaceAll('=', ''),
          p['code_challenge'],
        );
        request.response.statusCode = tokenStatus;
        request.response.write(jsonEncode(token));
      };
    });

    test('exchanges a folder-only grant and preserves the signed-in session', () async {
      final auth = pickerAuth();
      await auth.signIn();
      final previous = storage.values[starSyncGoogleTokenKey];
      final generation = auth.generation;
      // Even if Google supplies a refresh token, the picker must not store it.
      token['refresh_token'] = 'incidental-picker-refresh';
      expect(await auth.pickDriveFolder(), 'folder_123-X');
      final p = launches.single.queryParameters;
      expect(p['scope'], googleDriveFileScope);
      expect(p['prompt'], 'consent');
      expect(p['access_type'], 'online');
      expect(p['include_granted_scopes'], 'false');
      expect(p['trigger_onepick'], 'true');
      expect(p['mimetypes'], 'application/vnd.google-apps.folder');
      expect(p['allow_folder_selection'], 'true');
      expect(p['allow_multiple'], isNot('true'));
      expect(p['login_hint'], 'user@example.com');
      expect(p['client_id'], 'client');
      expect(p['response_type'], 'code');
      expect(p['code_challenge_method'], 'S256');
      expect(p['state'], isNotEmpty);
      expect(Uri.parse(p['redirect_uri']!).host, '127.0.0.1');
      expect(exchanges, 1);
      expect(storage.values[starSyncGoogleTokenKey], previous);
      expect(auth.generation, generation);
      expect(auth.currentEmail, 'user@example.com');
      expect(await auth.hasScope(googleDriveFileScope), isFalse);
      expect(await auth.accessToken(), 'initial');
      expect(await auth.accessToken(forceRefresh: true), 'refresh1');
    });

    test('requires a current session before opening the browser', () async {
      await expectLater(
        pickerAuth().pickDriveFolder(),
        failsWith(StarSyncGoogleAuthErrorKind.notSignedIn),
      );
      expect(launches, isEmpty);
      expect(exchanges, 0);
    });

    test(
      'ignores wrong state, path and method before the genuine callback',
      () async {
        final auth = pickerAuth(
          launch: (url) async {
            final target = callbackUri(url);
            expect(await sendCallback(target.replace(path: '/other')), 404);
            expect(
              await sendCallback(
                target.replace(
                  queryParameters: {'state': 'wrong', 'error': 'access_denied'},
                ),
              ),
              400,
            );
            expect(
              await sendCallback(
                target.replace(query: '${target.query}&state=wrong'),
              ),
              400,
            );
            expect(await sendCallback(target, method: 'POST'), 400);
            expect(await sendCallback(target), 200);
            return true;
          },
        );
        await auth.signIn();
        expect(await auth.pickDriveFolder(), 'folder_123-X');
        expect(exchanges, 1);
      },
    );

    test(
      'consent cancellation closes the listener and permits a fresh retry',
      () async {
        final auth = pickerAuth();
        await auth.signIn();
        final success = callback;
        callback = {'error': 'access_denied'};
        expect(await auth.pickDriveFolder(), isNull);
        expect(exchanges, 0);
        await expectLater(
          sendCallback(callbackUri(launches.single)),
          throwsA(isA<SocketException>()),
        );
        callback = success;
        expect(await auth.pickDriveFolder(), 'folder_123-X');
        for (final key in ['state', 'code_challenge']) {
          expect(
            launches.last.queryParameters[key],
            isNot(launches.first.queryParameters[key]),
          );
        }
      },
    );

    test(
      'browser launch failure releases the listener and allows retry',
      () async {
        final auth = pickerAuth(
          launch: (url) async {
            if (launches.length == 1) return false;
            await sendCallback(callbackUri(url));
            return true;
          },
        );
        await auth.signIn();
        await expectLater(
          auth.pickDriveFolder(),
          failsWith(StarSyncGoogleAuthErrorKind.browserUnavailable),
        );
        await expectLater(
          sendCallback(callbackUri(launches.single)),
          throwsA(isA<SocketException>()),
        );
        expect(await auth.pickDriveFolder(), 'folder_123-X');
      },
    );

    test('OAuth server errors are distinct from cancellation', () async {
      final auth = pickerAuth();
      await auth.signIn();
      callback['error'] = 'server_error';
      await expectLater(
        auth.pickDriveFolder(),
        failsWith(StarSyncGoogleAuthErrorKind.failed),
      );
      expect(exchanges, 0);
    });

    test(
      'discards a browser callback if its login session was replaced',
      () async {
        final launched = Completer<Uri>();
        final auth = pickerAuth(
          launch: (url) async {
            launched.complete(url);
            return true;
          },
        );
        await auth.signIn();
        final result = expectLater(
          auth.pickDriveFolder(),
          failsWith(StarSyncGoogleAuthErrorKind.notSignedIn),
        );
        final browser = await launched.future;
        await auth.restore();
        await sendCallback(callbackUri(browser));
        await result;
        expect(exchanges, 0);
      },
    );

    for (final id in [null, '', 'one,two', '../other']) {
      test('rejects missing or malformed single folder ID ($id)', () async {
        final auth = pickerAuth();
        await auth.signIn();
        callback.remove('picked_file_ids');
        if (id != null) callback['picked_file_ids'] = id;
        await expectLater(
          auth.pickDriveFolder(),
          failsWith(StarSyncGoogleAuthErrorKind.failed),
        );
      });
    }

    test(
      'exchange errors and missing access tokens leave login intact',
      () async {
        final auth = pickerAuth();
        await auth.signIn();
        final previous = storage.values[starSyncGoogleTokenKey];
        token = {'error': 'invalid_grant'};
        tokenStatus = 400;
        await expectLater(
          auth.pickDriveFolder(),
          failsWith(StarSyncGoogleAuthErrorKind.failed),
        );
        tokenStatus = 200;
        token = {};
        await expectLater(
          auth.pickDriveFolder(),
          failsWith(StarSyncGoogleAuthErrorKind.failed),
        );
        expect(exchanges, 2);
        expect(storage.values[starSyncGoogleTokenKey], previous);
        expect(await auth.accessToken(), 'initial');
      },
    );

    test(
      'rejects unexpected scopes from the callback or the exchange',
      () async {
        final auth = pickerAuth();
        await auth.signIn();
        callback['scope'] = 'openid $googleDriveFileScope';
        await expectLater(
          auth.pickDriveFolder(),
          failsWith(StarSyncGoogleAuthErrorKind.permissionDenied),
        );
        callback.remove('scope');
        token['scope'] = 'openid';
        await expectLater(
          auth.pickDriveFolder(),
          failsWith(StarSyncGoogleAuthErrorKind.permissionDenied),
        );
        token.remove('scope');
        expect(await auth.pickDriveFolder(), 'folder_123-X');
      },
    );

    test(
      'session replacement during code exchange invalidates the picked ID',
      () async {
        final auth = pickerAuth();
        await auth.signIn();
        tokenStarted = Completer<void>();
        tokenContinue = Completer<void>();
        final result = expectLater(
          auth.pickDriveFolder(),
          failsWith(StarSyncGoogleAuthErrorKind.notSignedIn),
        );
        await tokenStarted!.future;
        await auth.restore();
        tokenContinue!.complete();
        await result;
        expect(exchanges, 1);
      },
    );

    test(
      'immediate repick completes while the old token reply is held',
      () async {
        final auth = pickerAuth();
        await auth.signIn();
        tokenStarted = Completer<void>();
        final oldReply = tokenContinue = Completer<void>();
        final selection = auth.pickDriveFolder();
        await tokenStarted!.future;
        await expectLater(
          auth.pickDriveFolder(),
          failsWith(StarSyncGoogleAuthErrorKind.failed),
        );
        auth.cancelPendingDriveFolderPick();
        tokenStarted = tokenContinue = null;
        callback['picked_file_ids'] = 'replacement';
        final replacement = auth.pickDriveFolder();
        try {
          expect(await selection.timeout(const Duration(seconds: 3)), isNull);
          expect(
            await replacement.timeout(const Duration(seconds: 3)),
            'replacement',
          );
        } finally {
          oldReply.complete();
        }
        expect(exchanges, 2);
        expect(await auth.accessToken(), 'initial');
      },
    );

    for (final phase in [
      'launch',
      'callback',
      'callback before launch returns',
    ]) {
      test(
        'targeted cancellation allows an immediate repick during $phase',
        () async {
          final firstReady = Completer<void>();
          final oldLaunch = Completer<bool>();
          final nextReady = Completer<Uri>();
          final auth = pickerAuth(
            launch: (url) async {
              if (launches.length == 1) {
                if (phase == 'callback before launch returns') {
                  await sendCallback(callbackUri(url));
                }
                firstReady.complete();
                if (phase != 'callback') return oldLaunch.future;
              } else {
                nextReady.complete(url);
              }
              return true;
            },
          );
          await auth.signIn();
          final first = auth.pickDriveFolder();
          await firstReady.future;
          auth.cancelPendingSignIn();
          await expectLater(
            auth.pickDriveFolder(),
            failsWith(StarSyncGoogleAuthErrorKind.failed),
          );
          auth.cancelPendingDriveFolderPick();
          final retry = auth.pickDriveFolder();
          final next = await nextReady.future.timeout(
            const Duration(seconds: 3),
          );
          try {
            expect(await first.timeout(const Duration(seconds: 3)), isNull);
          } finally {
            oldLaunch.complete(false);
          }
          // Late cleanup from the first operation must not unlock the second.
          await expectLater(
            auth.pickDriveFolder(),
            failsWith(StarSyncGoogleAuthErrorKind.failed),
          );
          callback['picked_file_ids'] = 'replacement';
          await sendCallback(callbackUri(next));
          expect(await retry, 'replacement');
          expect(exchanges, 1);
        },
      );
    }

    for (final requestingScopes in [false, true]) {
      test(
        'picker cancellation preserves pending ${requestingScopes ? 'scope request' : 'sign-in'}',
        () async {
          final auth = pickerAuth();
          if (requestingScopes) await auth.signIn();
          incremental = requestingScopes;
          tokenStarted = Completer<void>();
          tokenContinue = Completer<void>();
          final pending = requestingScopes
              ? auth.requestScopes([googleDriveFileScope])
              : auth.signIn();
          await tokenStarted!.future;
          auth.cancelPendingDriveFolderPick();
          tokenContinue!.complete();
          await pending;
          expect(auth.currentEmail, 'user@example.com');
          expect(await auth.hasScope(googleDriveFileScope), requestingScopes);
        },
      );
    }
  });

  test('unticked scope reports permission denied', () async {
    omitScope = true;
    await expectLater(
      makeAuth().signIn(),
      throwsA(
        isA<StarSyncGoogleAuthException>().having(
          (e) => e.kind,
          'kind',
          StarSyncGoogleAuthErrorKind.permissionDenied,
        ),
      ),
    );
  });

  test('unavailable browser reports its own error', () async {
    final auth = StarSyncGoogleDesktopAuth(
      config: const StarSyncGoogleAuthConfig(
        desktopClientId: 'client',
        desktopClientSecret: 'secret',
      ),
      storage: storage,
      launcher: (_) async => false,
    );
    await expectLater(
      auth.signIn(),
      throwsA(
        isA<StarSyncGoogleAuthException>().having(
          (e) => e.kind,
          'kind',
          StarSyncGoogleAuthErrorKind.browserUnavailable,
        ),
      ),
    );
  });

  test('cancel closes loopback server and is harmless when idle', () async {
    final launched = Completer<Uri>();
    final auth = StarSyncGoogleDesktopAuth(
      config: const StarSyncGoogleAuthConfig(
        desktopClientId: 'client',
        desktopClientSecret: 'secret',
      ),
      storage: storage,
      launcher: (uri) async {
        launched.complete(uri);
        return true;
      },
    );
    auth.cancelPendingSignIn();
    final signIn = auth.signIn();
    final failure = expectLater(
      signIn,
      throwsA(
        isA<StarSyncGoogleAuthException>().having(
          (e) => e.kind,
          'kind',
          StarSyncGoogleAuthErrorKind.cancelled,
        ),
      ),
    );
    final uri = await launched.future;
    auth.cancelPendingSignIn();
    await failure;
    auth.cancelPendingSignIn();
    final client = HttpClient();
    try {
      await expectLater(
        client.getUrl(Uri.parse(uri.queryParameters['redirect_uri']!)),
        throwsA(isA<SocketException>()),
      );
    } finally {
      client.close(force: true);
    }
  });

  test('cancel during token exchange does not store credentials', () async {
    tokenStarted = Completer<void>();
    tokenContinue = Completer<void>();
    final auth = makeAuth();
    final signIn = auth.signIn();
    final failure = expectLater(
      signIn,
      throwsA(
        isA<StarSyncGoogleAuthException>().having(
          (e) => e.kind,
          'kind',
          StarSyncGoogleAuthErrorKind.cancelled,
        ),
      ),
    );
    await tokenStarted!.future;
    auth.cancelPendingSignIn();
    tokenContinue!.complete();
    await failure;
    expect(storage.values, isEmpty);
    expect(auth.currentEmail, isNull);
  });

  test('a second authorization does not disturb the first', () async {
    tokenStarted = Completer<void>();
    tokenContinue = Completer<void>();
    final auth = makeAuth();
    final first = auth.signIn();
    final firstFailure = expectLater(
      first,
      throwsA(
        isA<StarSyncGoogleAuthException>().having(
          (e) => e.kind,
          'kind',
          StarSyncGoogleAuthErrorKind.cancelled,
        ),
      ),
    );
    await tokenStarted!.future;
    await expectLater(
      auth.signIn(),
      throwsA(
        isA<StarSyncGoogleAuthException>().having(
          (e) => e.kind,
          'kind',
          StarSyncGoogleAuthErrorKind.failed,
        ),
      ),
    );
    auth.cancelPendingSignIn();
    tokenContinue!.complete();
    await firstFailure;
    expect(storage.values, isEmpty);
  });

  test(
    'cancel incremental authorization preserves previous credentials',
    () async {
      final auth = makeAuth();
      await auth.signIn();
      final previous = storage.values[starSyncGoogleTokenKey];
      incremental = true;
      tokenStarted = Completer<void>();
      tokenContinue = Completer<void>();
      final request = auth.requestScopes([googleDriveFileScope]);
      final failure = expectLater(
        request,
        throwsA(
          isA<StarSyncGoogleAuthException>().having(
            (e) => e.kind,
            'kind',
            StarSyncGoogleAuthErrorKind.cancelled,
          ),
        ),
      );
      await tokenStarted!.future;
      auth.cancelPendingSignIn();
      tokenContinue!.complete();
      await failure;
      expect(storage.values[starSyncGoogleTokenKey], previous);
      expect(auth.currentEmail, 'user@example.com');
      expect(await auth.hasScope(googleDriveFileScope), isFalse);
    },
  );

  test('sign in stores refresh token and parses email', () async {
    final auth = makeAuth();
    expect(await auth.signIn(), 'user@example.com');
    expect(jsonDecode(storage.values[starSyncGoogleTokenKey]!), {
      'refreshToken': 'refresh-secret',
      'email': 'user@example.com',
      'scopes': starSyncGoogleScopes,
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

  test(
    'malformed callback queries return 400 without aborting sign in',
    () async {
      malformedQuery = true;
      expect(await makeAuth().signIn(), 'user@example.com');
    },
  );

  test(
    'sign in reports unavailable storage without setting credentials',
    () async {
      storage.failWrite = true;
      final auth = makeAuth();
      await expectLater(
        auth.signIn(),
        throwsA(
          isA<StarSyncGoogleAuthException>().having(
            (e) => e.kind,
            'kind',
            StarSyncGoogleAuthErrorKind.storageUnavailable,
          ),
        ),
      );
      expect(auth.currentEmail, isNull);
      expect(storage.values, isEmpty);
    },
  );

  test('restore reports unavailable storage', () async {
    storage.failRead = true;
    await expectLater(
      makeAuth().restore(),
      throwsA(
        isA<StarSyncGoogleAuthException>().having(
          (e) => e.kind,
          'kind',
          StarSyncGoogleAuthErrorKind.storageUnavailable,
        ),
      ),
    );
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

  for (final invalidGrant in [false, true]) {
    for (final sameRefresh in [false, true]) {
      test(
        'ignores stale refresh after reauthorization ($invalidGrant, $sameRefresh)',
        () async {
          final auth = makeAuth();
          await auth.signIn();
          final generation = auth.generation;
          refreshStarted = Completer<void>();
          refreshContinue = Completer<void>();
          revoked = invalidGrant;
          final pending = expectLater(
            auth.accessToken(forceRefresh: true),
            throwsA(
              isA<StarSyncGoogleAuthException>().having(
                (error) => error.kind,
                'kind',
                StarSyncGoogleAuthErrorKind.notSignedIn,
              ),
            ),
          );
          await refreshStarted!.future;
          incremental = !sameRefresh;
          changedAccount = !sameRefresh;
          await auth.signIn(
            optionalScopes: incremental ? [googleDriveFileScope] : [],
          );
          final credentials = storage.values[starSyncGoogleTokenKey];
          expect(auth.generation, greaterThan(generation));
          refreshContinue!.complete();
          await pending;
          expect(
            auth.currentEmail,
            sameRefresh ? 'user@example.com' : 'other@example.com',
          );
          expect(storage.values[starSyncGoogleTokenKey], credentials);
          expect(await auth.accessToken(), 'initial');
          expect(refreshes, 1);
        },
      );
    }
  }

  test('invalid grant clears memory even when deletion fails', () async {
    final auth = makeAuth();
    await auth.signIn();
    revoked = true;
    storage.failDelete = true;
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
    expect(auth.currentEmail, isNull);
    expect(storage.values, contains(starSyncGoogleTokenKey));
  });

  test('incremental scopes accept a different email casing', () async {
    storage.values[starSyncGoogleTokenKey] = jsonEncode({
      'refreshToken': 'refresh-secret',
      'email': 'User@example.com',
      'scopes': starSyncGoogleScopes,
    });
    final auth = makeAuth();
    expect(await auth.restore(), 'User@example.com');
    incremental = true;
    await auth.requestScopes([googleDriveFileScope]);
    expect(auth.currentEmail, 'user@example.com');
    expect(await auth.hasScope(googleDriveFileScope), isTrue);
    expect(
      jsonDecode(storage.values[starSyncGoogleTokenKey]!)['refreshToken'],
      'new-refresh-secret',
    );
  });

  test('incremental scopes persist and reject another account', () async {
    final auth = makeAuth();
    await auth.signIn();
    incremental = true;
    await auth.requestScopes([googleDriveFileScope]);
    expect(await auth.hasScope(googleDriveFileScope), isTrue);
    final stored = jsonDecode(storage.values[starSyncGoogleTokenKey]!);
    expect(stored['refreshToken'], 'new-refresh-secret');
    expect(
      stored['scopes'],
      containsAll([...starSyncGoogleScopes, googleDriveFileScope]),
    );
    final restarted = makeAuth();
    expect(await restarted.restore(), 'user@example.com');
    expect(await restarted.hasScope(googleDriveFileScope), isTrue);
    await restarted.requestScopes([googleDriveFileScope]);
    expect(await restarted.accessToken(), 'refresh1');
    expect(await auth.accessToken(forceRefresh: true), 'refresh2');

    changedAccount = true;
    await expectLater(
      auth.requestScopes(['another-scope']),
      throwsA(
        isA<StarSyncGoogleAuthException>().having(
          (e) => e.message,
          'message',
          'account changed',
        ),
      ),
    );
    expect(
      jsonDecode(storage.values[starSyncGoogleTokenKey]!)['refreshToken'],
      'new-refresh-secret',
    );
    expect(await auth.accessToken(forceRefresh: true), 'refresh3');
  });

  test('sign out accepts an empty 200 revoke response', () async {
    final auth = makeAuth();
    await auth.signIn();
    await expectLater(auth.signOut(), completes);
    expect(revokedToken, 'refresh-secret');
    expect(storage.values, isEmpty);
    expect(auth.currentEmail, isNull);
  });

  for (final failRevocation in [false, true]) {
    test(
      'sign out reports failed deletion with revocation failure $failRevocation',
      () async {
        final auth = makeAuth();
        await auth.signIn();
        revokeFails = failRevocation;
        storage.failDelete = true;
        await expectLater(
          auth.signOut(),
          throwsA(
            isA<StarSyncGoogleAuthException>().having(
              (e) => e.kind,
              'kind',
              StarSyncGoogleAuthErrorKind.storageUnavailable,
            ),
          ),
        );
        expect(auth.currentEmail, isNull);
        expect(storage.values, contains(starSyncGoogleTokenKey));
      },
    );
  }

  test('failed revocation still deletes local credentials', () async {
    final auth = makeAuth();
    await auth.signIn();
    revokeFails = true;
    await expectLater(
      auth.signOut(),
      throwsA(isA<StarSyncGoogleRevocationException>()),
    );
    expect(storage.values, isEmpty);
    expect(auth.currentEmail, isNull);
  });

  test('sign out after restart revokes the stored token', () async {
    await makeAuth().signIn();
    await makeAuth().signOut();
    expect(revokedToken, 'refresh-secret');
    expect(storage.values, isEmpty);
  });

  test('failed revocation after restart still deletes credentials', () async {
    await makeAuth().signIn();
    revokeFails = true;
    await expectLater(
      makeAuth().signOut(),
      throwsA(isA<StarSyncGoogleRevocationException>()),
    );
    expect(revokedToken, 'refresh-secret');
    expect(storage.values, isEmpty);
  });

  test('restore uses persisted refresh token', () async {
    await makeAuth().signIn();
    final auth = makeAuth();
    expect(await auth.restore(), 'user@example.com');
    expect(await auth.accessToken(), 'refresh1');
  });
}
