import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_mobile_auth.dart';

import 'support/fake_google_sign_in_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = FakeGoogleSignInPlatform();
  const email = 'bound@example.com';
  late StarSyncGoogleMobileAuth auth;
  late bool reachable;
  late int reachabilityCalls;

  setUpAll(() {
    GoogleSignInPlatform.instance = platform;
  });

  setUp(() {
    platform.reset();
    reachable = true;
    reachabilityCalls = 0;
    auth = StarSyncGoogleMobileAuth(
      config: const StarSyncGoogleAuthConfig(),
      isAndroidOverride: true,
      isGoogleReachableOverride: () async {
        reachabilityCalls++;
        return reachable;
      },
    );
  });

  group('Drive folder picker', () {
    const channel = MethodChannel(
      'net.yoshida.morebettergakujo/drive_folder_picker',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final notSignedIn = throwsA(
      isA<StarSyncGoogleAuthException>().having(
        (e) => e.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      ),
    );
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('requires the active account before opening native UI', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return null;
      });
      await expectLater(auth.pickDriveFolder(), notSignedIn);
      expect(calls, 0);
    });

    for (final android in [true, false]) {
      test('passes only the active email and applicable config on '
          '${android ? "Android" : "iOS"}', () async {
        const clientId = 'sample.apps.googleusercontent.com';
        final mobile = StarSyncGoogleMobileAuth(
          config: const StarSyncGoogleAuthConfig(iosClientId: clientId),
          isAndroidOverride: android,
        );
        final activeEmail = android
            ? await mobile.restore(expectedEmail: email)
            : await mobile.signIn();
        final generation = mobile.generation;
        platform.calls.clear();
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 'Folder_1-2';
        });
        expect(await mobile.pickDriveFolder(), 'Folder_1-2');
        expect(calls.single.method, 'pickFolder');
        expect(calls.single.arguments, {
          'email': activeEmail,
          if (!android) 'iosClientId': clientId,
        });
        expect(mobile.currentEmail, activeEmail);
        expect(mobile.generation, generation);
        expect(platform.calls, isEmpty);
        await mobile.accessToken(forceRefresh: true);
        expect(platform.calls.first, 'clear:token');
      });
    }

    test('restricted mobile picker passes fileIds and rejects other IDs', () async {
      await auth.restore(expectedEmail: email);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'parent';
      });
      expect(await auth.pickDriveFolder(fileIds: ['parent']), 'parent');
      expect((calls.single.arguments as Map)['fileIds'], ['parent']);
      await expectLater(auth.pickDriveFolder(fileIds: ['other']),
        throwsA(isA<StarSyncGoogleAuthException>()));
      final before = calls.length;
      await expectLater(auth.pickDriveFolder(fileIds: ['bad/id']),
        throwsA(isA<StarSyncGoogleAuthException>()));
      expect(calls.length, before);
    });

    test('cancellation and malformed native replies leave the session usable', () async {
      await auth.restore(expectedEmail: email);
      final generation = auth.generation;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await auth.pickDriveFolder(), isNull);
      for (final value in ['', 'a,b', 'a/b', 'id\n', 12]) {
        messenger.setMockMethodCallHandler(channel, (_) async => value);
        await expectLater(auth.pickDriveFolder(), throwsA(
          isA<StarSyncGoogleAuthException>().having(
            (e) => e.kind, 'kind', StarSyncGoogleAuthErrorKind.failed,
          ),
        ));
      }
      expect(auth.generation, generation);
      expect(auth.currentEmail, email);
      expect(await auth.accessToken(), 'token');
    });

    for (final lateError in [false, true]) {
      test('cancel releases only the owning pick and permits immediate retry '
          '(late native error: $lateError)', () async {
        await auth.restore(expectedEmail: email);
        final other = StarSyncGoogleMobileAuth(
          config: const StarSyncGoogleAuthConfig(),
          isAndroidOverride: true,
        );
        await other.restore(expectedEmail: 'other@example.org');
        final generation = auth.generation;
        platform.calls.clear();
        final calls = <String>[];
        final replies = <Completer<String?>>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'cancelPick') {
            expect(call.arguments, isNull);
            throw PlatformException(code: 'cannot_cancel');
          }
          final reply = Completer<String?>();
          replies.add(reply);
          return reply.future;
        });

        final first = auth.pickDriveFolder();
        await expectLater(other.pickDriveFolder(), throwsA(isA<StarSyncGoogleAuthException>()));
        other.cancelPendingDriveFolderPick();
        auth.cancelPendingSignIn();
        expect(calls, ['pickFolder']);
        auth.cancelPendingDriveFolderPick();
        auth.cancelPendingDriveFolderPick();
        final retry = auth.pickDriveFolder();
        expect(await first, isNull);
        expect(calls, ['pickFolder', 'cancelPick', 'pickFolder']);
        if (lateError) {
          replies.first.completeError(PlatformException(code: 'old_failure'));
        } else {
          replies.first.complete('old_folder');
        }
        replies.last.complete('new_folder');
        expect(await retry, 'new_folder');
        auth.cancelPendingDriveFolderPick();
        expect(calls, ['pickFolder', 'cancelPick', 'pickFolder']);
        expect(auth.generation, generation);
        expect(auth.currentEmail, email);
        expect(platform.calls, isEmpty);
      });
    }

    test('native failures omit platform diagnostics', () async {
      await auth.restore(expectedEmail: email);
      for (final entry in {
        'browser_unavailable': StarSyncGoogleAuthErrorKind.browserUnavailable,
        'permission_denied': StarSyncGoogleAuthErrorKind.permissionDenied,
        'network': StarSyncGoogleAuthErrorKind.network,
        'busy': StarSyncGoogleAuthErrorKind.failed,
      }.entries) {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: entry.key, message: 'provider details');
        });
        await expectLater(auth.pickDriveFolder(), throwsA(
          isA<StarSyncGoogleAuthException>()
              .having((e) => e.kind, 'kind', entry.value)
              .having((e) => e.message, 'message', isEmpty),
        ));
      }
    });

    for (final reply in ['folder', null]) {
      test('rejects a stale native reply ($reply) after same-account restore', () async {
        await auth.restore(expectedEmail: email);
        final opened = Completer<void>();
        final response = Completer<String?>();
        messenger.setMockMethodCallHandler(channel, (_) {
          opened.complete();
          return response.future;
        });
        final checked = expectLater(auth.pickDriveFolder(), notSignedIn);
        await opened.future;
        await auth.restore(expectedEmail: email);
        response.complete(reply);
        await checked;
        expect(auth.currentEmail, email);
      });
    }
  });

  test('restore without a saved email does not attempt authentication', () async {
    expect(await auth.restore(), isNull);
    expect(await auth.restore(expectedEmail: '  '), isNull);
    expect(platform.lightweightCalls, 0);
    expect(platform.requests, isEmpty);
  });

  test('restore with a blank email clears a previously restored account', () async {
    await auth.restore(expectedEmail: email);
    platform.requests.clear();
    expect(await auth.restore(expectedEmail: '  '), isNull);
    expect(auth.currentEmail, isNull);
    expect(platform.requests, isEmpty);
    expect(platform.lightweightCalls, 0);
  });

  test('restore uses the saved email without prompting', () async {
    expect(await auth.restore(expectedEmail: email), email);
    expect(auth.currentEmail, email);
    expect(platform.lightweightCalls, 0);
    expect(platform.requests, hasLength(1));
    expect(platform.requests.single.email, email);
    expect(platform.requests.single.userId, isNull);
    expect(platform.requests.single.scopes, starSyncGoogleScopes);
    expect(platform.requests.single.promptIfUnauthorized, isFalse);
  });

  test('restore clears the account when no grant exists', () async {
    await auth.restore(expectedEmail: email);
    platform.token = null;
    expect(await auth.restore(expectedEmail: email), isNull);
    expect(auth.currentEmail, isNull);
    expect(platform.lightweightCalls, 0);
  });

  test('restore retains the email on failure and later reports the error', () async {
    platform.error = const GoogleSignInException(code: GoogleSignInExceptionCode.unknownError);
    expect(await auth.restore(expectedEmail: email), email);
    expect(auth.currentEmail, email);
    await expectLater(auth.accessToken(), throwsA(isA<StarSyncGoogleAuthException>()));
    expect(platform.lightweightCalls, 0);
  });

  test('restore also retains the email for other errors', () async {
    platform.error = StateError('offline');
    expect(await auth.restore(expectedEmail: email), email);
    expect(auth.currentEmail, email);
    await expectLater(auth.accessToken(), throwsA(isA<StarSyncGoogleAuthException>()));
  });

  test('accessToken remains bound and refresh clears the cached token first', () async {
    await auth.restore(expectedEmail: email);
    platform.calls.clear();
    platform.requests.clear();
    expect(await auth.accessToken(), 'token');
    platform.token = 'refreshed';
    expect(await auth.accessToken(forceRefresh: true), 'refreshed');
    expect(platform.calls, ['silent', 'clear:token', 'silent']);
    expect(platform.requests.every((request) =>
        request.email == email && !request.promptIfUnauthorized), isTrue);
  });

  test('accessToken reports notSignedIn when consent is gone', () async {
    await auth.restore(expectedEmail: email);
    platform.token = null;
    await expectLater(
      auth.accessToken(),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      )),
    );
  });

  test('scope checks are silent and scope requests can prompt', () async {
    await auth.restore(expectedEmail: email);
    platform.requests.clear();
    expect(await auth.hasScope(googleDriveFileScope), isTrue);
    expect(platform.requests.single.email, email);
    expect(platform.requests.single.scopes, [googleDriveFileScope]);
    expect(platform.requests.single.promptIfUnauthorized, isFalse);
    platform.requests.clear();
    platform.denySilent = true;
    await auth.requestScopes([googleDriveFileScope]);
    expect(platform.requests, hasLength(2));
    expect(platform.requests.map((request) => request.promptIfUnauthorized), [false, true]);
    expect(platform.requests.every((request) => request.email == email), isTrue);
    expect(platform.requests.last.scopes, contains(googleDriveFileScope));
  });

  test('scope operations handle a missing account or grant', () async {
    expect(await auth.hasScope(googleDriveFileScope), isFalse);
    await expectLater(
      auth.requestScopes([googleDriveFileScope]),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      )),
    );
    await auth.restore(expectedEmail: email);
    platform.token = null;
    expect(await auth.hasScope(googleDriveFileScope), isFalse);
    await expectLater(
      auth.requestScopes([googleDriveFileScope]),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      )),
    );
  });

  test('signOut silently caches the restored account before disconnect', () async {
    await auth.restore(expectedEmail: email);
    platform.calls.clear();
    platform.requests.clear();
    await auth.signOut();
    expect(platform.calls, ['silent', 'disconnect']);
    expect(platform.requests.single.email, email);
    expect(platform.requests.single.promptIfUnauthorized, isFalse);
    expect(auth.currentEmail, isNull);
  });

  test('signOut without an account reports an unconfirmed revocation', () async {
    await expectLater(auth.signOut(), throwsA(isA<StarSyncGoogleRevocationException>()));
    expect(platform.calls, isEmpty);
  });

  test('signOut without a grant clears state without disconnecting', () async {
    await auth.restore(expectedEmail: email);
    platform.calls.clear();
    platform.token = null;
    await auth.signOut();
    expect(platform.calls, ['silent']);
    expect(auth.currentEmail, isNull);
  });

  test('signOut reports a failed silent authorization as unconfirmed', () async {
    await auth.restore(expectedEmail: email);
    platform.calls.clear();
    platform.error = StateError('offline');
    await expectLater(auth.signOut(), throwsA(isA<StarSyncGoogleRevocationException>()));
    expect(platform.calls, ['silent']);
    expect(auth.currentEmail, isNull);
  });

  test('signIn replaces the restored email with the authenticated account', () async {
    await auth.restore(expectedEmail: email);
    platform.requests.clear();
    expect(await auth.signIn(), 'new@example.com');
    expect(auth.currentEmail, 'new@example.com');
    expect(platform.requests.single.email, 'new@example.com');
    expect(platform.requests.single.userId, 'new-id');
    platform.requests.clear();
    await auth.accessToken();
    expect(platform.requests.single.email, 'new@example.com');
    expect(platform.requests.single.userId, 'new-id');
  });

  test('restore clears an account missing from the device', () async {
    platform.error = const GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
      description: 'Authorization failed: 16: [28433] Cannot find a matching credential.',
    );
    expect(await auth.restore(expectedEmail: email), isNull);
    expect(auth.currentEmail, isNull);
    expect(reachabilityCalls, 0);
  });

  for (final operation in ['accessToken', 'hasScope', 'requestScopes']) {
    test('$operation clears a restored account missing from the device', () async {
      platform.error = StateError('temporary failure');
      expect(await auth.restore(expectedEmail: email), email);
      platform.error = const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: '[28433] Cannot find a matching credential',
      );
      Future<void> runOperation() async {
        switch (operation) {
          case 'accessToken':
            await auth.accessToken();
          case 'hasScope':
            await auth.hasScope(googleDriveFileScope);
          default:
            await auth.requestScopes([googleDriveFileScope]);
        }
      }
      await expectLater(runOperation(), throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      )));
      expect(auth.currentEmail, isNull);
      expect(reachabilityCalls, 0);
    });
  }

  test('matching credential description alone clears the account', () async {
    await auth.restore(expectedEmail: email);
    platform.error = const GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
      description: 'Cannot find a matching credential',
    );
    await expectLater(auth.hasScope(googleDriveFileScope), throwsA(isA<StarSyncGoogleAuthException>().having(
      (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
    )));
    expect(auth.currentEmail, isNull);
  });

  test('missing account clears an authenticated account and cached token', () async {
    await auth.signIn();
    platform.error = const GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
      description: '[28433]',
    );
    await expectLater(auth.accessToken(), throwsA(isA<StarSyncGoogleAuthException>().having(
      (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
    )));
    expect(auth.currentEmail, isNull);
    platform.calls.clear();
    await expectLater(auth.accessToken(forceRefresh: true), throwsA(isA<StarSyncGoogleAuthException>().having(
      (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
    )));
    expect(platform.calls, isEmpty);
  });

  test('unrelated Google errors do not clear the restored account', () async {
    await auth.restore(expectedEmail: email);
    platform.error = const GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
      description: 'Authorization failed: 16',
    );
    await expectLater(auth.accessToken(), throwsA(isA<StarSyncGoogleAuthException>().having(
      (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.failed,
    )));
    expect(auth.currentEmail, email);
  });

  test('requestScopes clears a missing account reported by the prompt', () async {
    await auth.restore(expectedEmail: email);
    platform.denySilent = true;
    platform.promptError = const GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
      description: '[28433]',
    );
    await expectLater(auth.requestScopes([googleDriveFileScope]),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      )),
    );
    expect(auth.currentEmail, isNull);
  });

  for (final online in [false, true]) {
    test('restore with a silent null and reachable=$online', () async {
      reachable = online;
      platform.token = null;
      expect(await auth.restore(expectedEmail: email), online ? null : email);
      expect(auth.currentEmail, online ? null : email);
      expect(reachabilityCalls, 1);
    });

    for (final signedIn in [false, true]) {
      for (final forceRefresh in [false, true]) {
        test('accessToken silent null: reachable=$online account=$signedIn refresh=$forceRefresh', () async {
          reachable = online;
          if (signedIn) {
            await auth.signIn();
          } else {
            await auth.restore(expectedEmail: email);
          }
          platform.token = null;
          await expectLater(auth.accessToken(forceRefresh: forceRefresh),
            throwsA(isA<StarSyncGoogleAuthException>().having(
              (error) => error.kind, 'kind', online
                  ? StarSyncGoogleAuthErrorKind.notSignedIn
                  : StarSyncGoogleAuthErrorKind.network,
            )),
          );
          expect(auth.currentEmail, signedIn ? 'new@example.com' : email);
          expect(reachabilityCalls, 1);
        });
      }

      test('hasScope silent null: reachable=$online account=$signedIn', () async {
        reachable = online;
        if (signedIn) {
          await auth.signIn();
        } else {
          await auth.restore(expectedEmail: email);
        }
        platform.token = null;
        if (online) {
          expect(await auth.hasScope(googleDriveFileScope), isFalse);
        } else {
          await expectLater(auth.hasScope(googleDriveFileScope),
            throwsA(isA<StarSyncGoogleAuthException>().having(
              (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.network,
            )),
          );
        }
        expect(auth.currentEmail, signedIn ? 'new@example.com' : email);
        expect(reachabilityCalls, 1);
      });
    }

    test('signOut with a silent null and reachable=$online', () async {
      await auth.restore(expectedEmail: email);
      reachable = online;
      platform.token = null;
      platform.calls.clear();
      if (online) {
        await auth.signOut();
      } else {
        await expectLater(auth.signOut(), throwsA(isA<StarSyncGoogleRevocationException>()));
      }
      expect(auth.currentEmail, isNull);
      expect(platform.calls, ['silent']);
      expect(reachabilityCalls, 1);
    });
  }

  test('forceRefresh checks a null silent call before clearing a token', () async {
    platform.error = StateError('temporary failure');
    expect(await auth.restore(expectedEmail: email), email);
    platform.error = null;
    platform.token = null;
    reachable = false;
    platform.calls.clear();
    await expectLater(auth.accessToken(forceRefresh: true),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.network,
      )),
    );
    expect(platform.calls, ['silent']);
    expect(reachabilityCalls, 1);
  });

  test('non-Android never checks Google reachability', () async {
    final other = StarSyncGoogleMobileAuth(
      config: const StarSyncGoogleAuthConfig(),
      isAndroidOverride: false,
      isGoogleReachableOverride: () async {
        reachabilityCalls++;
        return false;
      },
    );
    expect(await other.restore(expectedEmail: email), isNull);
    await other.signIn();
    platform.token = null;
    expect(await other.hasScope(googleDriveFileScope), isFalse);
    await expectLater(other.accessToken(forceRefresh: true),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.notSignedIn,
      )),
    );
    expect(reachabilityCalls, 0);
    platform.error = const GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
      description: '[28433]',
    );
    await expectLater(other.hasScope(googleDriveFileScope),
      throwsA(isA<StarSyncGoogleAuthException>().having(
        (error) => error.kind, 'kind', StarSyncGoogleAuthErrorKind.failed,
      )),
    );
    expect(other.currentEmail, 'new@example.com');
    expect(reachabilityCalls, 0);
  });
}
