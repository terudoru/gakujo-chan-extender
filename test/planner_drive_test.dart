import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/planner_bridge/planner_broker.dart';
import 'package:morebettergakujo_flutter/src/planner_bridge/planner_drive.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';

class _Auth extends Fake implements StarSyncGoogleAuth {
  @override
  String? get currentEmail => 'test@example.invalid';
  @override
  int get generation => 0;
  @override
  Future<String> accessToken({bool forceRefresh = false}) async => 'synthetic';
}

class _Client extends Fake implements HttpClient {
  _Client(this.inner, this.port);
  final HttpClient inner;
  final int port;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    expect(url.host, 'www.googleapis.com');
    expect(url.scheme, 'https');
    return inner.openUrl(
      method,
      Uri.http('127.0.0.1:$port', url.path, url.queryParameters),
    );
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

void main() {
  test(
    'native owner lookup and exact handoff listing retain appData read guard',
    () async {
      const name = 'mbg-gakujo-handoff.v1.json';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final inner = HttpClient();
      final requests = <Uri>[];
      var appData = true;
      server.listen((request) async {
        requests.add(request.uri);
        expect(request.method, 'GET');
        final Object data;
        if (request.uri.path == '/drive/v3/about') {
          expect(request.uri.queryParameters['fields'], 'user(permissionId)');
          data = {
            'user': {'permissionId': 'synthetic-owner'},
          };
        } else if (request.uri.path == '/drive/v3/files') {
          expect(request.uri.queryParameters['spaces'], 'appDataFolder');
          expect(
            request.uri.queryParameters['q'],
            anyOf(
              "trashed = false and name = '$name'",
              "trashed = false and name contains 'mbg-planner-'",
            ),
          );
          expect(
            request.uri.queryParameters['fields'],
            contains('mimeType,spaces,modifiedTime'),
          );
          data = {
            'files': [
              {'id': 'handoff', 'name': name},
              {'id': 'suffix', 'name': '$name.extra'},
              {'id': 'unrelated', 'name': 'unrelated'},
              {'id': 'planner', 'name': 'mbg-planner-account-key-v1'},
            ],
          };
        } else {
          data = {
            'name': name,
            'spaces': appData ? ['appDataFolder'] : ['drive'],
            'trashed': false,
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(data));
        await request.response.close();
      });
      try {
        await HttpOverrides.runZoned(() async {
          final drive = NativePlannerDrive(_Auth());
          try {
            expect(await drive.permissionId(), 'synthetic-owner');
            expect(await drive.list(name, null, exact: true), {
              'files': [
                {'id': 'handoff', 'name': name},
              ],
            });
            expect(await drive.list('mbg-planner-', null), {
              'files': [
                {'id': 'planner', 'name': 'mbg-planner-account-key-v1'},
              ],
            });
            expect(await drive.name('handoff'), name);
            appData = false;
            await expectLater(
              drive.name('handoff'),
              throwsA(
                isA<PlannerBridgeException>().having(
                  (e) => e.code,
                  'code',
                  'forbidden',
                ),
              ),
            );
            expect(requests, hasLength(5));
          } finally {
            drive.close();
          }
        }, createHttpClient: (_) => _Client(inner, server.port));
      } finally {
        inner.close(force: true);
        await server.close(force: true);
      }
    },
  );
}
