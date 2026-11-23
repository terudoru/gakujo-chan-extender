import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../star_sync/star_sync_google_auth.dart';
import '../star_sync/star_sync_transport.dart';

const plannerMaxBytes = 4 * 1024 * 1024;
const plannerStudentSalt = 'mbg.planner.student.v1';
String? plannerStudentScope(String? userId) => userId == null
    ? null
    : base64Url
          .encode(
            sha256.convert(utf8.encode('$plannerStudentSalt\n$userId')).bytes,
          )
          .replaceAll('=', '');

bool isHostedPlanner(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'gakujo.terudoru.com' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    uri.path.startsWith('/syllabus/');

final _plannerName = RegExp(
  r'^mbg-planner-(google-v1|v1)\.[A-Za-z0-9_-]{43}\.(plan|history|organizer)\.[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
bool isPlannerWritableName(String name) =>
    const {
      'mbg-planner-account-key-v1',
      'mbg-planner-cloud-deleted-v1',
      'mbg-planner-student-binding-v1',
    }.contains(name) ||
    (_plannerName.hasMatch(name) && !name.endsWith('\n'));

class PlannerBridgeException implements Exception {
  const PlannerBridgeException(this.code);
  final String code;
}

abstract interface class PlannerDrive {
  Future<Map<String, dynamic>> list(String prefix, String? pageToken);
  Future<String> name(String id);
  Future<String> read(String id);
  Future<String> create(
    String name,
    String text,
    Map<String, String>? properties, {
    void Function()? beforeSend,
  });
  Future<void> delete(String id, {void Function()? beforeSend});
}

/// Pure protocol boundary. Never returns exceptions, HTTP bodies or tokens.
class PlannerBroker {
  PlannerBroker({
    required this.auth,
    required this.drive,
    required this.student,
    required this.signIn,
    required this.signOut,
    this.onSession,
    this.timeout = const Duration(seconds: 30),
  });
  final StarSyncGoogleAuth auth;
  final PlannerDrive drive;
  final String? Function() student;
  final Future<void> Function() signIn;
  final Future<void> Function() signOut;
  final void Function(Map<String, dynamic>)? onSession;
  final Duration timeout;
  int generation = 0;
  bool _disposed = false;
  int? _authGeneration;
  String? _scope;
  Map<String, dynamic> get session => {
    'signedIn': auth.currentEmail != null,
    if (auth.currentEmail != null) 'email': auth.currentEmail,
  };
  void invalidate() {
    generation++;
  }

  void refreshSession() {
    final scope = student();
    if (_authGeneration == auth.generation && _scope == scope) return;
    _authGeneration = auth.generation;
    _scope = scope;
    invalidate();
    onSession?.call({'v': 2, 'event': 'session', 'session': session});
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }

  Future<Map<String, dynamic>> handle(
    Object? input, {
    required Uri document,
    required bool topFrame,
  }) async {
    final id = input is Map ? input['id'] : null;
    try {
      refreshSession();
      if (_disposed || !topFrame || !isHostedPlanner(document)) {
        throw const PlannerBridgeException('forbidden');
      }
      if (input is! Map ||
          input['v'] != 2 ||
          id is! String ||
          !RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(id) ||
          input['args'] is! Map) {
        throw const PlannerBridgeException('forbidden');
      }
      final start = generation;
      var expired = false;
      void check() {
        refreshSession();
        if (_disposed || generation != start) {
          throw const PlannerBridgeException('stale-session');
        }
        if (expired) throw const PlannerBridgeException('timeout');
      }

      final result =
          await _operate(
            input['op'],
            Map<String, dynamic>.from(input['args'] as Map),
            check,
          ).timeout(
            timeout,
            onTimeout: () {
              expired = true;
              throw const PlannerBridgeException('timeout');
            },
          );
      // Auth operations deliberately change the session; all others are pinned.
      if (input['op'] != 'signIn' && input['op'] != 'signOut') check();
      return {'v': 2, 'id': id, 'ok': true, 'result': result};
    } on Object catch (error) {
      final code = switch (error) {
        PlannerBridgeException() => error.code,
        TimeoutException() => 'timeout',
        SocketException() => 'network',
        StarSyncTransportException() => switch (error.kind) {
          StarSyncTransportErrorKind.network ||
          StarSyncTransportErrorKind.tls => 'network',
          StarSyncTransportErrorKind.storageFull => 'quota',
          StarSyncTransportErrorKind.auth => 'not-signed-in',
          StarSyncTransportErrorKind.invalidResponse => 'forbidden',
          _ => 'internal',
        },
        StarSyncGoogleAuthException() => switch (error.kind) {
          StarSyncGoogleAuthErrorKind.cancelled => 'auth-cancelled',
          StarSyncGoogleAuthErrorKind.network => 'network',
          StarSyncGoogleAuthErrorKind.notSignedIn ||
          StarSyncGoogleAuthErrorKind.revoked => 'not-signed-in',
          StarSyncGoogleAuthErrorKind.permissionDenied => 'forbidden',
          _ => 'internal',
        },
        _ => 'internal',
      };
      return {
        'v': 2,
        'id': id,
        'ok': false,
        'error': {'code': code, 'message': code},
      };
    }
  }

  Future<Map<String, dynamic>> _operate(
    Object? op,
    Map<String, dynamic> args,
    void Function() check,
  ) async {
    String string(String key) {
      final value = args[key];
      if (value is! String || value.isEmpty) {
        throw const PlannerBridgeException('forbidden');
      }
      return value;
    }

    switch (op) {
      case 'hello':
        return {
          'version': 2,
          'capabilities': ['drive-appdata', 'native-sign-in'],
          'sessionGeneration': generation,
          'session': session,
        };
      case 'student':
        return {'scope': student()};
      case 'signIn':
        check();
        await signIn();
        refreshSession();
        return {'session': session};
      case 'signOut':
        check();
        await signOut();
        refreshSession();
        return {'session': session};
      case 'drive.list':
      case 'drive.read':
      case 'drive.create':
      case 'drive.delete':
        if (auth.currentEmail == null) {
          throw const PlannerBridgeException('not-signed-in');
        }
        check();
        if (op == 'drive.list') {
          final prefix = string('namePrefix');
          if (!prefix.startsWith('mbg-planner-') ||
              prefix.length > 1024 ||
              (args['pageToken'] != null && args['pageToken'] is! String)) {
            throw const PlannerBridgeException('forbidden');
          }
          return drive.list(prefix, args['pageToken'] as String?);
        }
        if (op == 'drive.create') {
          final name = string('name');
          final text = args['text'];
          if (!isPlannerWritableName(name) ||
              text is! String ||
              utf8.encode(text).length > plannerMaxBytes) {
            throw const PlannerBridgeException('forbidden');
          }
          final properties = args['appProperties'];
          if (properties != null &&
              (properties is! Map ||
                  properties.entries.any(
                    (e) => e.key is! String || e.value is! String,
                  ))) {
            throw const PlannerBridgeException('forbidden');
          }
          check();
          return {
            'id': await drive.create(
              name,
              text,
              properties == null
                  ? null
                  : Map<String, String>.from(properties as Map),
              beforeSend: check,
            ),
          };
        }
        final id = string('fileId');
        final name = await drive.name(id);
        check();
        if (op == 'drive.read') {
          if (!name.startsWith('mbg-planner-')) {
            throw const PlannerBridgeException('forbidden');
          }
          final text = await drive.read(id);
          if (utf8.encode(text).length > plannerMaxBytes) {
            throw const PlannerBridgeException('forbidden');
          }
          return {'text': text};
        }
        if (!isPlannerWritableName(name)) {
          throw const PlannerBridgeException('forbidden');
        }
        await drive.delete(id, beforeSend: check);
        return {};
      default:
        throw const PlannerBridgeException('forbidden');
    }
  }
}
