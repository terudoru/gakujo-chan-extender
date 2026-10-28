part of 'gakujo_web_app.dart';

extension _GakujoWebAppMessageStars on _GakujoWebAppState {
  bool get _messageStarsEnabled =>
      _appSettings.isFeatureEnabled(GakujoFeatureFlag.messageStars);

  Future<void> _injectMessageStars() async {
    if (!_canRunPageScripts || !_messageStarsEnabled) return;
    try {
      final entries = await _activityStore.loadStarredMessages();
      if (!mounted || !_canRunPageScripts || !_messageStarsEnabled) return;
      await _controller.runJavaScript(
        GakujoMessageStarScript.build(
          starredIds: entries.map((entry) => entry.id),
        ),
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to inject message stars',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _refreshMessageStars() async {
    if (!_canRunPageScripts || !_messageStarsEnabled) return;
    try {
      final entries = await _activityStore.loadStarredMessages();
      if (!mounted || !_canRunPageScripts || !_messageStarsEnabled) return;
      await _controller.runJavaScript(
        GakujoMessageStarScript.buildRefresh(entries.map((entry) => entry.id)),
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to refresh message star buttons',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _handleMessageStarMessage(String message) async {
    if (!_canRunPageScripts || !_messageStarsEnabled) return;
    String? action;
    try {
      final data = jsonDecode(message);
      if (data is! Map<String, dynamic>) return;
      action = data['action']?.toString();
      if (action != 'toggle' && action != 'detail') return;
      final entry = GakujoStarredMessage.fromJson({
        ...data,
        'starredAt': DateTime.now().toIso8601String(),
      });
      if (!entry.isValid) return;
      if (action == 'detail') {
        await _activityStore.refreshStarredMessage(entry);
      } else {
        final starred = await _activityStore.toggleStarredMessage(entry);
        if (mounted) {
          _showSnackBar(starred ? 'スターを付けました' : 'スターを外しました');
        }
        await _refreshMessageStars();
      }
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to save message star',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && action == 'toggle') {
        _showSnackBar('スターを保存できませんでした。もう一度お試しください');
      }
    }
  }

  Future<void> _showStarredMessagesDialog() async {
    if (!_messageStarsEnabled) return;
    var entries = await _activityStore.loadStarredMessages();
    var query = '';
    var sort = GakujoStarredMessageSort.starredNewest;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final visible = queryStarredMessages(entries, query, sort);
          final size = MediaQuery.sizeOf(context);
          return AlertDialog(
            title: const Text('スター付き連絡通知'),
            content: SizedBox(
              width: size.width < 650 ? size.width : 900,
              height: size.height * .70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '保存した通知を検索',
                      hintText: '表題・本文・差出人など',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${visible.length} / ${entries.length} 件'),
                      DropdownButton<GakujoStarredMessageSort>(
                        value: sort,
                        items: const [
                          DropdownMenuItem(
                            value: GakujoStarredMessageSort.starredNewest,
                            child: Text('スターを付けた順'),
                          ),
                          DropdownMenuItem(
                            value: GakujoStarredMessageSort.postedNewest,
                            child: Text('掲載日の新しい順'),
                          ),
                          DropdownMenuItem(
                            value: GakujoStarredMessageSort.postedOldest,
                            child: Text('掲載日の古い順'),
                          ),
                          DropdownMenuItem(
                            value: GakujoStarredMessageSort.title,
                            child: Text('表題順'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setDialogState(() => sort = value);
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(
                            child: Text('連絡通知の表題にある☆を押すと、ここに保存されます。'),
                          )
                        : visible.isEmpty
                        ? const Center(child: Text('一致する通知はありません。'))
                        : ListView.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = visible[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                title: Text(
                                  entry.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      [entry.genre, entry.sender]
                                          .where((text) => text.isNotEmpty)
                                          .join('・'),
                                    ),
                                    if (entry.postedAt.isNotEmpty)
                                      Text(entry.postedAt),
                                    if (entry.body.isNotEmpty)
                                      Text(
                                        entry.body,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  unawaited(_openStarredMessage(entry));
                                },
                                trailing: PopupMenuButton<String>(
                                  tooltip: '連絡通知の操作',
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'open',
                                      child: Text('学務で開く'),
                                    ),
                                    PopupMenuItem(
                                      value: 'saved',
                                      child: Text('保存した内容を表示'),
                                    ),
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Text('スターを外す'),
                                    ),
                                  ],
                                  onSelected: (action) async {
                                    if (action == 'remove') {
                                      try {
                                        await _activityStore
                                            .removeStarredMessage(entry.id);
                                        entries = await _activityStore
                                            .loadStarredMessages();
                                        await _refreshMessageStars();
                                        if (!dialogContext.mounted) return;
                                        setDialogState(() {});
                                        _showSnackBar('スターを外しました');
                                      } on Object {
                                        if (mounted) {
                                          _showSnackBar('スターを外せませんでした');
                                        }
                                      }
                                      return;
                                    }
                                    Navigator.of(dialogContext).pop();
                                    if (action == 'saved') {
                                      await _showSavedMessage(entry);
                                    } else {
                                      await _openStarredMessage(entry);
                                    }
                                  },
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
          );
        },
      ),
    );
  }

  Future<void> _showSavedMessage(GakujoStarredMessage entry) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存した連絡通知'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              [
                entry.title,
                if (entry.genre.isNotEmpty) 'ジャンル: ${entry.genre}',
                if (entry.sender.isNotEmpty) '連絡通知元: ${entry.sender}',
                if (entry.period.isNotEmpty) '連絡通知期間: ${entry.period}',
                if (entry.postedAt.isNotEmpty) '掲載・送信日時: ${entry.postedAt}',
                'スターを付けた日時: ${entry.starredAt.toLocal()}',
                '',
                entry.body.isEmpty
                    ? '本文は未保存です。学務で詳細を開くと、本文を最大4000文字保存します。'
                    : entry.body,
              ].join('\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _openStarredMessage(GakujoStarredMessage entry) async {
    if (_calendarOperationGate.isRunning) {
      _showSnackBar('カレンダー連携または再検出の完了後に移動してください');
      return;
    }
    if (!_canRunPageScripts) {
      _showSnackBar('学務へのログインが必要です');
      return;
    }
    _setPendingMessageUrl(null);
    final navigationRevision = ++_navigationRevision;
    final url = _currentPageUrl;
    final inFlight = _messageOpenProcessing;
    if (inFlight != null) {
      await inFlight.future;
    }
    if (url == null ||
        !_isCurrentPageCallback(url, navigationRevision) ||
        _calendarOperationGate.isRunning ||
        _messageOpenProcessing != null) {
      return;
    }
    final processing = Completer<void>();
    _messageOpenProcessing = processing;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        GakujoMessageStarScript.buildOpen(
          keijitype: entry.keijitype,
          genrecd: entry.genrecd,
          seqNo: entry.seqNo,
        ),
      );
      final decoded = jsonDecode(_stringFromJavaScriptResult(result));
      if (!_isCurrentPageCallback(url, navigationRevision)) return;
      if (decoded is! Map) throw const FormatException('Invalid open result');
      switch (decoded['status']) {
        case 'ok':
          await _loadAllowedPageUrl(decoded['url'].toString());
          return;
        case 'gone':
          _showSnackBar('学務で見つかりませんでした。保存した内容を表示します');
          await _showSavedMessage(entry);
          return;
        case 'missing':
          _showSnackBar('学務へのログインが必要です');
          return;
        default:
          _showSnackBar('学務で連絡通知を開けませんでした。もう一度お試しください');
      }
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to open starred message',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (_isCurrentPageCallback(url, navigationRevision)) {
        _showSnackBar('学務で連絡通知を開けませんでした');
      }
    } finally {
      _messageOpenProcessing = null;
      processing.complete();
    }
  }
}
