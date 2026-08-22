import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final path in [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ]) {
    test('$path enables Keychain Sharing for secure storage', () async {
      final contents = await File(path).readAsString();

      expect(
        contents,
        matches(
          RegExp(
            r'<key>keychain-access-groups</key>\s*<array\s*/>',
            multiLine: true,
          ),
        ),
      );
    });
  }
}
