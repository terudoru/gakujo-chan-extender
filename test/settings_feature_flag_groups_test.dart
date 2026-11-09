import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/widgets/settings_sections.dart';

void main() {
  test('settings groups contain each feature flag exactly once', () {
    final flags = settingsFeatureFlagGroups.expand((group) => group).toList();
    expect(flags.length, GakujoFeatureFlag.values.length);
    expect(flags.toSet(), GakujoFeatureFlag.values.toSet());
  });

  testWidgets('a section renders only selected flags without a heading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureFlagsSection(
            settings: const GakujoAppSettings(),
            onChanged: (_, _) {},
            title: null,
            flags: settingsGradeFeatureFlags,
          ),
        ),
      ),
    );
    expect(find.text('機能のオン/オフ'), findsNothing);
    for (final flag in GakujoFeatureFlag.values) {
      expect(
        find.text(flag.label),
        settingsGradeFeatureFlags.contains(flag)
            ? findsOneWidget
            : findsNothing,
      );
    }
  });
}
