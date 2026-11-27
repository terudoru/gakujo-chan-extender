import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/planner_bridge/planner_broker.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';

class Auth extends Fake implements StarSyncGoogleAuth {
  String? email = 'test@example.invalid';
  int revision = 0;
  final scopes = starSyncGoogleScopes.toSet();
  final checkedScopes = <String>[];
  final scopeRequests = <List<String>>[];
  Completer<bool>? pendingScope;
  @override
  String? get currentEmail => email;
  @override
  int get generation => revision;
  @override
  Future<bool> hasScope(String scope) async {
    checkedScopes.add(scope);
    return pendingScope == null ? scopes.contains(scope) : pendingScope!.future;
  }

  @override
  Future<void> requestScopes(List<String> requested) async {
    scopeRequests.add(requested);
    scopes.addAll(requested);
    revision++;
  }
}

class Drive extends Fake implements PlannerDrive {
  String fileName = 'mbg-planner-account-key-v1';
  String text = 'fixture';
  int writes = 0;
  String owner = 'synthetic-owner';
  Completer<String>? pendingOwner;
  final created = <(String, String, Map<String, String>?)>[];
  final deleted = <String>[];
  @override
  Future<String> permissionId() async =>
      pendingOwner == null ? owner : pendingOwner!.future;
  Completer<String>? pending;
  Object? error;
  List<dynamic> files = [];
  final lists = <(String, String?, bool)>[];
  @override
  Future<String> name(String id) async =>
      pending == null ? fileName : pending!.future;
  @override
  Future<String> read(String id) async => text;
  @override
  Future<Map<String, dynamic>> list(
    String prefix,
    String? token, {
    bool exact = false,
  }) async {
    lists.add((prefix, token, exact));
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
    beforeSend?.call();
    writes++;
    created.add((name, text, properties));
    return 'synthetic-file';
  }

