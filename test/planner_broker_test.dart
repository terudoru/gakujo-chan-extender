import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/planner_bridge/planner_broker.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';

class Auth extends Fake implements StarSyncGoogleAuth {
  String? email = 'fixture@example.invalid';
  int revision = 0;
  @override
  String? get currentEmail => email;
  @override
  int get generation => revision;
}

class Drive extends Fake implements PlannerDrive {
  String fileName = 'mbg-planner-account-key-v1';
  String text = 'fixture';
  int writes = 0;
  Completer<String>? pending;
  Object? error;
  List<dynamic> files = [];
  @override
  Future<String> name(String id) async =>
      pending == null ? fileName : pending!.future;
  @override
  Future<String> read(String id) async => text;
  @override
  Future<Map<String, dynamic>> list(String prefix, String? token) async {
    if (error != null) throw error!;
    return {'files': files};
  }

  @override
  Future<String> create(
    String name,
    String text,
    Map<String, String>? properties, {
    void Function()? beforeSend,
  }) async {
    writes++;
    return 'fixture-id';
  }

  @override
  Future<void> delete(String id, {void Function()? beforeSend}) async {
    writes++;
  }
}

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/planner_bridge_v2_vectors.json').readAsStringSync(),
  ) as Map;
  late Auth auth;
  late Drive drive;
  late PlannerBroker broker;
  final events = <Map<String, dynamic>>[];
  const id = '00000000-0000-4000-8000-000000000001';
  Future<Map<String, dynamic>> call(
    String op, [
    Map<String, dynamic> args = const {},
  ]) => broker.handle(
    {'v': 2, 'id': id, 'op': op, 'args': args},
    document: Uri.parse('https://gakujo.terudoru.com/syllabus/'),
    topFrame: true,
  );
  setUp(() {
    auth = Auth();
    drive = Drive();
    drive.files = fixture['examples'][3]['response']['result']['files'] as List;
    events.clear();
    broker = PlannerBroker(
      auth: auth,
      drive: drive,
      student: () => plannerStudentScope('TEST-STUDENT-001'),
      signIn: () async {
        auth.email = 'fixture@example.invalid';
        auth.revision++;
      },
      signOut: () async {
        auth.email = null;
        auth.revision++;
      },
      onSession: events.add,
      timeout: const Duration(milliseconds: 100),
    );
  });
  test('shared name and student vectors', () {
    for (final name in fixture['names']['accept'] as List) {
      expect(isPlannerWritableName(name as String), isTrue, reason: name);
    }
    for (final name in fixture['names']['reject'] as List) {
      expect(isPlannerWritableName(name as String), isFalse, reason: name);
    }
    expect(
      plannerStudentScope(fixture['student']['userId'] as String),
      fixture['student']['scope'],
    );
    expect(plannerStudentScope(null), isNull);
  });
  test('fixture protocol operations echo IDs and exact result keys', () async {
    for (final example in fixture['examples'] as List) {
      final request = example['request'] as Map;
      if ((request['op'] as String).startsWith('drive.')) {
        auth.email = 'fixture@example.invalid';
      }
      final result = await call(
        request['op'] as String,
        Map<String, dynamic>.from(request['args'] as Map),
      );
      expect(result['id'], id);
      expect(result['ok'], isTrue, reason: '$result');
      expect(result, example['response']);
      expect(
        (result['result'] as Map).keys.toSet(),
        (example['response']['result'] as Map).keys.toSet(),
      );
    }
    expect(events.any((e) => e['session']['signedIn'] == false), isTrue);
  });
  test(
    'origin, path, frame, malformed request and unknown operation fail closed',
    () async {
      for (final url in [
        'https://evil.invalid/syllabus/',
        'https://gakujo.terudoru.com/syllabus',
        'https://gakujo.terudoru.com/planner/',
      ]) {
        expect(
          (await broker.handle(
            {'id': id},
            document: Uri.parse(url),
            topFrame: true,
          ))['error']['code'],
          'forbidden',
        );
      }
      expect(
        (await broker.handle(
          {'id': id},
          document: Uri.parse('https://gakujo.terudoru.com/syllabus/'),
          topFrame: false,
        ))['error']['code'],
        'forbidden',
      );
      expect((await call('unknown'))['error']['code'], 'forbidden');
    },
  );
  test('UTF8 size limits, read prefix and delete allowlist', () async {
    expect(
      (await call('drive.create', {
        'name': drive.fileName,
        'text': 'a' * plannerMaxBytes,
      }))['ok'],
      isTrue,
    );
    expect(
      (await call('drive.create', {
        'name': drive.fileName,
        'text': 'あ' * (plannerMaxBytes ~/ 3 + 1),
      }))['error']['code'],
      'forbidden',
    );
    drive.text = 'a' * (plannerMaxBytes + 1);
    expect(
      (await call('drive.read', {'fileId': 'x'}))['error']['code'],
      'forbidden',
    );
    drive.fileName = 'stars/keyring.json';
    expect(
      (await call('drive.read', {'fileId': 'x'}))['error']['code'],
      'forbidden',
    );
    expect(
      (await call('drive.delete', {'fileId': 'x'}))['error']['code'],
      'forbidden',
    );
    expect(
      (await call('drive.list', {'namePrefix': 'stars'}))['error']['code'],
      'forbidden',
    );
  });
  test(
    'navigation/account/dispose invalidates pending delete before mutation',
    () async {
      for (final change in [
        () => broker.invalidate(),
        () {
          auth.revision++;
        },
        () => broker.dispose(),
      ]) {
        drive.pending = Completer<String>();
        final result = call('drive.delete', {'fileId': 'x'});
        await Future<void>.delayed(Duration.zero);
        change();
        drive.pending!.complete(drive.fileName);
        expect((await result)['error']['code'], 'stale-session');
      }
      expect(drive.writes, 0);
    },
  );
  test('timeout cannot later delete', () async {
    drive.pending = Completer<String>();
    expect(
      (await call('drive.delete', {'fileId': 'x'}))['error']['code'],
      'timeout',
    );
    drive.pending!.complete(drive.fileName);
    await Future<void>.delayed(Duration.zero);
    expect(drive.writes, 0);
  });
  test('error codes never expose backend messages', () async {
    auth.email = null;
    expect(
      (await call('drive.list', {
        'namePrefix': 'mbg-planner-',
      }))['error']['code'],
      'not-signed-in',
    );
    auth.email = 'fixture@example.invalid';
    for (final code in fixture['errors'] as List) {
      drive.error = PlannerBridgeException(code as String);
      expect(
        (await call('drive.list', {'namePrefix': 'mbg-planner-'}))['error'],
        {'code': code, 'message': code},
      );
    }
    drive.error = StateError('secret');
    expect(
      (await call('drive.list', {
        'namePrefix': 'mbg-planner-',
      }))['error']['message'],
      'internal',
    );
  });
}
