import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../drive_planner_handoff.dart';
import '../star_sync/star_sync_google_auth.dart';
import '../star_sync/star_sync_transport.dart';
import 'planner_broker.dart';

class NativePlannerDrive implements PlannerDrive {
  NativePlannerDrive(this.auth);
  final StarSyncGoogleAuth auth;
  final _client = HttpClient();
  void close() => _client.close(force: true);

  Future<List<int>> _request(
    String method,
    String path, {
    Map<String, String> query = const {},
    List<int> body = const [],
    String? contentType,
    void Function()? beforeSend,
  }) async {
    final session = StarSyncGoogleAuthSession(auth, email: auth.currentEmail);
    final token = await session.accessToken();
    session.checkCurrent();
    final response = await starSyncRequest(
      _client,
      method,
      Uri.https('www.googleapis.com', path, query),
      headers: {'authorization': 'Bearer $token', 'content-type': ?contentType},
      body: body,
      maxBytes: plannerMaxBytes,
      timeout: const Duration(seconds: 29),
      beforeSend: () {
        session.checkCurrent();
        beforeSend?.call();
      },
    );
    session.checkCurrent();
    if (response.statusCode == 401) {
      throw const PlannerBridgeException('not-signed-in');
    }
    if (response.statusCode == 429 ||
        isGoogleDriveRateLimit(response) ||
        googleDriveErrorReason(response) == 'storageQuotaExceeded' ||
        googleDriveErrorReason(response) == 'dailyLimitExceeded') {
      throw const PlannerBridgeException('quota');
    }
    if (response.statusCode == 403 || response.statusCode == 404) {
      throw const PlannerBridgeException('forbidden');
    }
    if (response.statusCode >= 500) {
      throw const PlannerBridgeException('network');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const PlannerBridgeException('internal');
    }
    return response.bytes;
  }

  String _path(String id) => '/drive/v3/files/${Uri.encodeComponent(id)}';
  @override
  Future<String> permissionId() async {
    final data = jsonDecode(
      utf8.decode(
        await _request(
          'GET',
          '/drive/v3/about',
          query: {'fields': 'user(permissionId)'},
        ),
      ),
    );
    final owner = data['user']?['permissionId'];
    if (owner is! String || owner.isEmpty) {
      throw const PlannerBridgeException('forbidden');
    }
    return owner;
  }

  @override
  Future<Map<String, dynamic>> list(
    String prefix,
    String? pageToken, {
    bool exact = false,
  }) async {
    if (exact
        ? prefix != drivePlannerHandoffName
        : !prefix.startsWith('mbg-planner-')) {
      throw const PlannerBridgeException('forbidden');
    }
    // Drive has no startsWith query: filter contains results locally, and
    // preserve pagination even when a page contains no matching names.
    final data = jsonDecode(
      utf8.decode(
        await _request(
          'GET',
          '/drive/v3/files',
          query: {
            'spaces': 'appDataFolder',
            'q': exact
                ? "trashed = false and name = '$drivePlannerHandoffName'"
                : "trashed = false and name contains 'mbg-planner-'",
            'fields': 'nextPageToken,files(id,name,createdTime,appProperties,mimeType,spaces,modifiedTime)',
            'pageSize': '1000',
            'pageToken': ?pageToken,
          },
        ),
      ),
    ) as Map<String, dynamic>;
    return {
      'files': (data['files'] as List)
          .where(
            (f) => exact
                ? f['name'] == drivePlannerHandoffName
                : (f['name'] as String).startsWith(prefix),
          )
          .toList(),
      'nextPageToken': ?data['nextPageToken'],
    };
  }

  @override
  Future<String> name(String id) async {
    final data = jsonDecode(
      utf8.decode(
        await _request(
          'GET',
          _path(id),
          query: {'fields': 'name,spaces,trashed'},
        ),
      ),
    );
    if (data['trashed'] == true ||
        !(data['spaces'] as List? ?? []).contains('appDataFolder')) {
      throw const PlannerBridgeException('forbidden');
    }
    return data['name'] as String;
  }

  @override
  Future<String> read(String id) async =>
      utf8.decode(await _request('GET', _path(id), query: {'alt': 'media'}));
  @override
  Future<String> create(
    String name,
    String text,
    Map<String, String>? properties, {
    void Function()? beforeSend,
  }) async {
    final boundary =
        'planner_${List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16)).join()}';
    final metadata = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
      'appProperties': ?properties,
    });
    final body = utf8.encode(
      '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n$text\r\n--$boundary--\r\n',
    );
    final data = jsonDecode(
      utf8.decode(
        await _request(
          'POST',
          '/upload/drive/v3/files',
          query: {'uploadType': 'multipart', 'fields': 'id'},
          body: body,
          contentType: 'multipart/related; boundary=$boundary',
          beforeSend: beforeSend,
        ),
      ),
    );
    return data['id'] as String;
  }

  @override
  Future<void> delete(String id, {void Function()? beforeSend}) async {
    await _request('DELETE', _path(id), beforeSend: beforeSend);
  }
}
