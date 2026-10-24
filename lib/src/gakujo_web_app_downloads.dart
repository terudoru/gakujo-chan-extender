// ignore_for_file: invalid_use_of_protected_member

part of 'gakujo_web_app.dart';

@visibleForTesting
Future<void> handleGakujoNativeDownload(
  GakujoWebViewDownload download, {
  required FutureOr<void> Function(GakujoDownloadRequest request) onDownload,
  required ValueChanged<String> showSnackBar,
}) async {
  final uri = Uri.tryParse(download.url);
  if (uri?.scheme == 'blob' || uri?.scheme == 'data') {
    showSnackBar('このファイルは保存できませんでした');
    return;
  }
  if (!AllowedWebOrigins.canLoad(download.url, debugAllowed: false)) {
    showSnackBar('Gakujo以外のダウンロードをブロックしました');
    return;
  }
  // Without a query this may be a POST response that cannot be replayed as GET.
  // WebView2 keeps these downloads and displays its own download UI.
  if (uri == null || uri.query.isEmpty) {
    return;
  }

  // WebView2 suggests a path in Windows' Downloads folder and appends " (n)"
  // when that folder already holds the name; the course folder does not.
  final suggestedName = download.resultFilePath
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceFirst(RegExp(r' \(\d+\)(?=\.[^.]*$|$)'), '');
  await onDownload(
    GakujoDownloadRequest(
      url: download.url,
      method: 'GET',
      // The existing download handler estimates the course from the page.
      courseName: '',
      fileName: DownloadFileNamePolicy.safeFileName(
        preferredName: suggestedName,
        url: download.url,
        mimeType: download.mimeType,
      ),
      formFields: const {},
    ),
  );
}

@visibleForTesting
String gakujoDownloadLocationLabel(String location) {
  // Keep the encoded path intact so malformed escapes survive the fallback.
  final match = RegExp(
    r'^(content|file)://([^/?#]*)([^?#]*)',
    caseSensitive: false,
  ).firstMatch(location);
  if (match == null) {
    return location;
  }

  String decodeComponent(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return value;
    } on ArgumentError {
      return value;
    }
  }

  final path = match.group(3)!;
  if (match.group(1)!.toLowerCase() == 'file') {
    return decodeComponent(path);
  }
  if (match.group(2)!.toLowerCase() !=
      'com.android.externalstorage.documents') {
    return decodeComponent(path.split('/').last);
  }

  const documentMarker = '/document/';
  const treeMarker = '/tree/';
  final documentIndex = path.lastIndexOf(documentMarker);
  final treeIndex = path.lastIndexOf(treeMarker);
  final documentId = decodeComponent(
    documentIndex >= 0
        ? path.substring(documentIndex + documentMarker.length)
        : treeIndex >= 0
            ? path.substring(treeIndex + treeMarker.length)
            : path.split('/').last,
  );
  final separator = documentId.indexOf(':');
  if (separator < 0) {
    return documentId;
  }
  final volume = documentId.substring(0, separator);
  final root = volume == 'primary' ? '内部ストレージ' : volume;
  return '$root/${documentId.substring(separator + 1)}';
}

/// Android saves downloads as SAF content URIs, which viewer apps can read
/// only through an intent that carries a read grant.
@visibleForTesting
bool opensSavedDownloadNatively(Uri uri, TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => uri.scheme == 'content',
    // iOS opens no file URL from another app; the app previews it.
    TargetPlatform.iOS => uri.scheme == 'file',
    // macOS must hold the chosen folder's security scope while opening.
    TargetPlatform.macOS => uri.scheme == 'file',
    _ => false,
  };
}

