import 'dart:convert';

import 'package:collection/collection.dart';

import 'download_file_name_policy.dart';

const maxGakujoDownloadBytes = 512 * 1024 * 1024;

class GakujoDownloadRequest {
  const GakujoDownloadRequest({
    required this.url,
    required this.method,
    required this.courseName,
    required this.fileName,
    required this.formFields,
    this.formFieldPairs,
    this.courseNameAmbiguous = false,
  });

  final String url;
  final String method;
  final String courseName;
  final String fileName;
  final Map<String, String> formFields;
  final List<List<String>>? formFieldPairs;
  final bool courseNameAmbiguous;

  List<List<String>> get orderedFormFields =>
      formFieldPairs ??
      [for (final field in formFields.entries) [field.key, field.value]];

  List<List<String>> get canonicalFormFields {
    final grouped = orderedFormFields.groupListsBy((field) => field[0]);
    return [
      for (final name in grouped.keys.sorted())
        for (final field in grouped[name]!) [name, field[1]],
    ];
  }

  static List<List<String>>? _parsePairs(Object? raw) {
    if (raw is! List) return null;
    return [
      for (final pair in raw)
        if (pair is List &&
            pair.length == 2 &&
            pair[0] != null &&
            pair[1] != null)
          [pair[0].toString(), pair[1].toString()],
    ];
  }

  factory GakujoDownloadRequest.fromJsonText(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Download payload must be an object');
    }
    return GakujoDownloadRequest._fromMap(
      raw,
      mimeType: raw['mimeType']?.toString(),
    );
  }

  Map<String, Object?> toMethodChannelArguments({String? userAgent}) {
    return {
      'url': url,
      'method': method,
      'courseName': courseName,
      'fileName': fileName,
      'formFields': formFields,
      if (formFieldPairs != null) 'formFieldPairs': formFieldPairs,
      if (courseNameAmbiguous) 'courseNameAmbiguous': true,
      if (userAgent != null && userAgent.isNotEmpty) 'userAgent': userAgent,
    };
  }

  Map<String, Object?> toJson() {
    return {
      'url': url,
      'method': method,
      'courseName': courseName,
      'fileName': fileName,
      'formFields': formFields,
      if (formFieldPairs != null) 'formFieldPairs': formFieldPairs,
      if (courseNameAmbiguous) 'courseNameAmbiguous': true,
    };
  }

  /// Serializes without POST form fields for file or clipboard output.
  Map<String, Object?> toExternalJson() {
    final uri = Uri.tryParse(url);
    final publicOrigin = uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/'
        : 'about:blank';
    return {
      'url': publicOrigin,
      'method': method,
      'courseName': courseName,
      'fileName': fileName,
    };
  }

  factory GakujoDownloadRequest.fromJsonMap(Map<dynamic, dynamic> raw) =>
      GakujoDownloadRequest._fromMap(raw);

  factory GakujoDownloadRequest._fromMap(
    Map<dynamic, dynamic> raw, {
    String? mimeType,
  }) {
    final rawFields = raw['formFields'];
    final fields = <String, String>{};
    if (rawFields is Map) {
      rawFields.forEach((key, value) {
        if (key != null && value != null) {
          fields[key.toString()] = value.toString();
        }
      });
    }

    final rawFileName = raw['fileName']?.toString();
    final fileName = !DownloadFileNamePolicy.isUsefulDisplayedName(rawFileName)
        ? ''
        : DownloadFileNamePolicy.safeFileName(
            preferredName: rawFileName,
            url: raw['url']?.toString(),
            mimeType: mimeType,
          );

    return GakujoDownloadRequest(
      url: raw['url']?.toString() ?? '',
      method: (raw['method']?.toString() ?? 'GET').toUpperCase(),
      courseName:
          DownloadFileNamePolicy.safeFolderName(raw['courseName']?.toString()),
      fileName: fileName,
      formFields: fields,
      formFieldPairs: _parsePairs(raw['formFieldPairs']),
      courseNameAmbiguous: raw['courseNameAmbiguous'] == true,
    );
  }
}

class GakujoDownloadOperationGate {
  GakujoDownloadOperationGate({
    this.duplicateCaptureWindow = const Duration(milliseconds: 250),
    this.maxConcurrentDownloads = 4,
  });

  final Duration duplicateCaptureWindow;
  final int maxConcurrentDownloads;
  final Map<String, DateTime> _recentRequestStarts = <String, DateTime>{};
  final Set<String> _activeOperationIds = <String>{};
  var _nextOperationId = 0;

  bool get atCapacity => _activeOperationIds.length >= maxConcurrentDownloads;

  String? tryStart(GakujoDownloadRequest request, {DateTime? now}) {
    if (atCapacity) return null;
    final startedAt = now ?? DateTime.now();
    _recentRequestStarts.removeWhere(
      (_, previous) {
        final elapsed = startedAt.difference(previous);
        return elapsed.isNegative || elapsed > const Duration(minutes: 1);
      },
    );
    final requestKey = _requestKey(request);
    final previousStart = _recentRequestStarts[requestKey];
    final elapsed =
        previousStart == null ? null : startedAt.difference(previousStart);
    if (elapsed != null &&
        !elapsed.isNegative &&
        elapsed < duplicateCaptureWindow) {
      return null;
    }

    _recentRequestStarts[requestKey] = startedAt;
    final operationId = '${_nextOperationId++}:$requestKey';
    _activeOperationIds.add(operationId);
    return operationId;
  }

  void finish(String operationId) {
    _activeOperationIds.remove(operationId);
  }

  String _requestKey(GakujoDownloadRequest request) {
    final url = Uri.tryParse(request.url)?.replace(fragment: '').toString() ??
        request.url;
    return jsonEncode([
      request.method.toUpperCase(),
      url,
      ...request.canonicalFormFields,
    ]);
  }
}
