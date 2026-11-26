import 'dart:convert';
import 'dart:io';

/// Runs a node harness with its arguments passed through temp files: the
/// scripts exceed Windows' command-line length limit when inlined.
Future<ProcessResult> runNodeWithTempFiles(
  String tempPrefix,
  List<String> harnessAndArgs, {
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) async {
  final dir = Directory.systemTemp.createTempSync(tempPrefix);
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
