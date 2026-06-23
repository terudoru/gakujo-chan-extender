class DownloadFileNamePolicy {
  const DownloadFileNamePolicy._();

  static const fallbackBaseName = 'document';
  static const unknownCourseFolderName = '未分類';

  static String safeFileName({
    String? preferredName,
    String? contentDispositionName,
    String? url,
    String? mimeType,
  }) {
    final preferred = _cleanCandidate(preferredName);
    final disposition = _cleanCandidate(contentDispositionName);
    final urlName = _cleanCandidate(_fileNameFromUrl(url));
    final usableUrlName = _isCampussquareDo(urlName) ? null : urlName;
    final base = (_isCampussquareDo(preferred) ? null : preferred) ??
        disposition ??
        usableUrlName ??
        fallbackBaseName;
    return _withExtension(base, mimeType: mimeType, urlName: usableUrlName);
  }

  static String safeFolderName(String? name) {
    return _cleanCandidate(name) ?? unknownCourseFolderName;
  }

  static String courseFolderName({
    required String requestedCourseName,
    required String fileName,
  }) {
    final requested = safeFolderName(requestedCourseName);
    if (_isUsefulCourseName(requested)) {
      return requested;
    }
    return _inferCourseNameFromFileName(fileName) ?? unknownCourseFolderName;
  }

  static String uniqueName(String desiredName, Set<String> existingNames) {
    if (!existingNames.contains(desiredName)) {
      return desiredName;
    }

    final extensionIndex = desiredName.lastIndexOf('.');
    final hasExtension =
        extensionIndex > 0 && extensionIndex < desiredName.length - 1;
    final base =
        hasExtension ? desiredName.substring(0, extensionIndex) : desiredName;
    final extension = hasExtension ? desiredName.substring(extensionIndex) : '';

    var index = 1;
    while (true) {
      final candidate = '$base ($index)$extension';
      if (!existingNames.contains(candidate)) {
        return candidate;
      }
      index += 1;
    }
  }

  static String? fileNameFromContentDisposition(String? header) {
    if (header == null || header.trim().isEmpty) {
      return null;
    }

    final encodedMatch = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(header);
    if (encodedMatch != null) {
      return Uri.decodeComponent(
        encodedMatch.group(1)?.trim().replaceAll('"', '') ?? '',
      );
    }

    final quotedMatch = RegExp(
      r'''filename="?([^";]+)"?''',
      caseSensitive: false,
    ).firstMatch(header);
    return quotedMatch?.group(1);
  }

  static String? _cleanCandidate(String? raw, {String replacement = ''}) {
    final value = raw
        ?.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), replacement)
        .replaceAll(RegExp(r'''[\\/:*?"<>|]'''), replacement)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value == null || value.isEmpty || value == '.' || value == '..') {
      return null;
    }
    return value;
  }

  static String _withExtension(String base,
      {String? mimeType, String? urlName}) {
    if (_hasLikelyExtension(base) || _isCampussquareDo(base)) {
      return base;
    }

    final urlExtension = _extensionFromName(urlName).takeUnlessDo();
    final mimeExtension = _extensionFromMime(mimeType);
    final extension = urlExtension ?? mimeExtension;
    return extension == null ? base : '$base.$extension';
  }

  static bool _hasLikelyExtension(String name) {
    final extension = _extensionFromName(name);
    return extension != null && extension != 'do';
  }

  static String? _extensionFromName(String? name) {
    if (name == null) {
      return null;
    }

    final index = name.lastIndexOf('.');
    if (index <= 0 || index == name.length - 1) {
      return null;
    }

    final extension = name.substring(index + 1).toLowerCase();
    if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)) {
      return null;
    }
    return extension;
  }

  static String? _extensionFromMime(String? mimeType) {
    final normalized = mimeType?.split(';').first.trim().toLowerCase();
    return switch (normalized) {
      'application/pdf' => 'pdf',
      'text/plain' => 'txt',
      'text/csv' => 'csv',
      'application/zip' => 'zip',
      'application/msword' => 'doc',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
        'docx',
      'application/vnd.ms-excel' => 'xls',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
        'xlsx',
      'application/vnd.ms-powerpoint' => 'ppt',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
        'pptx',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      _ => null,
    };
  }

  static String? _fileNameFromUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(rawUrl);
    final segment =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : null;
    if (segment == null || segment.isEmpty) {
      return null;
    }
    return Uri.decodeComponent(segment);
  }

  static bool _isCampussquareDo(String? name) {
    return name?.toLowerCase() == 'campussquare.do';
  }

  static bool _isUsefulCourseName(String name) {
    if (name.isEmpty || name == unknownCourseFolderName) {
      return false;
    }
    const genericPageLabels = {
      '開設一覧',
      '連絡通知',
      '掲示一覧',
      '授業ポートフォリオ',
      'レポート・小テスト・アンケート提出',
      'レポート提出',
      '小テスト',
      'アンケート',
      '年度 開講所属 開講番号 科目名',
      'タイトル',
    };
    if (genericPageLabels.contains(name)) {
      return false;
    }

    final lower = name.toLowerCase();
    return !lower.contains('campussquare') &&
        !lower.contains('more better gakujo') &&
        !name.contains('学務情報システム');
  }

  static String? _inferCourseNameFromFileName(String fileName) {
    var base = fileName;
    final dot = base.lastIndexOf('.');
    if (dot > 0) {
      base = base.substring(0, dot);
    }
    base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (base.isEmpty) {
      return null;
    }

    base = base.replaceFirst(RegExp(r'^[0-9０-９]+\s*[_＿\-－ー.．]\s*'), '').trim();

    final separatedParts = <String>[];
    for (final separator in [
      '_',
      '＿',
      ' - ',
      ' – ',
      ' — ',
      '：',
      ':',
      '／',
      '/',
    ]) {
      final index = base.indexOf(separator);
      if (index > 0) {
        separatedParts.add(base.substring(0, index).trim());
      }
    }
    if (separatedParts.isNotEmpty) {
      separatedParts.sort((a, b) => a.length.compareTo(b.length));
      base = separatedParts.first;
    }

    base = base
        .replaceFirst(RegExp(r'^第\s*[0-9０-９]+\s*回\s*'), '')
        .replaceFirst(RegExp(r'^(講義|授業|資料|課題)\s*'), '')
        .trim();

    if (base.isEmpty || base.length < 3) {
      return null;
    }
    if (RegExp(r'^[0-9A-Za-z_ -]+$').hasMatch(base)) {
      return null;
    }
    final folderName = safeFolderName(base);
    return folderName == unknownCourseFolderName ? null : folderName;
  }
}

extension on String? {
  String? takeUnlessDo() {
    return this == 'do' ? null : this;
  }
}
