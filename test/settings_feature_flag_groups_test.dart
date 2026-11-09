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
            flags: settingsReportFeatureFlags,
          ),
        ),
      ),
    );
    expect(find.text('機能のオン/オフ'), findsNothing);
    for (final flag in GakujoFeatureFlag.values) {
      expect(
        find.text(flag.label),
        settingsReportFeatureFlags.contains(flag)
            ? findsOneWidget
            : findsNothing,
      );
    }
  });

  testWidgets('page settings retain the remaining controls', (tester) async {
    final keywords = TextEditingController();
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              GakujoPageModeSection(
                pageMode: GakujoPageMode.values.first,
                onChanged: (_) {},
              ),
              FeatureFlagsSection(
                settings: const GakujoAppSettings(),
                flags: settingsReportFeatureFlags,
                onChanged: (_, _) {},
              ),
              MessageExcludeKeywordsSection(
                keywords: const [],
                controller: keywords,
                canAdd: false,
                onChanged: (_) {},
                onAdd: () async {},
                onRemove: (_) async {},
              ),
            ]),
          ),
        ),
      ));
      expect(find.text('開く画面'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile,
          GakujoFeatureFlag.uploadCompression.label), findsOneWidget);
      expect(find.text('連絡通知の除外キーワード'), findsOneWidget);
      for (final label in [
        'GPA表示', 'レポート並び替え',
        '連絡通知の一括既読', '連絡通知のスター',
      ]) {
        expect(find.widgetWithText(CheckboxListTile, label), findsNothing);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      keywords.dispose();
    }
  });
}
