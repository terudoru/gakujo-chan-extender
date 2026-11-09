import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.hasUpdate,
    this.assetNames = const [],
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final bool hasUpdate;
  final List<String> assetNames;

  // iOS builds are attached later, so the latest release may lack an installer.
  bool hasInstallerFor(TargetPlatform platform) {
    final suffixes = switch (platform) {
      TargetPlatform.android => ['.apk'],
      TargetPlatform.iOS => ['.ipa'],
      TargetPlatform.macOS => ['.dmg'],
      TargetPlatform.windows => ['.exe', '.zip'],
      TargetPlatform.linux => ['.tar.gz', '.deb'],
      TargetPlatform.fuchsia => <String>[],
    };
    return assetNames.any((name) =>
        suffixes.any((suffix) => name.toLowerCase().endsWith(suffix)));
  }
}

const appUpdateCheckInterval = Duration(hours: 24);

bool isUpdateCheckDue(DateTime? lastCheckedAt, DateTime now) {
  return lastCheckedAt == null ||
      lastCheckedAt.isAfter(now) ||
      now.difference(lastCheckedAt) >= appUpdateCheckInterval;
}

bool shouldNotifyAboutUpdate(
  AppUpdateInfo info, {
  required TargetPlatform platform,
  String? dismissedVersion,
}) {
  return info.hasUpdate &&
      info.hasInstallerFor(platform) &&
      info.latestVersion != dismissedVersion;
}

class AppUpdateService {
  const AppUpdateService({
    this.owner = 'terudoru',
    this.repository = 'gakujo-chan-extender',
    this.httpClientFactory,
    this.requestTimeout = const Duration(seconds: 15),
  });

  final String owner;
  final String repository;
  final HttpClient Function()? httpClientFactory;
  final Duration requestTimeout;

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
    final client = httpClientFactory?.call() ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final body = await _readReleaseBody(client, uri).timeout(requestTimeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Release response must be an object');
      }
      final tag = decoded['tag_name']?.toString() ?? '';
      final latest = _normalizeVersion(tag);
      // releases/latest already skips these; a release marked by mistake or a
      // change on GitHub's side must still not reach students as an update.
      final isPrerelease = decoded['prerelease'] == true ||
          decoded['draft'] == true ||
          latest.contains('-');
      final assets = decoded['assets'];
      final assetNames = assets is List
          ? assets
              .whereType<Map>()
              .where((asset) =>
                  !asset.containsKey('state') || asset['state'] == 'uploaded')
              .map((asset) => asset['name'])
              .whereType<String>()
              .toList()
          : <String>[];
      return AppUpdateInfo(
        assetNames: assetNames,
        currentVersion: currentVersion,
        latestVersion: tag.isEmpty ? latest : tag,
        releaseUrl: decoded['html_url']?.toString() ??
            'https://github.com/$owner/$repository/releases',
        hasUpdate: !isPrerelease &&
            _compareVersions(latest, _normalizeVersion(currentVersion)) > 0,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _readReleaseBody(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'MoreBetterGakujo');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return utf8.decodeStream(response);
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
