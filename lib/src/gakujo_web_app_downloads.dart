// ignore_for_file: invalid_use_of_protected_member

part of 'gakujo_web_app.dart';

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
                              '${entry.displayCourseName}\n'
                              '${_formatDateTime(entry.savedAt)}'
                              '${entry.location == null ? '' : '\n${entry.location}'}',
                            ),
                            isThreeLine: entry.location != null,
                            trailing: entry.location == null
                                ? null
                                : IconButton(
                                    tooltip: '保存場所をコピー',
                                    icon: const Icon(Icons.copy),
                                    onPressed: () {
                                      unawaited(
                                        Clipboard.setData(
                                          ClipboardData(text: entry.location!),
                                        ),
                                      );
                                      Navigator.of(dialogContext).pop();
                                      _showSnackBar('保存場所をコピーしました');
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
                              subtitle: Text(_formatDateTime(file.savedAt)),
                              trailing: file.location == null
                                  ? null
                                  : IconButton(
                                      tooltip: '保存場所をコピー',
                                      icon: const Icon(Icons.copy),
                                      onPressed: () {
                                        unawaited(
                                          Clipboard.setData(
                                            ClipboardData(text: file.location!),
                                          ),
                                        );
                                        Navigator.of(dialogContext).pop();
                                        _showSnackBar('保存場所をコピーしました');
                                      },
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
        historyRecorded
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
    await _controller.runJavaScript(
      WindowsWebViewAuthenticatedDownloadScript.start(
        requestId: requestId,
        request: request,
      ),
    );

    late final Map<String, dynamic> decoded;
    try {
      decoded = await _pollWindowsWebViewDownloadResult(requestId);
    } finally {
      try {
        await _controller.runJavaScript(
          WindowsWebViewAuthenticatedDownloadScript.cleanup(requestId),
        );
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to clean up a Windows WebView download result',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    final status = int.tryParse(decoded['status']?.toString() ?? '') ?? 0;
    final finalUrl = decoded['finalUrl']?.toString() ?? request.url;
    if (decoded['blocked'] == true) {
      throw PlatformException(
        code: 'blocked_url',
        message: 'Gakujo以外へのリダイレクトをブロックしました',
      );
    }
    if (!AllowedWebOrigins.canLoad(finalUrl, debugAllowed: false)) {
      throw PlatformException(
        code: 'blocked_url',
        message: 'Gakujo以外へのリダイレクトをブロックしました',
      );
    }
    if (status < 200 || status > 299 || decoded['ok'] != true) {
      throw PlatformException(
        code: 'download_failed',
        message: 'ダウンロードに失敗しました HTTP $status',
      );
    }
    return AuthenticatedDownloadedFile(
      bytes: base64Decode(decoded['bodyBase64']?.toString() ?? ''),
      finalUrl: finalUrl,
      mimeType: _mimeTypeFromContentType(decoded['mimeType']?.toString()),
      contentDispositionFileName:
          DownloadFileNamePolicy.fileNameFromContentDisposition(
        decoded['contentDisposition']?.toString(),
      ),
    );
  }

  Future<Map<String, dynamic>> _pollWindowsWebViewDownloadResult(
    String requestId,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      final raw = _stringFromJavaScriptResult(
        await _controller.runJavaScriptReturningResult(
          WindowsWebViewAuthenticatedDownloadScript.poll(requestId),
        ),
      );
      if (raw.isNotEmpty && raw != 'null') {
        final state = jsonDecode(raw);
        if (state is! Map<String, dynamic>) {
          throw const FormatException(
            'WebView download state must be an object',
          );
        }
        if (state['state'] == 'done') {
          final payload = state['payload'];
          if (payload is! Map<String, dynamic>) {
            throw const FormatException(
              'WebView download result must be an object',
            );
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
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw PlatformException(
      code: 'download_timeout',
      message: 'ダウンロードがタイムアウトしました',
    );
  }

  String? _mimeTypeFromContentType(String? raw) {
    final value = raw?.split(';').first.trim().toLowerCase();
    return value == null || value.isEmpty ? null : value;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          historyRecorded
              ? '保存しました: ${result.fileName}'
              : '保存しました: ${result.fileName}（履歴の更新のみ失敗しました）',
        ),
        action: location == null
            ? null
            : SnackBarAction(
                label: '開く',
                onPressed: () => unawaited(_openSavedDownload(location)),
              ),
      ),
    );
  }

  Future<void> _openSavedDownload(String location) async {
    final uri = savedDownloadLocationUri(location);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showSnackBar('ファイルを開けませんでした');
    }
  }

  String _downloadRootLabel(DownloadDestinationSettings root) {
    return downloadRootLabel(root, includePath: true);
  }
}
