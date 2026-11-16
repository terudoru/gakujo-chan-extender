import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  test(
    'data management guards reentry before clearing and only pops its route',
    () {
      final source = File('lib/src/gakujo_web_app.dart').readAsStringSync();
      final dialog = source.substring(
        source.indexOf('Future<void> _showDataManagementDialog()'),
        source.indexOf('Future<void> _checkForUpdatesAfterInitialPage()'),
      );

      expect(dialog, contains('var isClearing = false;'));
      expect(dialog, contains('StatefulBuilder('));
      expect(
        dialog,
        matches(
          RegExp(
            r'onPressed: isClearing\s*\? null\s*: \(\) async \{\s*'
            r'if \(isClearing\) return;\s*'
            r'setDialogState\(\(\) => isClearing = true\);\s*try \{\s*'
            r'await clearAll\(\);\s*'
            r'if \(!dialogContext\.mounted \|\|\s*'
            r'ModalRoute\.of\(dialogContext\)\?\.isCurrent != true\) \{\s*'
            r'return;\s*\}\s*Navigator\.of\(dialogContext\)\.pop\(\);',
          ),
        ),
      );
      expect(
        dialog,
        matches(
          RegExp(
            r'finally \{\s*if \(dialogContext\.mounted &&\s*'
            r'ModalRoute\.of\(dialogContext\)\?\.isCurrent == true\) \{\s*'
            r'setDialogState\(\(\) => isClearing = false\);',
          ),
        ),
      );
    },
  );

  test('open favorites reloads on sync and only removes its own callback', () {
    final source = File('lib/src/gakujo_web_app.dart').readAsStringSync();
    final dialog = source.substring(
      source.indexOf('Future<void> _showFavoritesDialog('),
      source.indexOf('Future<void> _openGakujoHome()'),
    );

    expect(
      dialog,
      matches(
        RegExp(
          r'refreshFavorites \?\?= \(\) async \{\s*'
          r'final updatedFavorites = await _activityStore\.loadFavorites\(\);\s*'
          r'if \(!dialogContext\.mounted\) return;\s*'
          r'setDialogState\(\(\) => favorites = updatedFavorites\);\s*\};\s*'
          r'_refreshOpenFavorites = refreshFavorites;',
        ),
      ),
    );
    expect(
      dialog,
      matches(
        RegExp(
          r'if \(identical\(_refreshOpenFavorites, refreshFavorites\)\) \{\s*'
          r'_refreshOpenFavorites = null;\s*\}',
        ),
      ),
    );
  });

  testWidgets('dialog inputs remain alive through the exit animation', (
    tester,
  ) async {
    final controller = TextEditingController();
    var disposed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
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
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(disposed, isFalse);
    await tester.pumpAndSettle();
    expect(disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final apply in [false, true]) {
    testWidgets(
      'calendar title survives exit animation on ${apply ? 'apply' : 'cancel'}',
      (tester) async {
        final controller = TextEditingController(text: '授業予定');
        var resultReceived = false;
        var disposed = false;
        String? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    ModalRoute<String>? dialogRoute;
                    try {
                      result = await showDialog<String>(
                        context: context,
                        builder: (dialogContext) {
                          dialogRoute = ModalRoute.of<String>(dialogContext);
                          return AlertDialog(
                            content: TextField(controller: controller),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext)
                                        .pop(apply ? controller.text : null),
                                child: const Text('閉じる'),
                              ),
                            ],
                          );
                        },
                      );
                    } finally {
                      resultReceived = true;
                      await dialogRoute?.completed;
                      controller.dispose();
                      disposed = true;
                    }
                  },
                  child: const Text('開く'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('開く'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '新しい授業予定');
        await tester.tap(find.text('閉じる'));
        await tester.pump();

        expect(resultReceived, isTrue);
        expect(disposed, isFalse);
        expect(find.byType(TextField), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 50));
        expect(disposed, isFalse);
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(disposed, isTrue);
        expect(result, apply ? '新しい授業予定' : isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
