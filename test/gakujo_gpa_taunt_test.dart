import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/gakujo_gpa_taunt.dart';

void main() {
  for (final gpa in <double?>[null, 2.0, 3.1]) {
    testWidgets('hides the taunt for GPA $gpa', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GakujoGpaTaunt(gpa: gpa)),
      ));

      for (final message in gakujoGpaTauntMessages) {
        expect(find.text(message), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('rotates low GPA messages and stops when GPA improves',
      (tester) async {
    const interval = Duration(seconds: 6);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GakujoGpaTaunt(gpa: 1.5, interval: interval)),
    ));

    expect(find.text(gakujoGpaTauntMessages[0]), findsOneWidget);
    for (final index in [1, 2, 0]) {
      await tester.pump(interval);
      // Let the fade finish so the outgoing text is removed.
      await tester.pumpAndSettle();
      expect(find.text(gakujoGpaTauntMessages[index]), findsOneWidget);
      for (var otherIndex = 0;
          otherIndex < gakujoGpaTauntMessages.length;
          otherIndex += 1) {
        if (otherIndex != index) {
          expect(find.text(gakujoGpaTauntMessages[otherIndex]), findsNothing);
        }
      }
    }

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GakujoGpaTaunt(gpa: 2.5, interval: interval)),
    ));
    await tester.pump(interval);
    for (final message in gakujoGpaTauntMessages) {
      expect(find.text(message), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancels rotation when disposed while visible', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GakujoGpaTaunt(gpa: 1.5)),
    ));

    expect(find.text(gakujoGpaTauntMessages[0]), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
