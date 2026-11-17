import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  Future<void> showSnapshotGuard(
    WidgetTester tester, {
    required ValueNotifier<bool> obscured,
    required GlobalKey<LinuxOverlayGuardState> key,
    required Future<Uint8List?> Function() takeSnapshot,
    ValueNotifier<int>? navigation,
    bool forceObscured = false,
  }) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: 2),
        child: child!,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 200,
          child: LinuxOverlayGuard(
            key: key,
            obscured: obscured,
            forceObscured: forceObscured,
            navigation: navigation,
            takeSnapshot: takeSnapshot,
            child: const Text('native page'),
          ),
        ),
      ),
    ),
  );

  Uint8List pagePng() =>
      File('macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png')
          .readAsBytesSync();

  testWidgets(
    'snapshot fills the view at device scale and is dropped on close',
    (tester) async {
      final obscured = ValueNotifier(false);
      final key = GlobalKey<LinuxOverlayGuardState>();
      final bytes = pagePng();
      addTearDown(obscured.dispose);
      await showSnapshotGuard(
        tester,
        obscured: obscured,
        key: key,
        takeSnapshot: () async => bytes,
      );
      await tester.runAsync(() async {
        obscured.value = true;
        await key.currentState!.snapshotReady;
      });
      await tester.pump();
      expect(find.text('native page'), findsNothing);
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as MemoryImage;
      expect(provider.bytes, same(bytes));
      expect(provider.scale, 2);
      expect(image.gaplessPlayback, isTrue);
      expect(image.filterQuality, FilterQuality.none);
      expect(tester.getSize(find.byType(Image)), const Size(320, 200));

      obscured.value = false;
      await tester.pump();
      expect(find.text('native page'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
        PaintingBinding.instance.imageCache.containsKey(provider),
        isFalse,
      );
    },
  );

  testWidgets(
    'slow snapshots keep the page for at most 150ms and ignore late bytes',
    (tester) async {
      final obscured = ValueNotifier(false);
      final key = GlobalKey<LinuxOverlayGuardState>();
      final pending = Completer<Uint8List?>();
      addTearDown(obscured.dispose);
      await showSnapshotGuard(
        tester,
        obscured: obscured,
        key: key,
        takeSnapshot: () => pending.future,
      );
      obscured.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 149));
      expect(find.text('native page'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('native page'), findsNothing);
      expect(find.byType(Image), findsNothing);
      pending.complete(pagePng());
      await tester.pump();
      expect(find.byType(Image), findsNothing);

      obscured.value = false;
      await tester.pump();
      expect(find.text('native page'), findsOneWidget);
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'unavailable snapshot falls back without blocking overlays ($fails)',
      (tester) async {
        final obscured = ValueNotifier(false);
        final key = GlobalKey<LinuxOverlayGuardState>();
        addTearDown(obscured.dispose);
        await showSnapshotGuard(
          tester,
          obscured: obscured,
          key: key,
          takeSnapshot: () async {
            if (fails) throw StateError('renderer unavailable');
            return null;
          },
        );
        obscured.value = true;
        await tester.pump();
        expect(find.text('native page'), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('navigation drops both current and pending snapshots', (
    tester,
  ) async {
    final obscured = ValueNotifier(false);
    final navigation = ValueNotifier(0);
    final key = GlobalKey<LinuxOverlayGuardState>();
    final pending = Completer<Uint8List?>();
    var captures = 0;
    addTearDown(obscured.dispose);
    addTearDown(navigation.dispose);
    await showSnapshotGuard(
      tester,
      obscured: obscured,
      navigation: navigation,
      key: key,
      takeSnapshot: () =>
          ++captures == 1 ? pending.future : Future.value(pagePng()),
    );
    obscured.value = true;
    await tester.pump();
    navigation.value++;
    await tester.pump();
    pending.complete(pagePng());
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('native page'), findsNothing);

    obscured.value = false;
    await tester.pump();
    await tester.runAsync(() async {
      obscured.value = true;
      await key.currentState!.snapshotReady;
    });
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(captures, 2);
    navigation.value++;
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('native page'), findsNothing);
  });

  testWidgets(
    'closing or disposing during capture ignores the pending result',
    (tester) async {
      final obscured = ValueNotifier(false);
      final key = GlobalKey<LinuxOverlayGuardState>();
      final pending = Completer<Uint8List?>();
      addTearDown(obscured.dispose);
      await showSnapshotGuard(
        tester,
        obscured: obscured,
        key: key,
        takeSnapshot: () => pending.future,
      );
      obscured.value = true;
      await tester.pump();
      obscured.value = false;
      await tester.pump();
      expect(find.text('native page'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      pending.complete(pagePng());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings can prepare a snapshot before pushing their route', (
    tester,
  ) async {
    final obscured = ValueNotifier(false);
    final key = GlobalKey<LinuxOverlayGuardState>();
    addTearDown(obscured.dispose);
    Future<Uint8List?> takeSnapshot() async => pagePng();
    await showSnapshotGuard(
      tester,
      obscured: obscured,
      key: key,
      takeSnapshot: takeSnapshot,
    );
    await tester.runAsync(() async {
      await showSnapshotGuard(
        tester,
        obscured: obscured,
        key: key,
        takeSnapshot: takeSnapshot,
        forceObscured: true,
      );
      await key.currentState!.snapshotReady;
    });
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    await showSnapshotGuard(
      tester,
      obscured: obscured,
      key: key,
      takeSnapshot: takeSnapshot,
    );
    expect(find.text('native page'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('one snapshot stays under nested dialogs until the final exit', (
    tester,
  ) async {
    final observer = LinuxOverlayObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    final guardKey = GlobalKey<LinuxOverlayGuardState>();
    var captures = 0;
    ModalRoute<void>? firstRoute;
    addTearDown(observer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: Scaffold(
          body: LinuxOverlayGuard(
            key: guardKey,
            obscured: observer.obscured,
            takeSnapshot: () async {
              captures++;
              return pagePng();
            },
            child: const Text('native page'),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      unawaited(
        showDialog<void>(
          context: navigatorKey.currentContext!,
          builder: (context) {
          firstRoute = ModalRoute.of<void>(context);
          return const AlertDialog(content: Text('first dialog'));
        },
        ),
      );
      await guardKey.currentState!.snapshotReady;
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    unawaited(
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('nested dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(captures, 1);
    expect(find.byType(Image), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => firstRoute!.completed.timeout(const Duration(seconds: 1)),
    );
    await tester.pump();
    expect(observer.obscured.value, isFalse);
    expect(find.byType(Image), findsNothing);
    expect(find.text('native page'), findsOneWidget);
  });

  testWidgets('bad PNG data falls back without an image decode error', (
    tester,
  ) async {
    final obscured = ValueNotifier(false);
    final key = GlobalKey<LinuxOverlayGuardState>();
    addTearDown(obscured.dispose);
    await showSnapshotGuard(
      tester,
      obscured: obscured,
      key: key,
      takeSnapshot: () async => Uint8List.fromList([1, 2, 3]),
    );
    await tester.runAsync(() async {
      obscured.value = true;
      await key.currentState!.snapshotReady;
    });
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('native page'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing an obscured guard ignores the pending snapshot', (
    tester,
  ) async {
    final obscured = ValueNotifier(false);
    final key = GlobalKey<LinuxOverlayGuardState>();
    final pending = Completer<Uint8List?>();
    addTearDown(obscured.dispose);
    await showSnapshotGuard(
      tester,
      obscured: obscured,
      key: key,
      takeSnapshot: () => pending.future,
    );
    obscured.value = true;
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(pagePng());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
