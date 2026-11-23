part of 'gakujo_web_app.dart';

extension _AssignmentFileActions on _GakujoWebAppState {
  static const _attachmentLimit = 64 * 1024 * 1024;
  static const _attachmentChunkSize = 256 * 1024;

  bool get _supportsIncomingAttachments => Platform.isAndroid || Platform.isIOS;

  void _initializeIncomingAttachments() {
    _incomingAttachments.pending.addListener(_onIncomingAttachmentChanged);
    _incomingAttachments.error.addListener(_onIncomingAttachmentError);
    unawaited(_incomingAttachments.initialize());
  }

  void _onIncomingAttachmentError() {
    final message = _incomingAttachments.error.value;
    if (mounted && message != null) _showSnackBar(message);
  }

  void _onIncomingAttachmentChanged() {
    if (!mounted) return;
    if (_incomingAttachments.pending.value != null) {
      _showSnackBar(
        '共有ファイルを受け取りました。課題の添付欄で選べます。',
        action: SnackBarAction(
          label: '課題一覧',
          onPressed: () => unawaited(_loadAllowedPageUrl(_reportListPortalUrl)),
        ),
      );
    }
    unawaited(_updateAssignmentFileControls());
  }

  Future<void> _updateAssignmentFileControls() async {
    final drop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if ((!_supportsIncomingAttachments && !drop) || !_canRunPageScripts) return;
    try {
      await _controller.runJavaScript(
        gakujoAssignmentAttachmentJs({
          'scan': Platform.isIOS,
          'drop': drop,
          'shared': _incomingAttachments.pending.value != null,
        }),
      );
    } catch (_) {
      // The WebView can move to another page while a share enters the app.
    }
  }

