import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/google_drive_file_saver.dart';
import 'package:morebettergakujo_flutter/src/widgets/drive_save_folder_dialog.dart';

void main() {
  const folder = GoogleDriveFolder(id: 'child', name: 'Math', path: 'School / Math');

  testWidgets('lists folders and returns the selected folder', (tester) async {
    DriveSaveFolderResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await showDialog<DriveSaveFolderResult>(
              context: context,
              builder: (_) => DriveSaveFolderDialog(
                currentId: null,
                load: () async => [folder],
                create: (_) async => folder,
              ),
            );
          },
          child: const Text('open'),
        ),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('School / Math'), findsOneWidget);
    await tester.tap(find.text('School / Math'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result?.folder, same(folder));
  });

  testWidgets('create calls the callback and selects the new folder', (tester) async {
    String? requested;
    DriveSaveFolderResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await showDialog<DriveSaveFolderResult>(
              context: context,
              builder: (_) => DriveSaveFolderDialog(
                currentId: null,
                load: () async => [],
                create: (name) async {
                  requested = name;
                  return folder;
                },
              ),
            );
          },
          child: const Text('open'),
        ),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Math');
    await tester.tap(find.text('作成'));
    await tester.pumpAndSettle();
    expect(requested, 'Math');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result?.folder, same(folder));
  });
}
