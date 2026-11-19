import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'intercepted downloads capture and forward the origin before reading the page',
    () {
      final source = File('lib/src/gakujo_web_app.dart').readAsStringSync();
      final navigation = source.substring(
        source.indexOf(
          'Future<GakujoNavigationDecision> _handleNavigationRequest(',
        ),
        source.indexOf('Future<GakujoCourseEstimate> _estimateCourseNameFromPage('),
      );

      expect(
        navigation.indexOf('final origin = _captureDownloadCourseOrigin();'),
        inExclusiveRange(0, navigation.indexOf('await ')),
      );
      expect(
        navigation,
        matches(
          RegExp(
            r'final origin = _captureDownloadCourseOrigin\(\);\s*'
            r'final course = await _estimateDownloadCourse\(origin\);\s*'
            r'await _handleDownloadRequest\(\s*GakujoDownloadRequest\('
            r"[\s\S]*?courseName: course\.courseName \?\? '',\s*"
            r'courseNameAmbiguous: course\.isAmbiguous,[\s\S]*?\),\s*'
            r'courseOrigin: origin,\s*\);',
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

    expect(handler, contains('_DownloadCourseOrigin? courseOrigin,'));
    expect(
      handler.indexOf(
        'final origin = courseOrigin ?? _captureDownloadCourseOrigin();',
      ),
      inExclusiveRange(0, handler.indexOf('await ')),
    );
    expect(
      source,
      matches(
        RegExp(
          r'_DownloadCourseOrigin _captureDownloadCourseOrigin\(\) => \(\s*'
          r'revision: _navigationRevision,\s*document: _courseDocument,\s*'
          r'courseName: isGakujoSharedDownloadsUrl\(_currentPageUrl\)\s*'
          r'\? null\s*: _currentCourseName,\s*\);',
        ),
      ),
    );
    expect(
      handler,
      matches(
        RegExp(
          r'final course = await _estimateDownloadCourse\(\s*origin,\s*'
          r'fallback: origin\.courseName,\s*\);',
        ),
      ),
    );
    final estimate = source.substring(
      source.indexOf('Future<GakujoCourseEstimate> _estimateDownloadCourse('),
      source.indexOf('Future<void> _handleDownloadRequest('),
    );
    expect(
      estimate,
      matches(
        RegExp(
          r'const absent = GakujoCourseEstimate\.absent\(\);\s*'
          r'final estimate = mounted &&\s*origin\.revision == _navigationRevision &&\s*'
          r'origin\.document == _courseDocument\s*'
          r'\? await _estimateCourseNameFromPage\(await _controller.getTitle\(\)\)\s*'
          r': absent;[\s\S]*?return resolveGakujoDownloadCourseEstimate\(\s*'
          r'pageEstimate: mounted && origin\.document == _courseDocument\s*'
          r'\? estimate\s*: absent,\s*initialCourseName: fallback,\s*'
          r'navigationRevision: origin\.revision,\s*'
          r'currentNavigationRevision: _navigationRevision,',
        ),
      ),
    );
  });
}
