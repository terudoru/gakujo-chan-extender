import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/google_drive_file_saver.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';
import 'package:morebettergakujo_flutter/src/widgets/drive_save_folder_dialog.dart';

const school = GoogleDriveFolder(
  id: 'child',
  name: 'Math',
  path: 'School / Math',
);
const imported = GoogleDriveFolder(
  id: 'private-folder',
  name: 'ノート',
  path: 'ノート',
);
const pickLabel = 'Google ドライブから選ぶ';

Future<void> openDialog(
  WidgetTester tester, {
  String? currentId,
  Future<List<GoogleDriveFolder>> Function()? load,
  Future<GoogleDriveFolder?> Function()? pick,
  Future<String?> Function(String)? parentId,
  Future<GoogleDriveFolder?> Function(String)? pickParent,
  Future<GoogleDriveFolder> Function(String)? create,
  required Future<void> Function(String?, DriveFolderCommit) save,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DriveSaveFolderDialog(
                currentId: currentId,
                load: load ?? () async => [school],
                pick: pick ?? () async => null,
                parentId: parentId,
                pickParent: pickParent,
                create: create ?? (_) async => school,
                save: save,
              ),
            ),
            child: const Text('開く'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('開く'));
  await tester.pumpAndSettle();
}

void main() {
  for (final action in ['load', 'pick', 'create', 'selection']) {
    testWidgets('parent lookup failure preserves successful $action without errors', (tester) async {
      final saved = <String?>[];
      await openDialog(
        tester,
        currentId: action == 'load' ? school.id : null,
        parentId: (_) async => throw StateError('parent unavailable'),
        pickParent: (_) async => imported,
        pick: () async => school,
        create: (_) async => school,
        save: (id, commit) => commit(() async => saved.add(id)),
      );
      switch (action) {
        case 'pick':
          await tester.tap(find.text(pickLabel));
        case 'create':
          await tester.enterText(find.byType(TextField), 'Math');
          await tester.tap(find.text('作成'));
        case 'selection':
          await tester.tap(find.text(school.path));
      }
      await tester.pumpAndSettle();
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(find.descendant(of: find.byWidget(dialog.title!),
        matching: find.byType(Text)), findsNWidgets(2));
      expect(find.text('一覧を再読み込み'), findsNothing);
      expect(find.text('1つ上のフォルダを選ぶ'), findsNothing);
      expect(find.text(school.path), findsOneWidget);
      expect(tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue, school.id);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, [school.id]);
    });
  }

  testWidgets('failed lookup for a new selection clears the previous parent', (tester) async {
    await openDialog(tester,
      currentId: school.id,
      load: () async => [school, imported],
      parentId: (id) async {
        if (id == school.id) return 'parent';
        throw StateError('parent unavailable');
      },
      pickParent: (_) async => null,
      save: (_, _) async {},
    );
    expect(find.text('1つ上のフォルダを選ぶ'), findsOneWidget);
    await tester.tap(find.text(imported.path));
    await tester.pumpAndSettle();
    expect(find.text('1つ上のフォルダを選ぶ'), findsNothing);
    expect(tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue, imported.id);
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(find.descendant(of: find.byWidget(dialog.title!),
      matching: find.byType(Text)), findsNWidgets(2));
  });

  const parentLabel = '1\u3064\u4e0a\u306e\u30d5\u30a9\u30eb\u30c0\u3092\u9078\u3076';
  testWidgets('parent button hides for default and root, selects parent and climbs', (tester) async {
    final picked = <String>[];
    await openDialog(tester,
      parentId: (id) async => switch (id) {
        'child' => 'parent', 'parent' => 'grandparent', _ => null,
      },
      pickParent: (id) async {
        picked.add(id);
        return GoogleDriveFolder(id: id, name: id, path: id);
      },
      save: (_, _) async {},
    );
    expect(find.text(parentLabel), findsNothing);
    await tester.tap(find.text(school.path));
    await tester.pumpAndSettle();
    expect(find.text(parentLabel), findsOneWidget);
    await tester.tap(find.text(parentLabel));
    await tester.pumpAndSettle();
    expect(picked, ['parent']);
    expect(tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue, 'parent');
    await tester.tap(find.text(parentLabel));
    await tester.pumpAndSettle();
    expect(picked, ['parent', 'grandparent']);
    expect(tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue, 'grandparent');
    expect(find.text(parentLabel), findsNothing);
  });

  testWidgets('parent cancellation preserves selection and busy disables duplicate picks', (tester) async {
    final pending = Completer<GoogleDriveFolder?>();
    var calls = 0;
    await openDialog(tester, currentId: school.id,
      parentId: (_) async => 'parent',
      pickParent: (_) { calls++; return pending.future; },
      save: (_, _) async {},
    );
    await tester.tap(find.text(parentLabel));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, parentLabel)).onPressed, isNull);
    expect(calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue, school.id);
  });

  testWidgets('lists folders and confirms the selected ID', (tester) async {
    final saved = <String?>[];
    await openDialog(
      tester,
      save: (id, commit) => commit(() async => saved.add(id)),
    );
    expect(find.text(school.path), findsOneWidget);
    await tester.tap(find.text(school.path));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, [school.id]);
    expect(find.byType(DriveSaveFolderDialog), findsNothing);
  });

  testWidgets('restores the saved ID and can switch back to default', (
    tester,
  ) async {
    final saved = <String?>[];
    await openDialog(
      tester,
      currentId: school.id,
      save: (id, commit) => commit(() async => saved.add(id)),
    );
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      school.id,
    );
    await tester.tap(find.text('既定（More Better Gakujo）'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, [null]);
  });

  testWidgets('double create and immediate save taps wait for the new folder', (
    tester,
  ) async {
    final pending = Completer<GoogleDriveFolder>();
    final names = <String>[];
    final saved = <String?>[];
    await openDialog(
      tester,
      load: () async => [],
      create: (name) {
        names.add(name);
        return pending.future;
      },
      save: (id, commit) => commit(() async => saved.add(id)),
    );
    await tester.enterText(find.byType(TextField), 'Math');
    await tester.tap(find.text('作成'));
    await tester.tap(find.text('作成'));
    await tester.tap(find.text('保存'));
    expect(names, ['Math']);
    expect(saved, isEmpty);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
          .onPressed,
      isNull,
    );
    pending.complete(school);
    await tester.pumpAndSettle();
    expect(find.text(school.path), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, [school.id]);
  });

  testWidgets(
    'picker cancel and rejection keep the saved selection and typed name; retry selects the imported ID',
    (tester) async {
      final pending = Completer<GoogleDriveFolder?>();
      var picks = 0;
      final saved = <String?>[];
      await openDialog(
        tester,
        currentId: school.id,
        pick: () async {
          switch (++picks) {
            case 1:
              return null;
            case 2:
              throw const GoogleDriveSaveFolderShared();
            default:
              return pending.future;
          }
        },
        save: (id, commit) => commit(() async => saved.add(id)),
      );
      String? selected() => tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue;
      await tester.enterText(find.byType(TextField), '入力中');
      await tester.tap(find.text(pickLabel));
      await tester.pumpAndSettle();
      expect(selected(), school.id);
      expect(find.text('入力中'), findsOneWidget);
      await tester.tap(find.text(pickLabel));
      await tester.pumpAndSettle();
      expect(find.text('ご自身が所有し、誰とも共有していないフォルダを選んでください'), findsOneWidget);
      expect(selected(), school.id);
      await tester.tap(find.text(pickLabel));
      await tester.tap(find.text(pickLabel));
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(picks, 3);
      expect(saved, isEmpty);
      pending.complete(imported);
      await tester.pumpAndSettle();
      expect(find.text(imported.name), findsOneWidget);
      expect(selected(), imported.id);
      expect(saved, isEmpty);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, [imported.id]);
    },
  );

  testWidgets('closing the dialog discards a late picker result', (
    tester,
  ) async {
    final pending = Completer<GoogleDriveFolder?>();
    final saved = <String?>[];
    await openDialog(
      tester,
      pick: () => pending.future,
      save: (id, commit) => commit(() async => saved.add(id)),
    );
    await tester.tap(find.text(pickLabel));
    await tester.pump();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    pending.complete(imported);
    await tester.pump();
    expect(saved, isEmpty);
    expect(find.byType(DriveSaveFolderDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final back in [false, true]) {
    for (final validating in [false, true]) {
      final exit = back ? 'Back' : 'Cancel';
      final phase = validating ? 'validation' : 'queue wait';
      testWidgets(
        '$exit during $phase discards the write and allows a fresh save',
        (tester) async {
          final queue = StorageOperationQueue();
          final upload = Completer<void>();
          final validation = Completer<void>();
          unawaited(queue.runExclusive(() => upload.future));
          final validated = <String?>[];
          final written = <String?>[];
          await openDialog(
            tester,
            save: (id, commit) => queue.runExclusive(() async {
              validated.add(id);
              await validation.future;
              await commit(() async => written.add(id));
            }),
          );
          await tester.tap(find.text(school.path));
          await tester.tap(find.text('保存'));
          if (validating) upload.complete();
          await tester.pump();
          expect(validated, validating ? [school.id] : isEmpty);
          expect(
            tester
                .widget<TextButton>(find.widgetWithText(TextButton, 'キャンセル'))
                .onPressed,
            isNotNull,
          );
          if (back) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.text('キャンセル'));
          }
          // Let a response arrive while the popped route is still animating out.
          if (validating) validation.complete();
          await tester.pumpAndSettle();
          expect(find.byType(DriveSaveFolderDialog), findsNothing);
          expect(written, isEmpty);

          await tester.tap(find.text('開く'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('保存'));
          if (!validating) {
            upload.complete();
            validation.complete();
          }
          await tester.pumpAndSettle();
          expect(written, [null]);
          expect(find.byType(DriveSaveFolderDialog), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'Back and Cancel are guarded as soon as writing starts and a failed write can be retried',
    (tester) async {
      final validated = Completer<void>();
      final write = Completer<void>();
      var writes = 0;
      await openDialog(
        tester,
        save: (id, commit) async {
          await validated.future;
          await commit(() async {
            if (++writes == 1) await write.future;
          });
        },
      );
      await tester.tap(find.text('保存'));
      await tester.pump();
      final cancel = find.widgetWithText(TextButton, 'キャンセル');
      final beforeCommit = tester.widget<TextButton>(cancel).onPressed!;
      validated.complete();
      await tester.idle();
      expect(writes, 1);
      beforeCommit();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(tester.widget<TextButton>(cancel).onPressed, isNull);
      write.completeError(StateError('write failed'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
      expect(find.text('保存先を変更できませんでした'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(writes, 2);
      expect(find.byType(DriveSaveFolderDialog), findsNothing);
    },
  );

  testWidgets(
    'retries the list and failed confirmation without losing the imported selection',
    (tester) async {
      var loads = 0;
      final attempts = <String?>[];
      await openDialog(
        tester,
        load: () async {
          if (++loads == 1) throw StateError('offline');
          return [school];
        },
        pick: () async => imported,
        save: (id, commit) async {
          attempts.add(id);
          if (attempts.length == 1) throw const GoogleDriveSaveFolderMissing();
        },
      );
      await tester.tap(find.text(pickLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一覧を再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text(school.path), findsOneWidget);
      expect(find.text(imported.name), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('フォルダを確認できません。保存先'), findsOneWidget);
      expect(find.byType(DriveSaveFolderDialog), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(attempts, [imported.id, imported.id]);
      expect(find.byType(DriveSaveFolderDialog), findsNothing);
    },
  );
}
