import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/widgets/settings_sections.dart';

void main() {
  testWidgets('compression setting can be turned off and on', (tester) async {
    var settings = const GakujoAppSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: FeatureFlagsSection(
                  settings: settings,
                  onChanged: (flag, enabled) => setState(() {
                    final disabled = {...settings.disabledFeatureFlags};
                    if (enabled) {
                      disabled.remove(flag);
                    } else {
                      disabled.add(flag);
                    }
                    settings = settings.copyWith(
                      disabledFeatureFlags: disabled,
                    );
                  }),
                ),
              );
            },
          ),
        ),
      ),
    );
    final label = find.text('5MB超の添付ファイルを自動圧縮');
    await tester.ensureVisible(label);
    await tester.tap(label);
    await tester.pump();
    expect(
      settings.isFeatureEnabled(GakujoFeatureFlag.uploadCompression),
      isFalse,
    );
    expect(find.text('5MBを超えるファイルを提出前に圧縮します。オフでもプレビューできます。'), findsOneWidget);
    await tester.tap(label);
    await tester.pump();
    expect(
      settings.isFeatureEnabled(GakujoFeatureFlag.uploadCompression),
      isTrue,
    );
  });
}