  @override
  Future<void> delete(String id, {void Function()? beforeSend}) async {
    beforeSend?.call();
    writes++;
    deleted.add(id);
  }
}

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/planner_bridge_v2_vectors.json').readAsStringSync(),
  ) as Map;
  late Auth auth;
  late Drive drive;
  late PlannerBroker broker;
  late int signIns;
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
    signIns = 0;
    drive = Drive();
    drive.files =
        fixture['operations'][3]['response']['result']['files'] as List;
    drive.text =
        fixture['operations'][4]['response']['result']['text'] as String;
    events.clear();
    broker = PlannerBroker(
      auth: auth,
      drive: drive,
      student: () => plannerStudentScope('TEST-STUDENT-001'),
      signIn: () async {
        signIns++;
        auth.email = 'test@example.invalid';
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
  test(
    'signed-in signIn reuses scoped session without interactive auth',
    () async {
      final hello = (await call('hello'))['result'] as Map;
      final generation = broker.generation;
      events.clear();
      expect(await call('signIn'), {
        'v': 2,
        'id': id,
        'ok': true,
        'result': {'session': hello['session']},
      });
      expect(auth.checkedScopes, starSyncGoogleScopes);
      expect(signIns, 0);
      expect(auth.scopeRequests, isEmpty);
      expect(auth.revision, 0);
      expect(broker.generation, generation);
      expect(events, isEmpty);
    },
  );
  test(
    'signed-out signIn invokes interactive auth and binds new session',
    () async {
      auth.email = null;
      final result = await call('signIn');
      expect(signIns, 1);
      expect(auth.checkedScopes, isEmpty);
      expect(auth.scopeRequests, isEmpty);
      expect(result, {
        'v': 2,
        'id': id,
        'ok': true,
        'result': {
          'session': {
            'signedIn': true,
            'email': auth.email,
            'permissionId': drive.owner,
          },
        },
      });
      expect(events.single['session'], result['result']['session']);
    },
  );
  test('missing scope requests consent for the existing account', () async {
    await call('hello');
    final generation = broker.generation;
    auth.scopes.remove(starSyncGoogleScopes.first);
    final result = await call('signIn');
    expect(result['ok'], true);
    expect(result['result']['session'], {
      'signedIn': true,
      'email': 'test@example.invalid',
      'permissionId': drive.owner,
    });
    expect(signIns, 0);
    expect(auth.scopeRequests.single, starSyncGoogleScopes);
    expect(broker.generation, greaterThan(generation));
  });
  test(
    'account change during scope check cannot start interactive auth',
    () async {
      auth.pendingScope = Completer<bool>();
      final result = call('signIn');
      await Future<void>.delayed(Duration.zero);
      auth.email = 'other@example.invalid';
      auth.revision++;
      auth.pendingScope!.complete(false);
      expect((await result)['error']['code'], 'not-signed-in');
      expect(signIns, 0);
      expect(auth.scopeRequests, isEmpty);
      expect(events, isEmpty);
    },
  );
  final hash = fixture['studentHash'] as Map;
  test('studentHash vector includes the exact salt and newline separator', () {
    expect(plannerStudentSalt, hash['salt']);
    expect(hash['separator'], '\n');
    expect(plannerStudentScope(hash['userId'] as String), hash['scope']);
    expect(plannerStudentScope(null), isNull);
  });
  for (final accepted in [true, false]) {
    for (final name
        in fixture['names'][accepted ? 'accept' : 'reject'] as List) {
      test('name $accepted: $name', () async {
        expect(isPlannerWritableName(name as String), accepted);
        final result = await call('drive.create', {'name': name, 'text': '{}'});
        expect(result['ok'], accepted);
        drive.fileName = name;
        final deletion = await call('drive.delete', {
          'fileId': 'synthetic-file',
        });
        expect(deletion['ok'], accepted);
        expect(drive.writes, accepted ? 2 : 0);
        if (!accepted) {
          expect(result['error']['code'], 'forbidden');
          expect(deletion['error']['code'], 'forbidden');
        }
      });
    }
  }
  for (final example in fixture['operations'] as List) {
    final request = Map<String, dynamic>.from(example['request'] as Map);
    test(
      'exact contract operation: ${request['op']} ${request['args']}',
      () async {
        if (request['op'] == 'drive.list') {
          drive.files = example['response']['result']['files'] as List;
        }
        if (request['op'] == 'drive.read') {
          drive.text = example['response']['result']['text'] as String;
          if (request['args']['fileId'] == 'synthetic-handoff') {
            drive.fileName = fixture['names']['acceptForRead'][0] as String;
          }
          if (request['args']['fileId'] == 'synthetic-timetable') {
            drive.fileName = fixture['names']['acceptForRead'][1] as String;
          }
        }
        final result = await broker.handle(
          request,
          document: Uri.parse('https://gakujo.terudoru.com/syllabus/'),
          topFrame: true,
        );
        expect(result, example['response']);
        if (request['op'] == 'drive.list') {
          final args = request['args'] as Map;
          expect(drive.lists.single, (
            args['nameExact'] ?? args['namePrefix'],
            args['pageToken'],
            args.containsKey('nameExact'),
          ));
        }
        if (request['op'] == 'drive.create') {
          final created = drive.created.single;
          expect(created.$1, request['args']['name']);
          expect(created.$2, request['args']['text']);
          expect(created.$3, request['args']['appProperties']);
        }
        if (request['op'] == 'drive.delete') {
          expect(drive.deleted, [request['args']['fileId']]);
        }
      },
    );
  }
  for (final example in fixture['forbiddenOperations'] as List) {
    final request = Map<String, dynamic>.from(example['request'] as Map);
    test('forbidden vector: ${request['op']} ${request['args']}', () async {
      drive.fileName = fixture['names']['acceptForRead'][0] as String;
      final expected = Map<String, dynamic>.from(example['response'] as Map);
      final code = expected['error']['code'];
      expect(
        await broker.handle(
          request,
          document: Uri.parse('https://gakujo.terudoru.com/syllabus/'),
          topFrame: true,
        ),
        {
          ...expected,
          'error': {'code': code, 'message': code},
        },
      );
      expect(drive.writes, 0);
    });
  }
  for (final accepted in [true, false]) {
    for (final name
        in fixture['names'][accepted ? 'acceptForRead' : 'rejectForRead']
            as List) {
      test('read name $accepted: $name', () async {
        drive.fileName = name as String;
        expect(
          (await call('drive.read', {'fileId': 'unlisted'}))['ok'],
          accepted,
        );
      });
    }
  }
  for (final name in fixture['names']['rejectForWrite'] as List) {
    test('reject write name: $name', () async {
      drive.fileName = name as String;
      expect(
        (await call('drive.create', {
          'name': name,
          'text': '{}',
        }))['error']['code'],
        'forbidden',
      );
      expect(
        (await call('drive.delete', {'fileId': 'unlisted'}))['error']['code'],
        'forbidden',
      );
      expect(drive.writes, 0);
    });
  }
  test('previous negative name regressions remain forbidden', () async {
    final plan = fixture['names']['accept'][0] as String;
    for (final name in [
      'stars/keyring.json',
      '$plan\n',
      'x$plan',
      plan.replaceFirst('.plan.', '.grades.'),
      plan.replaceFirst('ITR8.plan', 'ITR.plan'),
    ]) {
      expect(isPlannerWritableName(name), false);
      expect(
        (await call('drive.create', {
          'name': name,
          'text': '{}',
        }))['error']['code'],
        'forbidden',
      );
      drive.fileName = name;
      expect(
        (await call('drive.delete', {'fileId': 'unlisted'}))['error']['code'],
        'forbidden',
      );
    }
    expect(drive.writes, 0);
  });
  test('every session event including same-email owner replacement', () async {
    for (final event in fixture['sessionEvents'] as List) {
      final session = event['session'] as Map;
      auth.email = session['email'] as String?;
      drive.owner = session['permissionId'] as String? ?? '';
      auth.revision++;
      await broker.refreshSession();
      expect(events.last, event);
    }
    expect(events, fixture['sessionEvents']);
  });
  test(
    'binding vector can be created, read and purged without rewriting bytes',
    () async {
      final binding = fixture['binding'] as Map;
      final name = binding['name'] as String;
      final text = binding['text'] as String;
      expect(jsonDecode(text), {'v': 1, 'scope': hash['scope']});
      expect(
        (await call('drive.create', {'name': name, 'text': text}))['ok'],
        true,
      );
      expect(drive.created.single, (name, text, null));
      drive.fileName = name;
      drive.text = text;
      expect(
        (await call('drive.read', {'fileId': 'synthetic-file'}))['result'],
        {'text': text},
      );
      expect(
        (await call('drive.delete', {'fileId': 'synthetic-file'}))['ok'],
        true,
      );
      expect(drive.deleted, ['synthetic-file']);
    },
  );
  test('timetable capability gives the web view exact read-only access', () async {
    const name = 'mbg-gakujo-timetable.v1.json';
    drive.fileName = name;
    final hello = (await call('hello'))['result'] as Map;
    expect(hello['capabilities'], contains('gakujo-timetable'));
    expect((await call('drive.list', {'nameExact': name}))['ok'], true);
    expect((await call('drive.read', {'fileId': 'timetable'}))['ok'], true);
    expect((await call('drive.list', {'namePrefix': name}))['error']['code'], 'forbidden');
    expect((await call('drive.create', {'name': name, 'text': '{}'}))['error']['code'], 'forbidden');
    expect((await call('drive.delete', {'fileId': 'timetable'}))['error']['code'], 'forbidden');
  });

  test('handoff is reachable only by exact name and is read-only', () async {
    const name = 'mbg-gakujo-handoff.v1.json';
    drive.fileName = name;
    expect((await call('drive.read', {'fileId': 'handoff'}))['result'], {
      'text': drive.text,
    });
    expect((await call('drive.list', {'nameExact': name}))['ok'], true);
    expect(
      (await call('drive.list', {'namePrefix': name}))['error']['code'],
      'forbidden',
    );
    for (final prefix in ['mbg-planner-', null]) {
      expect(
        (await call('drive.list', {
          'nameExact': name,
          'namePrefix': prefix,
        }))['error']['code'],
        'forbidden',
      );
    }
    expect(
      (await call('drive.create', {
        'name': name,
        'text': '{}',
      }))['error']['code'],
      'forbidden',
    );
    expect(
      (await call('drive.delete', {'fileId': 'handoff'}))['error']['code'],
      'forbidden',
    );
    for (final invalid in [
      'mbg-gakujo-',
      '$name.extra',
      'x$name',
      name.toUpperCase(),
    ]) {
      drive.fileName = invalid;
      expect(
        (await call('drive.read', {'fileId': 'handoff'}))['error']['code'],
        'forbidden',
      );
      expect(
        (await call('drive.list', {'namePrefix': invalid}))['error']['code'],
        'forbidden',
      );
    }
    expect(drive.writes, 0);
  });
  test('owner lookup cannot deliver a previous account identity', () async {
    drive.pendingOwner = Completer<String>();
    final result = call('hello');
    await Future<void>.delayed(Duration.zero);
    auth.revision++;
    drive.pendingOwner!.complete('previous-owner');
    expect((await result)['error']['code'], 'stale-session');
    expect(events, isEmpty);
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
    auth.email = 'test@example.invalid';
    for (final vector in fixture['errors'] as List) {
      final expected = Map<String, dynamic>.from(vector as Map);
      final error = expected['error'] as Map;
      final code = error['code'] as String;
      expect(error['message'], isA<String>());
      drive.error = PlannerBridgeException(code);
      final result = await call('drive.list', {'namePrefix': 'mbg-planner-'});
      // Fixture messages illustrate the response shape; native errors expose
      // only the sanitized code, never a backend's explanatory message.
      expect(result.keys.toSet(), expected.keys.toSet());
      expect((result['error'] as Map).keys.toSet(), error.keys.toSet());
      expect(result, {
        ...expected,
        'error': {'code': code, 'message': code},
      });
      expect(result['error']['message'], isNot(error['message']));
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
