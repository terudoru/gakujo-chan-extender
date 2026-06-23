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
}