  Future<void> _handleAssignmentAttachment(String message) async {
    if (!_supportsIncomingAttachments ||
        !_canRunPageScripts ||
        _receivingAssignmentAttachment ||
        message.length > 2048) {
      return;
    }
    final dynamic data;
    try {
      data = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (data is! Map<String, dynamic>) return;
    final id = data['id'];
    final kind = data['kind'];
    final accept = data['accept'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        accept is! String ||
        accept.length > 1024 ||
        (kind != 'share' && !(kind == 'scan' && Platform.isIOS))) {
      return;
    }

    final revision = _navigationRevision;
    final origin = jsonEncode(Uri.parse(AllowedWebOrigins.gakujoUrl).origin);
    bool current() =>
        mounted && _canRunPageScripts && revision == _navigationRevision;
    Future<bool> call(String method, List<Object> args) async {
      if (!current()) return false;
      final arguments = args.map(jsonEncode).join(',');
      final result = await _controller.runJavaScriptReturningResult(
        '(location.origin === $origin && '
        'window.__MBG_ASSIGNMENT_ATTACHMENT?.$method($arguments) === true)',
      );
      return current() && (result == true || result.toString() == 'true');
    }

    _receivingAssignmentAttachment = true;
    XFile? scanned;
    try {
      if (!await call('pending', [id])) return;
      final pending = kind == 'share'
          ? _incomingAttachments.pending.value
          : null;
      if (kind == 'share' && pending == null) return;
      if (pending != null) {
        if (!pending.supportsAccept(accept.split(','))) {
          _showSnackBar('この添付欄では、共有されたファイル形式を使えません');
          return;
        }
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('共有したファイルを添付'),
            content: Text(pending.name),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('この欄に添付'),
              ),
            ],
          ),
        );
        if (confirmed != true ||
            !current() ||
            !identical(pending, _incomingAttachments.pending.value)) {
          return;
        }
      } else {
        if (!mounted) return;
        scanned = await showGakujoPhotoPdfScanner(context);
        if (scanned == null || !current()) return;
      }

      final file = File(pending?.path ?? scanned!.path);
      final name = pending?.name ?? scanned!.name;
      final mime = pending?.mimeType ?? 'application/pdf';
      final size = await file.length();
      if (!current()) return;
      if (size < 1 || size > _attachmentLimit) {
        _showSnackBar('このファイルのサイズでは添付できません');
        return;
      }
      if (!await call('begin', [id, name, mime, size])) {
        if (current()) _showSnackBar('添付欄の状態が変わりました。もう一度選んでください');
        return;
      }
      final handle = await file.open();
      try {
        var remaining = size;
        var index = 0;
        while (remaining > 0) {
          if (!current()) return;
          final length = remaining < _attachmentChunkSize
              ? remaining
              : _attachmentChunkSize;
          final bytes = await handle.read(length);
          if (bytes.length != length ||
              !await call('chunk', [id, index, base64Encode(bytes)])) {
            if (current()) _showSnackBar('ファイルを添付できませんでした');
            return;
          }
          remaining -= length;
          index += 1;
        }
        if (!await call('finish', [id])) {
          if (current()) _showSnackBar('ファイルを添付できませんでした');
          return;
        }
      } finally {
        await handle.close();
      }
      if (pending != null) _incomingAttachments.clear(pending);
      if (current()) _showSnackBar('ファイルを添付しました');
    } catch (_) {
      if (current()) _showSnackBar('ファイルを添付できませんでした');
    } finally {
      if (current()) {
        try {
          await _controller.runJavaScript(
            'window.__MBG_ASSIGNMENT_ATTACHMENT?.cancel(${jsonEncode(id)})',
          );
        } catch (_) {}
      }
      _receivingAssignmentAttachment = false;
      if (scanned != null) await discardGakujoPhotoPdf(scanned);
    }
  }

  Future<void> _handleWorksheetExport(String message) async {
    if (!_canRunPageScripts || _exportingWorksheet || message.length > 2048) {
      return;
    }
    final dynamic data;
    try {
      data = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (data is! Map<String, dynamic>) return;
    final id = data['id'];
    final name = data['name'];
    final size = data['size'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        name is! String ||
        name.isEmpty ||
        name.length > 250 ||
        size is! int ||
        size < 5 ||
        size > _attachmentLimit) {
      return;
    }

    _exportingWorksheet = true;
    final revision = _navigationRevision;
    bool current() =>
        mounted && _canRunPageScripts && revision == _navigationRevision;
    var saved = false;
    try {
      final requestId = jsonEncode(id);
      final bytes = BytesBuilder(copy: false);
      for (var offset = 0; offset < size; offset += _attachmentChunkSize) {
        if (!current()) return;
        final raw = await _controller.runJavaScriptReturningResult(
          'window.__MBG_WORKSHEET_EXPORT?.chunk($requestId,$offset) ?? ""',
        );
        final encoded = _stringFromJavaScriptResult(raw);
        final length = size - offset < _attachmentChunkSize
            ? size - offset
            : _attachmentChunkSize;
        if (encoded.length != ((length + 2) ~/ 3) * 4 || !current()) return;
        final chunk = base64Decode(encoded);
        if (chunk.length != length ||
            (offset == 0 &&
                !listEquals(chunk.take(5).toList(), ascii.encode('%PDF-')))) {
          return;
        }
        bytes.add(chunk);
      }
      if (!current()) return;
      final service = _downloadService;
      if (service is! FileSystemGakujoDownloadService) return;
      await service.exportEditedPdf(bytes.takeBytes(), name);
      saved = true;
      if (current()) _showSnackBar('書き込んだPDFを保存しました');
    } catch (_) {
      // The editor keeps the changes if saving fails or is cancelled.
    } finally {
      _exportingWorksheet = false;
      if (current()) {
        try {
          await _controller.runJavaScript(
            'window.__MBG_WORKSHEET_EXPORT?.reply(${jsonEncode(id)},$saved)',
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _handlePdfReadingProgress(String message) async {
    if (!_canRunPageScripts || message.length > 256) return;
    final dynamic data;
    try {
      data = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (data is! Map<String, dynamic>) return;
    final key = data['key'];
    if (key is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) return;
    final page = data['page'];
    if (page is int && page >= 1 && page <= GakujoPdfReadingProgress.maxPage) {
      try {
        await _pdfReadingProgress.save(key, page);
      } catch (_) {
        // Reading can continue if the application data cannot be saved.
      }
      return;
    }
    final request = data['request'];
    if (request is! int || request < 1 || request > 0x7fffffff) return;
    final revision = _navigationRevision;
    try {
      final saved = await _pdfReadingProgress.read(key);
      if (!mounted || !_canRunPageScripts || revision != _navigationRevision) {
        return;
      }
      await _controller.runJavaScript(
        'window.__MBG_PDF_READING_PROGRESS?.($request, ${saved ?? 'null'})',
      );
    } catch (_) {
      // The viewer can still open at the first page.
    }
  }
}
