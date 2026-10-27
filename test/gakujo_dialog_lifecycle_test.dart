import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  testWidgets('dialog inputs remain alive through the exit animation',
      (tester) async {
    final controller = TextEditingController();
    var disposed = false;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            ModalRoute<void>? route;
            await showDialog<void>(
              context: context,
              builder: (dialogContext) {
                route = ModalRoute.of<void>(dialogContext);
                return AlertDialog(
                  content: TextField(controller: controller),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                );
              },
            );
            await gakujoWaitForDialogDismissal(route);
            controller.dispose();
            disposed = true;
          },
          child: const Text('Open'),
        );
      }),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(disposed, isFalse);
    await tester.pumpAndSettle();
    expect(disposed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
