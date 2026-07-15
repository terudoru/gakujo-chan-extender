part of 'gakujo_web_app.dart';

extension _GakujoWebAppDiagnostics on _GakujoWebAppState {
  Future<void> _createErrorReportPackage() async {
    final includeStoredData = await _confirmDetailedErrorReport();
    if (includeStoredData == null) {
      return;
    }
    try {
      final payload = await _diagnosticPayload(
        includeStoredData: includeStoredData,
      );
      final file = await _writeJsonFile(
        directoryName: 'MoreBetterGakujoReports',
        fileName: 'error-report-${DateTime.now().microsecondsSinceEpoch}.json',
        payload: payload,
      );
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(payload),
        ),
      );
      _showSnackBar('エラー報告パッケージを作成してコピーしました: ${file.path}');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to create error report package',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('エラー報告パッケージを作成できませんでした: $error');
    }
  }

  Future<bool?> _confirmDetailedErrorReport() {
    if (!mounted) {
      return Future.value(null);
    }
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('エラー報告パッケージ'),
          content: const Text(
            '軽量版は件数と設定状態だけを含みます。詳細版は履歴、URL、失敗ダウンロード、課題キャッシュも含みます。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('軽量版'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('詳細版'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyDiagnosticInfo() async {
    final payload = await _diagnosticPayload(includeStoredData: false);
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
    );
    _showSnackBar('診断情報をコピーしました');
  }

  Future<Map<String, Object?>> _diagnosticPayload({
    required bool includeStoredData,
  }) async {
    final hasTwoFactorSecret = await _secretStore.load() != null;
    final historyCount = (await _downloadHistoryStore.load()).length;
    final failedDownloadCount =
        (await _downloadHistoryStore.loadFailedDownloads()).length;
    final snapshots = await _activityStore.loadSnapshots();
    final deadlines = await _activityStore.loadDeadlines();
    final favorites = await _activityStore.loadFavorites();
    final changes = await _activityStore.loadChanges();
    final reportLists = await _activityStore.loadReportLists();
    final payload = <String, Object?>{
      'app': 'More Better Gakujo',
      'platform': defaultTargetPlatform.name,
      'createdAt': DateTime.now().toIso8601String(),
      'canGoBack': _canGoBack,
      'canGoForward': _canGoForward,
      'downloadRootConfigured': _downloadRoot.isConfigured,
      'downloadRootLabel': downloadRootLabel(
        _downloadRoot,
        includePath: includeStoredData,
      ),
      'downloadSaveMode': _appSettings.downloadSaveMode.storageValue,
      'pageMode': _appSettings.pageMode.storageValue,
      'calendarImportSettings': _appSettings.calendarImportSettings.toJson(),
      'loginCredentialsConfigured': _appSettings.hasLoginCredentials,
      'twoFactorSecretConfigured': hasTwoFactorSecret,
      'desktopZoom': _desktopZoom,
      'downloadHistoryCount': historyCount,
      'failedDownloadCount': failedDownloadCount,
      'unseenUpdateCount':
          snapshots.where((snapshot) => snapshot.hasUpdate).length,
      'deadlineCount': deadlines.length,
      'favoriteCount': favorites.length,
      'changeHistoryCount': changes.length,
      'cachedReportListCount': reportLists.length,
    };
    if (includeStoredData) {
      payload['currentUrl'] = _displayUrl(_currentPageUrl);
      payload['lastAllowedUrl'] = _displayUrl(_lastAllowedPageUrl);
      payload['backup'] = await _backupPayload();
      payload['failedDownloads'] =
          (await _downloadHistoryStore.loadFailedDownloads())
              .map((entry) => entry.toJson())
              .toList();
    }
    return payload;
  }
}
