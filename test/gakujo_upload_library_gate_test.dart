import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_compression_libraries.dart';

void main() {
  test(
    'office preview is acknowledged before waiting previews are notified',
    () async {
      final directory = await Directory.systemTemp.createTemp('office-ack-');
      try {
        final script = File('${directory.path}/injection.js');
        final library = GakujoUploadCompressionLibraries.buildInjectionScript(
          'preview-office',
          ['window.JSZip = {};'],
        );
        await script.writeAsString(
          GakujoUploadCompressionLibraries.acknowledgedInjectionScript(
            'preview-office',
            library,
          ),
        );
        final result = await Process.run('node', [
          'test/upload_office_library_ack.mjs',
          script.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('injection acknowledges success and rolls back partial failure', () async {
    final directory = await Directory.systemTemp.createTemp('library-ack-');
    try {
      final script = File('${directory.path}/injection.js');
      await script.writeAsString(
        GakujoUploadCompressionLibraries.acknowledgedInjectionScript(
          'preview',
          '''
window.__MBG_PDF_WORKER_URL = URL.createObjectURL(new Blob([]));
if (window.fail) throw new Error('synthetic failure');
window.pdfjsLib = {};
''',
        ),
      );
      final result = await Process.run('node', [
        'test/upload_library_ack.mjs',
        script.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('concurrent requests inject once and new navigation can inject again',
      () async {
    final gate = GakujoUploadLibraryGate();
    final pending = Completer<bool>();
    var calls = 0;
    Future<bool> inject() {
      calls++;
      return pending.future;
    }

    final first = gate.run(revision: 1, kind: 'preview', inject: inject);
    final second = gate.run(revision: 1, kind: 'preview', inject: inject);
    expect(calls, 1);
    pending.complete(true);
    await Future.wait([first, second]);
    await gate.run(revision: 1, kind: 'preview', inject: inject);
    expect(calls, 1);
    await gate.run(revision: 2, kind: 'preview', inject: () async {
      calls++;
      return true;
    });
    expect(calls, 2);
  });

  test('failed or stale injection does not poison a later request', () async {
    final gate = GakujoUploadLibraryGate();
    await expectLater(
      gate.run(revision: 1, kind: 'pdf', inject: () async => throw StateError('failure')),
      throwsStateError,
    );
    final old = Completer<bool>();
    final stale = gate.run(revision: 1, kind: 'pdf', inject: () => old.future);
    var currentCalls = 0;
    await gate.run(revision: 2, kind: 'pdf', inject: () async {
      currentCalls++;
      return false;
    });
    old.complete(true);
    await stale;
    await gate.run(revision: 2, kind: 'pdf', inject: () async {
      currentCalls++;
      return true;
    });
    expect(currentCalls, 2);
  });
}