@visibleForTesting
Future<bool> recordGakujoDownloadMetadataBestEffort({
  required GakujoDownloadHistoryStore historyStore,
  required GakujoDownloadHistoryEntry historyEntry,
  String? retryEntryId,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  var succeeded = true;
  try {
    await historyStore.add(historyEntry);
  } on Object catch (error, stackTrace) {
    succeeded = false;
    onError?.call(error, stackTrace);
  }

  if (retryEntryId != null) {
    try {
      await historyStore.removeFailedDownload(retryEntryId);
    } on Object catch (error, stackTrace) {
      succeeded = false;
      onError?.call(error, stackTrace);
    }
  }
  return succeeded;
}

@visibleForTesting
Future<Map<String, dynamic>> pollWindowsWebViewDownloadResult({
  required Future<String> Function() readState,
  Future<void> Function(Uint8List bytes)? onChunk,
  Duration timeout = const Duration(minutes: 5),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  PlatformException timeoutError() => PlatformException(
        code: 'download_timeout',
        message: 'ダウンロードがタイムアウトしました',
      );
  final elapsed = Stopwatch()..start();
  final collected = onChunk == null ? BytesBuilder(copy: false) : null;
  var nextChunkIndex = 0;
  var receivedBytes = 0;
  while (elapsed.elapsed < timeout) {
    final raw = await readState().timeout(
      timeout - elapsed.elapsed,
      onTimeout: () => throw timeoutError(),
    );
    if (raw.trim().isEmpty || raw.trim() == 'null') {
      throw PlatformException(
        code: 'download_interrupted',
        message: '画面が切り替わったため取得を中断しました。元の画面から再試行してください',
      );
    }
    final state = jsonDecode(raw);
    if (state is! Map<String, dynamic>) {
      throw const FormatException(
        'WebView download state must be an object',
      );
    }
    if (state['state'] == 'chunk') {
      final encoded = state['bodyBase64'];
      if (state['index'] != nextChunkIndex ||
          encoded is! String ||
          encoded.length > 349528) {
        throw const FormatException('Invalid WebView download chunk');
      }
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty || bytes.length > 256 * 1024) {
        throw const FormatException('Invalid WebView download chunk size');
      }
      nextChunkIndex++;
      receivedBytes += bytes.length;
      if (onChunk != null) {
        final remaining = timeout - elapsed.elapsed;
        if (remaining <= Duration.zero) {
          throw timeoutError();
        }
        await onChunk(bytes).timeout(
          remaining,
          onTimeout: () => throw timeoutError(),
        );
      } else {
        collected!.add(bytes);
      }
      continue;
    }
    if (state['state'] == 'done') {
      final payload = state['payload'];
      if (payload is! Map<String, dynamic>) {
        throw const FormatException(
          'WebView download result must be an object',
        );
      }
      if (payload.containsKey('bodyBase64')) {
        throw const FormatException('Unexpected unchunked WebView download');
      }
      if (payload['ok'] == true ||
          payload.containsKey('bodyByteLength') ||
          nextChunkIndex > 0) {
        if (payload['bodyByteLength'] is! int ||
            payload['chunkCount'] is! int ||
            payload['bodyByteLength'] != receivedBytes ||
            payload['chunkCount'] != nextChunkIndex) {
          throw const FormatException('Incomplete WebView download body');
        }
        if (collected != null) payload['bodyBytes'] = collected.takeBytes();
      }
      return payload;
    }
    if (state['state'] == 'error') {
      final detail = state['message']?.toString().trim() ?? '';
      throw PlatformException(
        code: 'download_failed',
        message:
            detail.isEmpty ? 'ダウンロード通信に失敗しました' : 'ダウンロード通信に失敗しました: $detail',
      );
    }
    if (state['state'] != 'pending') {
      throw const FormatException('Unknown WebView download state');
    }
    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      break;
    }
    await Future<void>.delayed(
      pollInterval < remaining ? pollInterval : remaining,
    );
  }
  throw timeoutError();
}

