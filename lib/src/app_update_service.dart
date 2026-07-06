import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.hasUpdate,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final bool hasUpdate;
}

class AppUpdateService {
  const AppUpdateService({
    this.owner = 'terudoru',
    this.repository = 'gakujo-chan-extender',
  });

  final String owner;
  final String repository;

  @visibleForTesting
  static int compareVersionsForTesting(String left, String right) {
    return const AppUpdateService()._compareVersions(left, right);
  }

  Future<AppUpdateInfo> checkLatestRelease({
    required String currentVersion,
  }) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repository/releases/latest',
    );
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'MoreBetterGakujo');
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final body = await utf8.decodeStream(response);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Release response must be an object');
      }
      final tag = decoded['tag_name']?.toString() ?? '';
      final latest = _normalizeVersion(tag);
      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: tag.isEmpty ? latest : tag,
        releaseUrl: decoded['html_url']?.toString() ??
            'https://github.com/$owner/$repository/releases',
        hasUpdate:
            _compareVersions(latest, _normalizeVersion(currentVersion)) > 0,
      );
    } finally {
      client.close(force: true);
    }
  }

  String _normalizeVersion(String value) {
    return value.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
  }

  int _compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < maxLength; index += 1) {
      final l = index < leftParts.length ? leftParts[index] : 0;
      final r = index < rightParts.length ? rightParts[index] : 0;
      if (l != r) {
        return l.compareTo(r);
      }
    }
    return 0;
  }

  List<int> _versionParts(String value) {
    final parts = <int>[];
    final segments = _normalizeVersion(value).split(RegExp(r'[.-]'));
    for (final segment in segments) {
      final match = RegExp(r'^\d+').firstMatch(segment);
      if (match == null) {
        if (parts.isEmpty) {
          continue;
        }
        break;
      }
      parts.add(int.parse(match.group(0)!));
    }
    return parts.isEmpty ? const [0] : parts;
  }
}
