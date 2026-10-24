part of 'gakujo_web_app.dart';

extension _GakujoWebAppReportDrafts on _GakujoWebAppState {
  Future<bool> _hasReportDraftPage() async {
    final url = await _controller.currentUrl();
    if (!mounted) return false;
    if (AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
      return true;
    }
    _showSnackBar('学務情報システムのページを開いてから使ってください');
    return false;
  }

  Future<List<Map<String, dynamic>>> _loadReportDrafts() async {
    final result = await _controller.runJavaScriptReturningResult(
      GakujoReportDraftScript.buildList(),
    );
    final decoded = jsonDecode(_stringFromJavaScriptResult(result));
    if (decoded is! List) {
      throw const FormatException('Invalid report draft list');
    }
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> _showReportDraftsDialog() async {
    try {
      if (!await _hasReportDraftPage()) return;
      var drafts = await _loadReportDrafts();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('下書き'),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('下書きはこの端末の学務ページ内に14日間保存されます。'),
                  const SizedBox(height: 12),
                  if (drafts.isEmpty)
                    const Text('保存済みの下書きはありません。')
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: drafts.length,
                        itemBuilder: (context, index) {
                          final draft = drafts[index];
                          final savedAt = DateTime.fromMillisecondsSinceEpoch(
                            (draft['savedAt'] as num).toInt(),
                          );
                          return ListTile(
                            title: Text(draft['heading'] as String),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_formatDateTime(savedAt)),
                                Text(draft['preview'] as String),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () async {
                                        await Clipboard.setData(ClipboardData(
                                          text: draft['text'] as String,
                                        ));
                                        if (!dialogContext.mounted) return;
                                        _showSnackBar('下書きをコピーしました');
                                      },
                                      icon: const Icon(Icons.copy_outlined),
                                      label: const Text('コピー'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: dialogContext,
                                          builder: (confirmContext) =>
                                              AlertDialog(
                                            title: const Text('下書きを削除しますか？'),
                                            // Old drafts share a generic page
                                            // title, so show which one this is.
                                            content: Text(
                                              '${draft['heading']}\n'
                                              '${_formatDateTime(savedAt)} 保存\n'
                                              '${draft['preview']}',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  confirmContext,
                                                ).pop(false),
                                                child: const Text('キャンセル'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  confirmContext,
                                                ).pop(true),
                                                child: const Text('削除'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed != true ||
                                            !dialogContext.mounted) {
                                          return;
                                        }
                                        try {
                                          if (!await _hasReportDraftPage()) {
                                            return;
                                          }
                                          final result = await _controller
                                              .runJavaScriptReturningResult(
                                            GakujoReportDraftScript.buildDelete(
                                              draft['key'] as String,
                                            ),
                                          );
                                          if (!_boolFromJavaScriptResult(
                                            result,
                                          )) {
                                            throw StateError(
                                              'Report draft deletion failed',
                                            );
                                          }
                                          final refreshed =
                                              await _loadReportDrafts();
                                          if (!dialogContext.mounted) return;
                                          setDialogState(() {
                                            drafts = refreshed;
                                          });
                                        } on Object catch (error, stackTrace) {
                                          developer.log(
                                            'Failed to delete report draft',
                                            name: 'MoreBetterGakujo',
                                            error: error,
                                            stackTrace: stackTrace,
                                          );
                                          if (!dialogContext.mounted) return;
                                          _showSnackBar('下書きを削除できませんでした');
                                        }
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('削除'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ),
      );
    } on Object catch (error, stackTrace) {
      developer.log('Failed to load report drafts',
          name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      if (mounted) _showSnackBar('下書きを読み込めませんでした');
    }
  }
}