@visibleForTesting
Future<AuthenticatedDownloadedFile> receiveWindowsWebViewDownload({
  required GakujoDownloadRequest request,
  required Future<void> Function() start,
  required Future<String> Function() readState,
  required Future<void> Function() cleanup,
  Directory? temporaryRoot,
}) async {
  if (!AllowedWebOrigins.canLoad(request.url, debugAllowed: false)) {
    throw PlatformException(
        code: 'blocked_url', message: 'Gakujo以外のダウンロードをブロックしました');
  }
  final directory = await (temporaryRoot ?? Directory.systemTemp)
      .createTemp('mbg-webview-download-');
  final file = File('${directory.path}${Platform.pathSeparator}payload');
  RandomAccessFile? output;
  Future<void>? inFlightWrite;
  var transferred = false;
  var fileCleanupDeferred = false;
  try {
    output = await file.open(mode: FileMode.write);
    await start().timeout(const Duration(seconds: 15));
    final decoded = await pollWindowsWebViewDownloadResult(
      readState: readState,
      onChunk: (bytes) async {
        final write = output!.writeFrom(bytes).then<void>((_) {});
        inFlightWrite = write;
        try {
          await write;
        } finally {
          if (identical(inFlightWrite, write)) {
            inFlightWrite = null;
          }
        }
      },
    );
    await output.close();
    output = null;
    final status = int.tryParse(decoded['status']?.toString() ?? '') ?? 0;
    final finalUrl = decoded['finalUrl']?.toString() ?? request.url;
    if (decoded['blocked'] == true ||
        !AllowedWebOrigins.canLoad(finalUrl, debugAllowed: false)) {
      throw PlatformException(
          code: 'blocked_url', message: 'Gakujo以外へのリダイレクトをブロックしました');
    }
    if (status < 200 || status > 299 || decoded['ok'] != true) {
      throw PlatformException(
          code: 'download_failed', message: 'ダウンロードに失敗しました HTTP $status');
    }
    final mimeType =
        decoded['mimeType']?.toString().split(';').first.trim().toLowerCase();
    final downloaded = AuthenticatedDownloadedFile.fromFile(
      file: file,
      cleanup: () async {
        await directory.delete(recursive: true);
      },
      finalUrl: finalUrl,
      mimeType: mimeType == null || mimeType.isEmpty ? null : mimeType,
      contentDispositionFileName:
          DownloadFileNamePolicy.fileNameFromContentDisposition(
              decoded['contentDisposition']?.toString()),
    );
    transferred = true;
    return downloaded;
  } finally {
    try {
      await cleanup().timeout(const Duration(seconds: 3));
    } on Object catch (error, stackTrace) {
      developer.log('Failed to clean up a Windows WebView download result',
          name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
    }
    final pendingWrite = inFlightWrite;
    if (pendingWrite != null) {
      try {
        await pendingWrite.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        final pendingOutput = output;
        output = null;
        fileCleanupDeferred = true;
        unawaited(() async {
          try {
            await pendingWrite;
          } on Object catch (error, stackTrace) {
            developer.log('A timed-out WebView download write failed',
                name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
          }
          try {
            await pendingOutput?.close();
          } on Object catch (error, stackTrace) {
            developer.log('Failed to close a temporary WebView download',
                name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
          }
          try {
            await directory.delete(recursive: true);
          } on Object catch (error, stackTrace) {
            developer.log('Failed to remove an incomplete WebView download',
                name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
          }
        }());
      } on Object catch (error, stackTrace) {
        developer.log('A timed-out WebView download write failed',
            name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      }
    }
    try {
      await output?.close();
    } on Object catch (error, stackTrace) {
      developer.log('Failed to close a temporary WebView download',
          name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
    }
    if (!transferred && !fileCleanupDeferred) {
      try {
        await directory.delete(recursive: true);
      } on Object catch (error, stackTrace) {
        developer.log('Failed to remove an incomplete WebView download',
            name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      }
    }
  }
}

extension _GakujoWebAppDownloads on _GakujoWebAppState {
  Future<void> _loadDownloadRoot() async {
    try {
      final root = await _downloadService.getDownloadRoot();
      if (!mounted) {
        return;
      }

      setState(() {
        _downloadRoot = root;
      });
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to load download root',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _checkDownloadDestinationHealth() async {
    try {
      final root = await _downloadService.getDownloadRoot();
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadRoot = root;
      });
      final needsRoot = _appSettings.downloadSaveMode.needsConfiguredRoot;
      if (!needsRoot) {
        _showSnackBar('現在の保存方式では固定保存先は不要です');
      } else if (root.isConfigured) {
        _showSnackBar('保存先は利用できます: ${root.displayName ?? root.path ?? '設定済み'}');
      } else {
        _showSnackBar('保存先を再設定してください');
      }
    } on PlatformException catch (error) {
      _showSnackBar('保存先を確認できませんでした: ${error.message ?? error.code}');
    }
  }

  Future<void> _showDownloadHistoryDialog() async {
    var entries = await _downloadHistoryStore.load();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('ダウンロード履歴'),
              content: SizedBox(
                width: 520,
                child: entries.isEmpty
                    ? const Text('まだ保存したファイルはありません。')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            dense: true,
                            title: Text(entry.fileName),
                            subtitle: Text(
                              [
                                entry.displayCourseName,
                                _formatDateTime(entry.savedAt),
                                if (entry.location != null)
                                  gakujoDownloadLocationLabel(entry.location!),
                              ].join('\n'),
                            ),
                            isThreeLine: entry.location != null,
                            trailing: entry.location == null
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: '保存場所をコピー',
                                        icon: const Icon(Icons.copy),
                                        onPressed: () {
                                          unawaited(
                                            Clipboard.setData(
                                              ClipboardData(
                                                text:
                                                    gakujoDownloadLocationLabel(
                                                        entry.location!),
                                              ),
                                            ),
                                          );
                                          Navigator.of(dialogContext).pop();
                                          _showSnackBar('保存場所をコピーしました');
                                        },
                                      ),
                                      IconButton(
                                        tooltip: '開く',
                                        icon: const Icon(Icons.open_in_new),
                                        onPressed: () {
                                          Navigator.of(dialogContext).pop();
                                          unawaited(
                                            _openSavedDownload(entry.location!),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: entries.isEmpty
                      ? null
                      : () async {
                          await _downloadHistoryStore.clear();
                          entries = const [];
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {});
                        },
                  child: const Text('履歴を削除'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('閉じる'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showFailedDownloadsDialog() async {
    var entries = await _downloadHistoryStore.loadFailedDownloads();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('失敗したダウンロード'),
              content: SizedBox(
                width: 560,
                child: entries.isEmpty
                    ? const Text('再試行待ちのダウンロードはありません。')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              entry.request.fileName.trim().isEmpty
                                  ? _displayUrl(entry.request.url)
                                  : entry.request.fileName,
                            ),
                            subtitle: Text(
                              '${entry.request.courseName.trim().isEmpty ? '未分類' : entry.request.courseName}\n'
                              '${_formatDateTime(entry.failedAt)}\n'
                              '${entry.errorMessage}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              tooltip: '再試行',
                              icon: const Icon(Icons.refresh),
                              onPressed: () async {
                                Navigator.of(dialogContext).pop();
                                await _handleDownloadRequest(
                                  entry.request,
                                  retryEntryId: entry.id,
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: entries.isEmpty
                      ? null
                      : () async {
                          await _downloadHistoryStore.clearFailedDownloads();
                          entries = const [];
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {});
                        },
                  child: const Text('キューを削除'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('閉じる'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCourseMaterialsDialog() async {
    final entries = await _downloadHistoryStore.load();
    if (!mounted) {
      return;
    }

    final grouped = <String, List<GakujoDownloadHistoryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.displayCourseName, () => []).add(entry);
    }
    final courses = grouped.keys.toList()..sort();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('授業ごとの資料'),
          content: SizedBox(
            width: 560,
            child: courses.isEmpty
                ? const Text('ダウンロード履歴から授業ごとの資料一覧を作ります。')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: courses.length,
                    itemBuilder: (context, index) {
                      final course = courses[index];
                      final files = grouped[course]!;
                      return ExpansionTile(
                        title: Text(course),
                        subtitle: Text('${files.length}件'),
                        children: [
                          for (final file in files)
                            ListTile(
                              dense: true,
                              title: Text(file.fileName),
                              subtitle: Text(
                                [
                                  _formatDateTime(file.savedAt),
                                  if (file.location != null)
                                    gakujoDownloadLocationLabel(file.location!),
                                ].join('\n'),
                              ),
                              trailing: file.location == null
                                  ? null
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: '保存場所をコピー',
                                          icon: const Icon(Icons.copy),
                                          onPressed: () {
                                            unawaited(
                                              Clipboard.setData(
                                                ClipboardData(
                                                  text:
                                                      gakujoDownloadLocationLabel(
                                                          file.location!),
                                                ),
                                              ),
                                            );
                                            Navigator.of(dialogContext).pop();
                                            _showSnackBar('保存場所をコピーしました');
                                          },
                                        ),
                                        IconButton(
                                          tooltip: '開く',
                                          icon: const Icon(Icons.open_in_new),
                                          onPressed: () {
                                            Navigator.of(dialogContext).pop();
                                            unawaited(
                                              _openSavedDownload(
                                                  file.location!),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  /// Injects pdf.js/pdf-lib or JSZip when the upload compression script
  /// meets an oversized PDF or Office file.
  Future<void> _handleUploadCompressionLibraryRequest(String message) async {
    if (!_canRunPageScripts ||
        !_appSettings.isFeatureEnabled(GakujoFeatureFlag.uploadCompression)) {
      return;
    }
    try {
      final script = await GakujoUploadCompressionLibraries.scriptFor(message);
      if (script == null) {
        return;
      }
      await _controller.runJavaScript(script);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to inject upload compression libraries',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _handleNativeDownload(GakujoWebViewDownload download) async {
    if (!mounted) {
      return;
    }
    await handleGakujoNativeDownload(
      download,
      onDownload: _handleDownloadRequest,
      showSnackBar: _showSnackBar,
    );
  }

  Future<void> _handleDownloadMessage(String message) async {
    if (!_appSettings.isFeatureEnabled(GakujoFeatureFlag.downloadCapture)) {
      return;
    }
    late final GakujoDownloadRequest request;
    try {
      request = GakujoDownloadRequest.fromJsonText(message);
      if (kDebugMode) {
        debugPrint(
          'MoreBetterGakujo download candidate ${request.method} '
          '${_displayUrl(request.url)} as "${request.fileName}" '
          'course="${request.courseName}"',
        );
      }
    } on FormatException {
      _setStatus('保存エラー: ダウンロード情報を読めませんでした');
      _showSnackBar('ダウンロード情報を読めませんでした');
      return;
    }

    await _handleDownloadRequest(request);
  }

  Future<void> _handleDownloadRequest(
    GakujoDownloadRequest request, {
    String? retryEntryId,
  }) async {
    if (!AllowedWebOrigins.canLoad(
      request.url,
      debugAllowed: _debugAllowed,
    )) {
      _setStatus('ブロック: ${_displayUrl(request.url)}');
      _showSnackBar('Gakujo以外のダウンロードをブロックしました');
      return;
    }

    final operationKey = _downloadOperationGate.tryStart(request);
    if (operationKey == null) {
      if (kDebugMode) {
        debugPrint(
          'Ignored duplicate in-flight download ${request.method} '
          '${_displayUrl(request.url)}',
        );
      }
      return;
    }

    var effectiveRequest = request;
    try {
      if (!_isUsefulCourseName(request.courseName)) {
        final pageCourseName =
            await _estimateCourseNameFromPage(await _controller.getTitle());
        final cachedCourseName = _currentCourseName;
        final courseName = _isUsefulCourseName(pageCourseName)
            ? pageCourseName
            : _isUsefulCourseName(cachedCourseName ?? '')
                ? cachedCourseName!
                : null;
        if (courseName != null) {
          effectiveRequest = GakujoDownloadRequest(
            url: request.url,
            method: request.method,
            courseName: courseName,
            fileName: request.fileName,
            formFields: request.formFields,
          );
        }
      }
      if (kDebugMode) {
        debugPrint(
          'Download request course="${effectiveRequest.courseName}" '
          'file="${effectiveRequest.fileName}"',
        );
      }

      var root = _downloadRoot;
      if (_appSettings.downloadSaveMode.needsConfiguredRoot) {
        root = await _downloadService.getDownloadRoot();
        if (!mounted) {
          return;
        }
        setState(() {
          _downloadRoot = root;
        });
      }
      if (_appSettings.downloadSaveMode.needsConfiguredRoot &&
          !root.isConfigured) {
        _showSnackBar('ダウンロード保存先を選択してください');
        root = await _downloadService.pickDownloadRoot();
        if (!mounted) {
          return;
        }
        setState(() {
          _downloadRoot = root;
        });
        if (!root.isConfigured) {
          return;
        }
      }

      _setStatus('ダウンロード中: ${effectiveRequest.fileName}');
      final result = await _downloadService.download(
        effectiveRequest,
        userAgent: await _userAgent(),
        cookieHeader: await _cookieHeader(effectiveRequest.url),
        sharePositionOrigin: _sharePositionOrigin(),
        saveMode: _appSettings.downloadSaveMode,
      );
      final historyRecorded = await recordGakujoDownloadMetadataBestEffort(
        historyStore: _downloadHistoryStore,
        historyEntry: GakujoDownloadHistoryEntry(
          fileName: result.fileName,
          courseName: result.courseName.isEmpty
              ? effectiveRequest.courseName
              : result.courseName,
          savedAt: DateTime.now(),
          location: _nonEmptyOrNull(result.location),
        ),
        retryEntryId: retryEntryId,
        onError: (error, stackTrace) {
          developer.log(
            'Download was saved but its history metadata could not be updated',
            name: 'MoreBetterGakujo',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
      final savedPath = result.courseName.isEmpty
          ? result.fileName
          : '${result.courseName}/${result.fileName}';
      _setStatus(
        result.alreadySaved
            ? '保存済みのファイルと同じ内容のため、新しく保存しませんでした: $savedPath'
            : historyRecorded
                ? '保存しました: $savedPath'
                : '保存しました（履歴は更新できませんでした）: $savedPath',
      );
      _showDownloadSavedSnackBar(
        result,
        historyRecorded: historyRecorded,
      );
    } on PlatformException catch (error) {
      final message = error.message ?? error.code;
      if (isCancelledDownloadError(error)) {
        _setStatus('保存をキャンセルしました');
        _showSnackBar(message);
        return;
      }
      await _recordFailedDownload(effectiveRequest, message);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Unexpected error while preparing or saving a download',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      await _recordFailedDownload(effectiveRequest, error.toString());
    } finally {
      _downloadOperationGate.finish(operationKey);
    }
  }

  Future<void> _recordFailedDownload(
    GakujoDownloadRequest request,
    String message,
  ) async {
    var queued = false;
    try {
      await _downloadHistoryStore.addFailedDownload(
        request: request,
        errorMessage: message,
      );
      queued = true;
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to add a download to the retry queue',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!mounted) {
      return;
    }
    _setStatus('保存エラー: $message');
    _showSnackBar(
      queued ? '保存できませんでした。失敗キューに追加しました: $message' : '保存できませんでした: $message',
    );
  }

  Future<String?> _userAgent() async {
    final result = await _controller.runJavaScriptReturningResult(
      'navigator.userAgent',
    );
    return _stringFromJavaScriptResult(result);
  }

  Rect? _sharePositionOrigin() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  String? get _downloadDestinationHelperText {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    return 'iCloud Drive はフォルダ指定と自動仕分けに対応します。Google Drive に保存する場合は「自動仕分けなし+適宜保存場所指定」を使います。';
  }

  Future<String?> _cookieHeader(String url) async {
    final cookieStoreHeader = await _controller.cookieHeaderForUrl(url);
    if (cookieStoreHeader != null && cookieStoreHeader.trim().isNotEmpty) {
      return cookieStoreHeader;
    }

    // WebView2 does not currently expose its complete cookie store through the
    // controller. document.cookie can contain only a non-HttpOnly subset and
    // would make the downloader skip the authenticated WebView-session path.
    if (Platform.isWindows) {
      return null;
    }

    if (!_canRunPageScripts) {
      return null;
    }

    try {
      final result = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      return _stringFromJavaScriptResult(result);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to read WebView cookie header',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<AuthenticatedDownloadedFile> _downloadBytesWithWebViewSession(
    GakujoDownloadRequest request, {
    String? userAgent,
  }) async {
    if (!Platform.isWindows) {
      throw PlatformException(
        code: 'unsupported_platform',
        message: 'WebViewセッションでの取得はWindows専用です',
      );
    }
    if (!AllowedWebOrigins.canLoad(request.url, debugAllowed: false)) {
      throw PlatformException(
        code: 'blocked_url',
        message: 'Gakujo以外のダウンロードをブロックしました',
      );
    }

    final requestId = 'download-${DateTime.now().microsecondsSinceEpoch}-'
        '${_webViewDownloadRequestSequence++}';
    return receiveWindowsWebViewDownload(
      request: request,
      start: () => _controller.runJavaScript(
        WindowsWebViewAuthenticatedDownloadScript.start(
          requestId: requestId,
          request: request,
        ),
      ),
      readState: () async => _stringFromJavaScriptResult(
        await _controller.runJavaScriptReturningResult(
          WindowsWebViewAuthenticatedDownloadScript.poll(requestId),
        ),
      ),
      cleanup: () => _controller.runJavaScript(
        WindowsWebViewAuthenticatedDownloadScript.cleanup(requestId),
      ),
    );
  }

  Future<void> _injectDownloadCaptureIfAllowed() async {
    if (!_canRunPageScripts ||
        !_appSettings.isFeatureEnabled(GakujoFeatureFlag.downloadCapture)) {
      return;
    }

    try {
      await _controller.runJavaScript(GakujoDownloadCaptureScript.build());
    } catch (error, stackTrace) {
      developer.log(
        'Failed to inject download capture script',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _showDownloadSavedSnackBar(
    GakujoDownloadResult result, {
    required bool historyRecorded,
  }) {
    if (!mounted) {
      return;
    }

    final location = _nonEmptyOrNull(result.location);
    final savedPath = result.courseName.isEmpty
        ? result.fileName
        : '${result.courseName}/${result.fileName}';
    _showSnackBar(
      result.alreadySaved
          ? '保存済みのファイルと同じ内容のため、新しく保存しませんでした: $savedPath'
          : historyRecorded
              ? '保存しました: ${result.fileName}'
              : '保存しました: ${result.fileName}（履歴の更新のみ失敗しました）',
      action: location == null
          ? null
          : SnackBarAction(
              label: '開く',
              onPressed: () => unawaited(_openSavedDownload(location)),
            ),
    );
  }

  Future<void> _openSavedDownload(String location) async {
    final uri = savedDownloadLocationUri(location);
    final launched = opensSavedDownloadNatively(uri, defaultTargetPlatform)
        ? await _openSavedDownloadNatively(uri)
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showSnackBar('ファイルを開けませんでした');
    }
  }

  Future<bool> _openSavedDownloadNatively(Uri uri) async {
    try {
      final opened = await _gakujoNativeDownloadsChannel.invokeMethod<bool>(
        'openDownloadedFile',
        {'location': uri.toString()},
      );
      return opened ?? false;
    } on PlatformException catch (error, stackTrace) {
      developer.log(
        'Failed to open saved download',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  String _downloadRootLabel(DownloadDestinationSettings root) {
    return downloadRootLabel(root, includePath: true);
  }
}
