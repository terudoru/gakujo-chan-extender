import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/widgets/linux_snack_bar_strip.dart';

void main() {
  testWidgets('shows text and action, and closes after the action', (tester) async {
    var invoked = false;
    final snackBar = buildTransientGakujoSnackBar(
      '保存しました',
      action: SnackBarAction(label: '開く', onPressed: () => invoked = true),
    );
    await tester.pumpWidget(MaterialApp(
      home: _StripHost(initialSnackBar: snackBar),
    ));

    expect(find.text('保存しました'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('保存しました'), findsOneWidget);
    await tester.tap(find.text('開く'));
    await tester.pump();
    expect(invoked, isTrue);
    expect(find.text('保存しました'), findsNothing);
  });

  testWidgets('closes and automatically dismisses after the SnackBar duration',
      (tester) async {
    final host = GlobalKey<_StripHostState>();
    await tester.pumpWidget(MaterialApp(
      home: _StripHost(
        key: host,
        initialSnackBar: buildTransientGakujoSnackBar('閉じるテスト'),
      ),
    ));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('閉じるテスト'), findsNothing);

    host.currentState!.show(buildTransientGakujoSnackBar('自動で閉じる'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('自動で閉じる'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('自動で閉じる'), findsNothing);

    host.currentState!.show(buildTransientGakujoSnackBar(
      'アクション付き',
      action: SnackBarAction(label: '開く', onPressed: () {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('アクション付き'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('アクション付き'), findsNothing);
  });

  testWidgets('replacement resets the timer even for the same text', (tester) async {
    final host = GlobalKey<_StripHostState>();
    await tester.pumpWidget(MaterialApp(
      home: _StripHost(
        key: host,
        initialSnackBar: buildTransientGakujoSnackBar('メッセージ'),
      ),
    ));
    await tester.pump(const Duration(seconds: 6));
    host.currentState!.show(buildTransientGakujoSnackBar('メッセージ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('メッセージ'), findsOneWidget);
    host.currentState!.show(buildTransientGakujoSnackBar('新しいメッセージ'));
    await tester.pump();
    expect(find.text('メッセージ'), findsNothing);
    expect(find.text('新しいメッセージ'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('新しいメッセージ'), findsNothing);
  });
}

class _StripHost extends StatefulWidget {
  const _StripHost({super.key, required this.initialSnackBar});

  final SnackBar initialSnackBar;

  @override
  State<_StripHost> createState() => _StripHostState();
}

class _StripHostState extends State<_StripHost> {
  SnackBar? snackBar;

  @override
  void initState() {
    super.initState();
    snackBar = widget.initialSnackBar;
  }

  void show(SnackBar value) => setState(() => snackBar = value);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            if (snackBar != null)
              LinuxSnackBarStrip(
                snackBar: snackBar!,
                onDismiss: () => setState(() => snackBar = null),
              ),
          ],
        ),
      );
}
