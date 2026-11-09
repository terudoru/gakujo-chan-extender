import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_download_capture_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_compression_script.dart';
import 'package:test/test.dart';

void main() {
  test(
    'compresses an oversized photo in place, keeping name and format',
    () async {
      final result = await _run({
        'files': [
          {'name': 'scan.JPG', 'type': 'image/jpeg', 'size': 12 * 1024 * 1024},
        ],
        'width': 4000,
        'height': 3000,
      });

      expect(result['stopped'], isTrue);
      expect(result['replayed'], ['input', 'change']);
      final files = result['files'] as List;
      expect(files.single['name'], 'scan.JPG');
      expect(files.single['type'], 'image/jpeg');
      expect(files.single['size'], lessThanOrEqualTo(4700000));
      expect(result['status'], contains('5MB以下に圧縮しました'));
    },
  );

  test('keeps PNG files as PNG', () async {
    final result = await _run({
      'files': [
        {'name': 'diagram.png', 'type': 'image/png', 'size': 9000000},
      ],
      'width': 3000,
      'height': 3000,
    });

    final file = (result['files'] as List).single;
    expect(file['name'], 'diagram.png');
    expect(file['type'], 'image/png');
    expect(file['size'], lessThanOrEqualTo(4700000));
  });

  test('compresses files above 5,000,000 bytes, even below 5 MiB', () async {
    final result = await _run({
      'files': [
        {'name': 'scan.jpg', 'type': 'image/jpeg', 'size': 5000001},
      ],
      'width': 2000,
      'height': 2000,
    });
    expect(result['stopped'], isTrue);
    expect(result['files'].single['size'], lessThanOrEqualTo(4700000));
  });

  test('requests the PDF libraries from the app', () async {
    final result = await _run({
      'channel': true,
      'files': [
        {'name': 'report.pdf', 'type': 'application/pdf', 'size': 8000000},
      ],
    });

    expect(result['stopped'], isTrue);
    expect(result['channelMessages'], ['pdf']);
    expect(result['status'], contains('PDFを圧縮しています'));
  });

  test('keeps a PDF above the safe input limit without starting a worker', () async {
    final result = await _run({
      'files': [
        {'name': 'large.pdf', 'type': 'application/pdf', 'size': 64 * 1024 * 1024 + 1},
      ],
      'pdf': <String, Object?>{},
    });
    expect(result['originalsKept'], isTrue);
    expect(result['workerCreated'], 0);
    expect(result['status'], contains('64 MiB'));
  });

  test('does not start a second PDF compression while another is running', () async {
    final result = await _run({
      'files': [_pdf],
      'pdf': <String, Object?>{},
      'pdfAlreadyRunning': true,
    });
    expect(result['originalsKept'], isTrue);
    expect(result['workerCreated'], 0);
    expect(result['status'], contains('別のPDFを圧縮中'));
  });

  test('cancelled PDF reads do not overlap a reselected file', () async {
    final result = await _run({
      'files': [_pdf],
      'nextFiles': [_pdf],
      'pdf': <String, Object?>{},
      'holdPdfRead': true,
    });
    expect(result['pdfReadCount'], 1);
    expect(result['maxPdfReads'], 1);
    expect(result['workerCreated'], 0);
    expect(result['files'].single['size'], 8000000);
  });

  test('requests JSZip for Word files', () async {
    final result = await _run({
      'channel': true,
      'files': [
        {'name': 'report.docx', 'type': '', 'size': 8000000},
      ],
    });

    expect(result['channelMessages'], ['office']);
  });

  test('terminates a stalled PDF worker on timeout', () async {
    final result = await _run({
      'files': [_pdf],
      'pdf': {'hold': true},
      'compressionTimeout': true,
    });
    expect(result['workerTerminated'], 1);
    expect(result['pending'], isFalse);
    expect(result['originalsKept'], isTrue);
    expect(result['consoleRestored'], isTrue);
  });

  test(
    'a cancelled PDF never starts a worker after libraries load late',
    () async {
      final result = await _run({
        'files': [_pdf],
        'pdf': <String, Object?>{},
        'channel': true,
        'latePdfLibrary': true,
        'nextFiles': [_photo],
      });
      expect(result['workerCreated'], 0);
      expect(result['files'].single['name'], 'scan.jpg');
    },
  );

  test(
    'bounds real Office archive expansion and preserves normal content',
    () async {
      for (final bomb in [false, true]) {
        final result = await _run({
          'files': [
            {'name': 'report.docx', 'type': '', 'size': 8000000},
          ],
          'realOffice': true,
          'officeBomb': bomb,
        });
        expect(result['originalsKept'], bomb);
        if (bomb) {
          expect(result['status'], contains('大きすぎます'));
        } else {
          expect(result['officeContent'], 'normal office content');
          expect(result['status'], contains('5MB以下に圧縮しました'));
        }
      }
    },
  );

  test('rejects ZIP64 directory metadata before invoking JSZip', () async {
    final result = await _run({
      'files': [
        {'name': 'report.docx', 'type': '', 'size': 8000000},
      ],
      'realOffice': true,
      'officeZip64': true,
    });
    expect(result['originalsKept'], isTrue);
    expect(result['officeParseCalls'], 0);
    expect(result['status'], contains('文書の構造'));
  });

  test('rejects oversized image dimensions before invoking the decoder', () async {
    final result = await _run({
      'files': [
        {'name': 'photo.png', 'type': 'image/png', 'size': 8000000},
      ],
      'headerWidth': 10001,
    });
    expect(result['originalsKept'], isTrue);
    expect(result['bitmapCalls'], 0);
    expect(result['status'], contains('ピクセル数'));
  });

  test('keeps the original file when the libraries are unavailable', () async {
    final result = await _run({
      'files': [
        {'name': 'report.pdf', 'type': 'application/pdf', 'size': 8000000},
      ],
    });

    expect(result['stopped'], isTrue);
    expect(result['replayed'], ['input', 'change']);
    expect((result['files'] as List).single['size'], 8000000);
    expect(result['status'], contains('圧縮できませんでした'));
  });

  test('explains formats it cannot compress', () async {
    final result = await _run({
      'files': [
        {'name': 'data.zip', 'type': 'application/zip', 'size': 8000000},
      ],
    });

    expect(result['stopped'], isFalse);
    expect(result['status'], contains('この形式は自動で圧縮できません'));
  });

  test('ignores files that already fit', () async {
    final result = await _run({
      'files': [
        {'name': 'small.png', 'type': 'image/png', 'size': 1024},
      ],
    });

    expect(result['stopped'], isFalse);
    expect(result['status'], isNull);
  });

  test('teardown stops compressing', () async {
    final result = await _run({
      'teardownFirst': true,
      'files': [
        {'name': 'scan.jpg', 'type': 'image/jpeg', 'size': 12 * 1024 * 1024},
      ],
    });

    expect(result['stopped'], isFalse);
    expect((result['files'] as List).single['size'], 12 * 1024 * 1024);
  });

  test(
    'disabling during compression discards completion and releases submit',
    () async {
      for (final teardown in [false, true]) {
        for (final failure in [false, true]) {
          final result = await _run({
            'files': [_photo],
            'holdImage': true,
            'imageError': failure,
            'disableDuringPending': true,
            'useTeardown': teardown,
            'checkSubmission': true,
          });
          expect(result['originalsKept'], isTrue);
          expect(result['replayed'], isEmpty);
          expect(result['status'], result['statusAfterDisable']);
          expect(result['blockedWhenDisabled'], [false, false, false, false]);
          expect(result['blockedAfter'], [false, false, false, false]);
          expect(result['pending'], isFalse);
        }
      }
    },
  );

  test(
    're-enabling compression never revives a job cancelled by teardown',
    () async {
      for (final failure in [false, true]) {
        final result = await _run({
          'files': [_photo],
          'holdImage': true,
          'imageError': failure,
          'disableDuringPending': true,
          'useTeardown': true,
          'reenableDuringPending': true,
          'checkSubmission': true,
        });
        expect(result['originalsKept'], isTrue);
        expect(result['replayed'], isEmpty);
        expect(result['status'], isNull);
        expect(result['blockedAfterReenable'], [false, false, false, false]);
        expect(result['pending'], isFalse);
      }
    },
  );

  for (final failure in [false, true]) {
    test('discards stale image ${failure ? 'failure' : 'result'}', () async {
      final result = await _run({
        'files': [_photo],
        'holdImage': true,
        'imageError': failure,
        'nextFiles': [
          {'name': 'new.pdf', 'type': 'application/pdf', 'size': 1000},
        ],
      });
      expect((result['files'] as List).single['name'], 'new.pdf');
      expect(result['replayed'], isEmpty);
      expect(result['status'], isEmpty);
    });
  }

  test(
    'selection token invalidates work even for the same File object',
    () async {
      final result = await _run({
        'files': [_photo],
        'holdImage': true,
        'reselectSameFiles': true,
        'teardownBeforeReselect': true,
      });
      expect(result['originalsKept'], isTrue);
      expect(result['replayed'], isEmpty);
    },
  );

  test(
    'checks the original File identity even without a change event',
    () async {
      final result = await _run({
        'files': [_photo],
        'holdImage': true,
        'nextFiles': [_photo],
        'replaceWithoutChange': true,
      });
      expect((result['files'] as List).single['size'], _photo['size']);
      expect(result['replayed'], isEmpty);
    },
  );

  test('cancelling the selection discards an in-flight result', () async {
    final result = await _run({
      'files': [_photo],
      'holdImage': true,
      'nextFiles': <Object?>[],
    });
    expect(result['files'], isEmpty);
    expect(result['replayed'], isEmpty);
    expect(result['status'], isEmpty);
  });

  test(
    'removes timed-out waiters and requests libraries on the next pick',
    () async {
      final result = await _run({
        'files': [_pdf],
        'channel': true,
        'timeoutLibrary': true,
        'pdf': <String, Object?>{},
      });
      expect(result['channelMessages'], ['pdf', 'pdf']);
      expect(result['originalsKept'], isFalse);
      expect(result['status'], contains('5MB以下に圧縮しました'));
    },
  );

  test('replaces a PDF only when the worker succeeds', () async {
    final result = await _run({
      'files': [_pdf],
      'pdf': <String, Object?>{},
    });
    expect(result['originalsKept'], isFalse);
    expect(result['files'].single['name'], 'report.pdf');
    expect(result['status'], contains('5MB以下に圧縮しました'));
    expect(result['workerTerminated'], 1);
  });

  test('preserves all selected originals when PDF compression fails', () async {
    final result = await _run({
      'files': [_photo, _pdf],
      'pdf': {'error': '署名付きPDFは圧縮できません'},
    });
    expect(result['originalsKept'], isTrue);
    expect(result['status'], contains('署名付きPDF'));
    expect(result['replayed'], ['input', 'change']);
  });

  test('blocks only the busy form until success, error, or timeout', () async {
    for (final outcome in ['success', 'error', 'timeout']) {
      final result = await _run({
        'files': [_photo],
        'holdImage': true,
        'imageError': outcome == 'error',
        'compressionTimeout': outcome == 'timeout',
        'checkSubmission': true,
      });
      expect(result['blockedDuring'], [
        true,
        true,
        true,
        true,
      ], reason: outcome);
      expect(result['unrelatedBlocked'], [false, false]);
      expect(result['pendingStatus'], 'ファイルを圧縮しています。完了してから提出してください');
      expect(result['blockedAfter'], [false, false, false, false]);
      expect(result['listenerCounts'], {'change': 1, 'submit': 1, 'click': 1});
      expect(result['listenersCapture'], isTrue);
      expect(result['autoSubmits'], 0);
      expect(result['originalsKept'], outcome != 'success');
      expect(
        result['status'],
        contains(outcome == 'success' ? '5MB以下に圧縮しました' : '元のファイルのまま'),
      );
    }
  });

  test(
    'releases the submit hold before a replayed change handler submits',
    () async {
      for (final failure in [false, true]) {
        final result = await _run({
          'files': [_photo],
          'holdImage': true,
          'imageError': failure,
          'checkSubmission': true,
          'submitOnChange': true,
        });
        expect(result['stopped'], isTrue);
        expect(result['blockedDuring'], [true, true, true, true]);
        expect(result['submitsDuring'], 0);
        expect(result['replayed'], ['input', 'change']);
        expect(result['autoSubmits'], 1);
        expect(result['pendingOnChange'], isFalse);
        expect(result['pending'], isFalse);
        expect(result['blockedAfter'], [false, false, false, false]);
        expect(result['originalsKept'], failure);
      }
    },
  );

  test(
    'keeps only live submit hooks after 30 iframe document replacements',
    () async {
      final result = await _runNode([
        'test/support/gakujo_upload_compression_script_iframe_document_replacement_harness.cts',
        GakujoUploadCompressionScript.build(),
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    },
  );

  test(
    'blocks programmatic submits with either download hook install order',
    () async {
      final result = await _runNode([
        'test/support/gakujo_upload_compression_script_programmatic_submission_harness.cts',
        GakujoUploadCompressionScript.build(),
        GakujoUploadCompressionScript.buildTeardown(),
        GakujoDownloadCaptureScript.build(),
        GakujoDownloadCaptureScript.buildTeardown(),
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    },
  );
}

const _photo = {'name': 'scan.jpg', 'type': 'image/jpeg', 'size': 12000000};
const _pdf = {'name': 'report.pdf', 'type': 'application/pdf', 'size': 8000000};
Future<Map<String, dynamic>> _run(Map<String, Object?> scenario) async {
  final result = await _runNode(
    [
      'test/support/gakujo_upload_compression_script_harness.cts',
      GakujoUploadCompressionScript.build(),
      GakujoUploadCompressionScript.buildTeardown(),
      jsonEncode(scenario),
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}







/// Runs a node harness with its arguments passed through temp files: the
/// scripts exceed Windows' command-line length limit when inlined.
Future<ProcessResult> _runNode(
  List<String> harnessAndArgs, {
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) async {
  final dir = Directory.systemTemp.createTempSync('gakujo_upload_compression_');
  try {
    final paths = <String>[];
    for (var i = 1; i < harnessAndArgs.length; i += 1) {
      final file = File('${dir.path}${Platform.pathSeparator}arg$i.txt')
        ..writeAsStringSync(harnessAndArgs[i]);
      paths.add(file.path);
    }
    return await Process.run(
      'node',
      [harnessAndArgs.first, ...paths],
      stdoutEncoding: stdoutEncoding ?? utf8,
      stderrEncoding: stderrEncoding ?? utf8,
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}
