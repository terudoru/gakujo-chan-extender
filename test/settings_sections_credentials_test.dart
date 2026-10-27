import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/settings_sections.dart';

void main() {
  for (final hasCallbacks in [false, true]) {
    final visibility = hasCallbacks ? 'shown' : 'hidden';
    final Future<void> Function()? callback = hasCallbacks ? () async {} : null;

    testWidgets('login credential actions are $visibility', (tester) async {
      await _pumpSection(
        tester,
        LoginCredentialsSection(
          isConfigured: true,
          canSave: true,
          onLoginIdChanged: (_) {},
          onPasswordChanged: (_) {},
          onSave: callback,
          onClear: callback,
        ),
      );

      final matcher = hasCallbacks ? findsOneWidget : findsNothing;
      expect(find.text('ログイン情報を保存'), matcher);
      expect(find.text('ログイン情報を削除'), matcher);
      expect(find.byType(Wrap), matcher);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('two-factor secret actions are $visibility', (tester) async {
      await _pumpSection(
        tester,
        TwoFactorSecretSection(
          canSave: true,
          onChanged: (_) {},
          onSave: callback,
          onClear: callback,
        ),
      );

      final matcher = hasCallbacks ? findsOneWidget : findsNothing;
      expect(find.text('秘密鍵を保存'), matcher);
      expect(find.text('秘密鍵を削除'), matcher);
      expect(find.byType(Wrap), matcher);
      expect(find.byType(TextField), findsOneWidget);
    });
  }
}

Future<void> _pumpSection(WidgetTester tester, Widget section) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: section),
    ),
  ));
}
