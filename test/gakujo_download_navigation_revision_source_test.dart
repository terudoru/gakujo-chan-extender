import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'intercepted downloads capture the revision before reading the page',
    () {
      final source = File('lib/src/gakujo_web_app.dart').readAsStringSync();
      final navigation = source.substring(
        source.indexOf(
          'Future<GakujoNavigationDecision> _handleNavigationRequest(',
        ),
        source.indexOf('Future<String> _estimateCourseNameFromPage('),
      );

      expect(
        navigation.indexOf('final revision = _navigationRevision;'),
        inExclusiveRange(0, navigation.indexOf('await ')),
      );
      expect(
        navigation,
        matches(
          RegExp(
            r'final pageCourseName = await _estimateCourseNameFromPage\(title\);\s*'
            r'final courseName =\s*resolveGakujoDownloadCourseName\(\s*'
            r'pageCourseName: pageCourseName,\s*'
            r'initialCourseName: null,\s*'
            r'navigationRevision: revision,\s*'
            r'currentNavigationRevision: _navigationRevision,\s*'
            r"\)\s*\?\?\s*'';",
          ),
        ),
      );
      expect(
        navigation,
        matches(
          RegExp(
            r'await _handleDownloadRequest\(\s*GakujoDownloadRequest\('
            r'[\s\S]*?courseName: courseName,[\s\S]*?\),\s*'
            r'navigationRevision: revision,\s*\);',
          ),
        ),
      );
    },
  );

  test('download preparation excludes page and cached names from a later page', () {
    final source = File('lib/src/gakujo_web_app_downloads.dart')
        .readAsStringSync();
    final handler = source.substring(
      source.indexOf('Future<void> _handleDownloadRequest('),
      source.indexOf('Future<void> _recordFailedDownload('),
    );

    expect(handler, contains('int? navigationRevision,'));
    expect(
      handler.indexOf(
        'final revision = navigationRevision ?? _navigationRevision;',
      ),
      inExclusiveRange(0, handler.indexOf('await ')),
    );
    expect(
      handler,
      matches(
        RegExp(
          r'final initialCourseName =\s*revision != _navigationRevision \|\|\s*'
          r'isGakujoSharedDownloadsUrl\(_currentPageUrl\)\s*'
          r'\? null\s*: _currentCourseName;',
        ),
      ),
    );
    expect(
      handler,
      matches(
        RegExp(
          r'final pageCourseName = mounted && revision == _navigationRevision\s*'
          r'\? await _estimateCourseNameFromPage\(await _controller.getTitle\(\)\)\s*'
          r': null;\s*'
          r'final courseName = resolveGakujoDownloadCourseName\(\s*'
          r'pageCourseName: pageCourseName,\s*'
          r'initialCourseName: initialCourseName,\s*'
          r'navigationRevision: revision,\s*'
          r'currentNavigationRevision: _navigationRevision,',
        ),
      ),
    );
  });
}
