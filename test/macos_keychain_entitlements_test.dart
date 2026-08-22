import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final path in [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ]) {
    test('$path avoids restricted Keychain Sharing entitlement', () async {
      final contents = await File(path).readAsString();

      expect(
        contents,
        isNot(contains('<key>keychain-access-groups</key>')),
      );
    });
  }

  test('release workflow runs the macOS launch verification gate', () async {
    final workflow = await File('.github/workflows/release.yml').readAsString();
    final verifier =
        await File('scripts/verify_macos_release.sh').readAsString();

    expect(workflow, contains('bash scripts/verify_macos_release.sh'));
    expect(verifier, contains('codesign --verify --deep --strict'));
    expect(verifier, contains("-c 'Print :keychain-access-groups'"));
    expect(verifier, contains('lipo -archs'));
    expect(verifier, contains('kill -0'));
  });
}
