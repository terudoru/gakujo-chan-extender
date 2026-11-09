import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/linux_overlay_guard.dart';

void main() {
  testWidgets('hides the web view for menus and nested dialogs until closed',
      (tester) async {
    final observer = LinuxOverlayObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(observer.dispose);

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      home: Scaffold(
        body: LinuxOverlayGuard(
          obscured: observer.obscured,
          child: const Text('web view'),
        ),
        appBar: AppBar(actions: [
          PopupMenuButton<int>(itemBuilder: (_) => [
                const PopupMenuItem(value: 1, child: Text('menu item')),
              ]),
        ]),
      ),
    ));
    expect(find.text('web view'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    expect(find.text('menu item'), findsOneWidget);
    expect(find.text('web view'), findsNothing);

    unawaited(showDialog<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('dialog')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);
    expect(find.text('web view'), findsNothing);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('menu item'), findsOneWidget);
    expect(find.text('web view'), findsNothing);

    navigatorKey.currentState!.pop();
    await tester.pump();
    expect(find.text('web view'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('web view'), findsOneWidget);
  });
}
