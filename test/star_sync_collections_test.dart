import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_collections.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_drive_transport.dart';

void main() {
  test('canonical JSON sorts keys recursively', () {
    expect(
      starSyncValueHash({
        'b': [
          1,
          {'z': 2, 'a': 3},
        ],
        'a': true,
      }),
      starSyncValueHash({
        'a': true,
        'b': [
          1,
          {'a': 3, 'z': 2},
        ],
      }),
    );
  });

  test('retains only the newest 1000 tombstones', () {
    final records = <String, StarSyncCollectionRecord>{};
    for (var i = 0; i < 1002; i++) {
      final key = '$i';
      records[key] = StarSyncCollectionRecord(
        key: key,
        value: null,
        deleted: true,
        clock: i,
        deviceId: 'device',
        valueHash: starSyncValueHash(null),
      );
    }
    final merged = mergeStarSyncCollectionRecords([records]);
    expect(merged.length, 1000);
    expect(merged.containsKey('0'), isFalse);
    expect(merged.containsKey('1'), isFalse);
    expect(merged.containsKey('1001'), isTrue);
  });

  test('Drive collection listing uses the same files.list cache', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var listCount = 0;
    final serving = server.forEach((request) async {
      if (request.uri.path == '/drive/v3/files') listCount++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'files': []}));
      await request.response.close();
    });
    final transport = StarSyncGoogleDriveTransport(
      accessToken: ({bool forceRefresh = false}) async => 'test',
      apiBase: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    try {
      await transport.list('stars');
      await transport.list('stars/devices');
      await transport.list('sync/drafts');
      await transport.list('sync/settings');
      expect(listCount, 1);
    } finally {
      transport.close();
      await server.close(force: true);
      await serving;
    }
  });
}
