import 'dart:convert';

import 'download_file_name_policy.dart';

class GakujoDownloadRequest {
  const GakujoDownloadRequest({
    required this.url,
    required this.method,
    required this.courseName,
    required this.fileName,
    required this.formFields,
  });

  final String url;
  final String method;
  final String courseName;
  final String fileName;
  final Map<String, String> formFields;

  factory GakujoDownloadRequest.fromJsonText(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Download payload must be an object');
    }

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
    final fileName = rawFileName == null || rawFileName.trim().isEmpty
        ? ''
        : DownloadFileNamePolicy.safeFileName(
            preferredName: rawFileName,
            url: raw['url']?.toString(),
            mimeType: raw['mimeType']?.toString(),
          );

    return GakujoDownloadRequest(
      url: raw['url']?.toString() ?? '',
      method: (raw['method']?.toString() ?? 'GET').toUpperCase(),
      courseName:
          DownloadFileNamePolicy.safeFolderName(raw['courseName']?.toString()),
      fileName: fileName,
      formFields: fields,
    );
  }

  Map<String, Object?> toMethodChannelArguments({String? userAgent}) {
    return {
      'url': url,
      'method': method,
      'courseName': courseName,
      'fileName': fileName,
      'formFields': formFields,
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
    };
  }

  /// Serializes without POST form fields for file or clipboard output.
  Map<String, Object?> toExternalJson() {
    return {
      'url': url,
      'method': method,
      'courseName': courseName,
      'fileName': fileName,
    };
  }

  factory GakujoDownloadRequest.fromJsonMap(Map<dynamic, dynamic> raw) {
    final rawFields = raw['formFields'];
    final fields = <String, String>{};
    if (rawFields is Map) {
      rawFields.forEach((key, value) {
        if (key != null && value != null) {
          fields[key.toString()] = value.toString();
        }
      });
    }

    return GakujoDownloadRequest(
      url: raw['url']?.toString() ?? '',
      method: (raw['method']?.toString() ?? 'GET').toUpperCase(),
      courseName:
          DownloadFileNamePolicy.safeFolderName(raw['courseName']?.toString()),
      fileName: DownloadFileNamePolicy.safeFileName(
        preferredName: raw['fileName']?.toString(),
        url: raw['url']?.toString(),
      ),
      formFields: fields,
    );
  }
}

class GakujoDownloadOperationGate {
  GakujoDownloadOperationGate({
    this.duplicateCaptureWindow = const Duration(milliseconds: 250),
  });

  final Duration duplicateCaptureWindow;
  final Map<String, DateTime> _recentRequestStarts = <String, DateTime>{};
  final Set<String> _activeOperationIds = <String>{};
  var _nextOperationId = 0;

  String? tryStart(GakujoDownloadRequest request, {DateTime? now}) {
    final startedAt = now ?? DateTime.now();
    _recentRequestStarts.removeWhere(
      (_, previous) =>
          startedAt.difference(previous) > const Duration(minutes: 1),
    );
    final requestKey = _requestKey(request);
    final previousStart = _recentRequestStarts[requestKey];
    if (previousStart != null &&
        startedAt.difference(previousStart) < duplicateCaptureWindow) {
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
    final fields = request.formFields.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final url = Uri.tryParse(request.url)?.replace(fragment: '').toString() ??
        request.url;
    return jsonEncode([
      request.method.toUpperCase(),
      url,
      for (final field in fields) [field.key, field.value],
    ]);
  }
}
