import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/gakujo_toolbar_actions.dart';
import 'package:morebettergakujo_flutter/src/widgets/linux_native_toolbar_tooltips.dart';

void main() {
  testWidgets(
    'all toolbar tooltips reach GTK without changing button actions',
    (tester) async {
      const channel = MethodChannel('com.abandoft.webview_all_linux');
      final messages = <String?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'setFlutterTooltip');
            messages.add((call.arguments as Map)['message'] as String?);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: LinuxNativeToolbarTooltips(
                child: AppBar(
                  toolbarHeight: 40,
                  actions: [
                    GakujoNavigationActions(
                      canGoBack: true,
                      canGoForward: true,
                      onBack: () => presses++,
                      onForward: () {},
                    ),
                    GakujoReloadAction(enabled: true, onReload: () {}),
                    GakujoZoomActions(
                      zoomPercent: 100,
                      canZoomOut: true,
                      canZoomIn: true,
                      onZoomOut: () {},
                      onReset: () {},
                      onZoomIn: () {},
                    ),
                    IconButton(
                      tooltip: 'スター付き連絡通知',
                      onPressed: () {},
                      icon: const Icon(Icons.star_outline),
                    ),
                    IconButton(
                      tooltip: 'AKIKO（空き講義室検索・CIRCLE 運営の外部サービス）',
                      onPressed: () {},
                      icon: const Icon(Icons.meeting_room_outlined),
                    ),
                    IconButton(
                      tooltip: '設定',
                      onPressed: () {},
                      icon: const Icon(Icons.settings),
                    ),
                    PopupMenuButton<int>(
                      tooltip: 'メニュー',
                      itemBuilder: (_) => [],
                    ),
                  ],
                ),
              ),
            ),
            body: const SizedBox.expand(key: Key('webview')),
          ),
        ),
      );
      final top = tester.getTopLeft(find.byKey(const Key('webview'))).dy;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      for (final label in [
        '前のページ',
        '次のページ',
        '再読み込み',
        '縮小',
        '拡大',
        'スター付き連絡通知',
        'AKIKO（空き講義室検索・CIRCLE 運営の外部サービス）',
        '設定',
        'メニュー',
      ]) {
        await mouse.moveTo(tester.getCenter(find.byTooltip(label)));
        await tester.pump();
        expect(messages.last, label);
        expect(tester.getTopLeft(find.byKey(const Key('webview'))).dy, top);
      }
      await mouse.moveTo(const Offset(10, 200));
      await tester.pump();
      expect(messages.last, isNull);
      await tester.tap(find.byTooltip('前のページ'));
      expect(presses, 1);
    },
  );
}
