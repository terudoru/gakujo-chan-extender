import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../secure_storage_factory.dart';
import 'star_sync_google_desktop_auth.dart';
import 'star_sync_google_mobile_auth.dart';

const starSyncGoogleScopes = [
  'https://www.googleapis.com/auth/drive.appdata',
  'openid',
  'email',
];
const googleDriveFileScope = 'https://www.googleapis.com/auth/drive.file';

class StarSyncGoogleAuthConfig {
  const StarSyncGoogleAuthConfig({
    this.desktopClientId = const String.fromEnvironment(
      'GOOGLE_OAUTH_DESKTOP_CLIENT_ID',
    ),
    this.desktopClientSecret = const String.fromEnvironment(
      'GOOGLE_OAUTH_DESKTOP_CLIENT_SECRET',
    ),
    this.androidServerClientId = const String.fromEnvironment(
      'GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID',
    ),
    this.iosClientId = const String.fromEnvironment(
      'GOOGLE_OAUTH_IOS_CLIENT_ID',
    ),
  });

  final String desktopClientId;
  final String desktopClientSecret;
  final String androidServerClientId;
  final String iosClientId;

  bool get isAvailable {
    if (Platform.isAndroid) return androidServerClientId.isNotEmpty;
    if (Platform.isIOS) return iosClientId.isNotEmpty;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return desktopClientId.isNotEmpty && desktopClientSecret.isNotEmpty;
    }
    return false;
  }
}

enum StarSyncGoogleAuthErrorKind {
  notSignedIn,
  revoked,
  permissionDenied,
  browserUnavailable,
  storageUnavailable,
  cancelled,
  network,
  failed,
}

class StarSyncGoogleAuthException implements Exception {
  const StarSyncGoogleAuthException(this.kind, [this.message = '']);
  final StarSyncGoogleAuthErrorKind kind;
  final String message;
  @override
  String toString() => 'StarSyncGoogleAuthException($kind): $message';
}

class StarSyncGoogleRevocationException implements Exception {
  const StarSyncGoogleRevocationException();
}

abstract interface class StarSyncGoogleAuth {
  String? get currentEmail;
  Future<String?> restore();

  /// [optionalScopes] are asked for too, but sign-in succeeds without them.
  Future<String> signIn({List<String> optionalScopes = const []});
  void cancelPendingSignIn();
  Future<String> accessToken({bool forceRefresh = false});
  Future<bool> hasScope(String scope);
  Future<void> requestScopes(List<String> scopes);
  Future<void> signOut();
}

StarSyncGoogleAuth createStarSyncGoogleAuth({
  StarSyncGoogleAuthConfig? config,
  FlutterSecureStorage? storage,
}) {
  final effectiveConfig = config ?? const StarSyncGoogleAuthConfig();
  if (Platform.isAndroid || Platform.isIOS) {
    return StarSyncGoogleMobileAuth(config: effectiveConfig);
  }
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return StarSyncGoogleDesktopAuth(
      config: effectiveConfig,
      storage: storage ?? SecureStorageFactory.create(),
    );
  }
  throw UnsupportedError('Google sign-in is unavailable on this platform');
}
