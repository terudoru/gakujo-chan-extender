import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/app_update_service.dart';

void main() {
  group('AppUpdateService version comparison', () {
    int compare(String left, String right) {
      return AppUpdateService.compareVersionsForTesting(left, right).sign;
    }

    test('compares numeric semantic versions', () {
      expect(compare('v1.2.4', '1.2.3'), 1);
      expect(compare('1.2.3', '1.2.4'), -1);
      expect(compare('1.2.3', 'v1.2.3+45'), 0);
    });

    test('keeps pre-release suffixes from erasing patch versions', () {
      expect(compare('v1.2.3-beta.1', '1.2.2'), 1);
      expect(compare('1.2.3-beta.1', '1.2.3'), 0);
      expect(compare('1.2.10-rc1', '1.2.9'), 1);
    });

    test('can recover versions from prefixed tag names', () {
      expect(compare('release-2026.6.23', '2026.6.22'), 1);
      expect(compare('MoreBetterGakujo-v0.67.1', '0.67.0'), 1);
    });
  });
}
