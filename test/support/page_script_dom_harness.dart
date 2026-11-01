import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<Map<String, dynamic>> evaluatePageScriptLifecycle({
  required String feature,
  required String buildScript,
  required String teardownScript,
}) async {
  final result = await Process.run(
      'node',
      [
        'test/support/page_script_dom_harness.cts',
        feature,
        buildScript,
        teardownScript,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8);

  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> evaluateMessageReaderScript({
  required String buildScript,
  required List<int?> fetchStatuses,
  List<String?> fetchBodies = const [],
  bool supportsAbortController = true,
  List<bool> iframeOutcomes = const [],
  String? inputValue,
  String? inputValueAfterArming,
  int clickCount = 1,
  String teardownScript = '',
  bool teardownDuringRead = false,
  bool teardownAfterRead = false,
  List<String>? messageUrls,
  Map<String, Object?> owningDocument = const {},
}) async {
  final scenario = jsonEncode({
    'fetchStatuses': fetchStatuses,
    'fetchBodies': fetchBodies,
    'supportsAbortController': supportsAbortController,
    'iframeOutcomes': iframeOutcomes,
    'inputValue': inputValue,
    'inputValueAfterArming': inputValueAfterArming,
    'clickCount': clickCount,
    'teardownDuringRead': teardownDuringRead,
    'teardownAfterRead': teardownAfterRead,
    'messageUrls': messageUrls,
    'owningDocument': owningDocument,
  });
  final result = await Process.run(
      'node',
      [
        'test/support/page_script_dom_harness.cts',
        'message',
        buildScript,
        teardownScript,
        scenario,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8);

  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}
