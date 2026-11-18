import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A single file copied by the mobile host into its private cache.
class IncomingAttachment {
  const IncomingAttachment._(this.path, this.name, this.mimeType, this._id);

  final String path;
  final String name;
  final String mimeType;
  final String _id;

  static const _cacheDirectory = 'mbg-incoming-attachments';
  static final _cacheId = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
    caseSensitive: false,
  );
  static final _invalidName = RegExp(r'[\x00-\x1f\x7f<>:"/\\|?*]');
  static final _mimePattern = RegExp(r'^[a-z0-9.+-]+/[a-z0-9.+-]+$');

  @visibleForTesting
  static IncomingAttachment? fromHost(Object? response) {
    if (response is! Map) return null;
    final path = response['path'];
    final name = response['name'];
    final mime = response['mimeType'];
    if (path is! String ||
        name is! String ||
        mime is! String ||
        !path.startsWith('/') ||
        path.length > 2048 ||
        name.isEmpty ||
        _invalidName.hasMatch(name) ||
        !_mimePattern.hasMatch(mime)) {
      return null;
    }
    final segments = path.substring(1).split('/');
    if (segments.length < 4 ||
        segments.any((part) => part.isEmpty || part == '.' || part == '..') ||
        segments[segments.length - 3] != _cacheDirectory ||
        !_cacheId.hasMatch(segments[segments.length - 2]) ||
        segments.last != name) {
      return null;
    }
    return IncomingAttachment._(
      path,
      name,
      mime,
      segments[segments.length - 2],
    );
  }

  bool supportsAccept(List<String> acceptTypes) {
    final types = acceptTypes
        .expand((value) => value.toLowerCase().split(','))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    final fileName = name.toLowerCase();
    final primaryType = mimeType.split('/').first;
    return types.isEmpty ||
        types.any(
          (type) =>
              type == '*/*' ||
              type == mimeType ||
              type == '$primaryType/*' ||
              (type.startsWith('.') && fileName.endsWith(type)),
        );
  }
}

/// Receives files from the mobile OS. A file stays pending in this process
/// until the user explicitly attaches it or dismisses it.
class IncomingAttachmentService {
  IncomingAttachmentService({
    this._channel = const MethodChannel(
      'net.yoshida.morebettergakujo/incoming_attachment',
    ),
  });

  static final instance = IncomingAttachmentService();

  final MethodChannel _channel;
  final pending = ValueNotifier<IncomingAttachment?>(null);
  final error = ValueNotifier<String?>(null);
  Future<void>? _initialization;
  Future<void> _reads = Future<void>.value();

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'attachmentAvailable') await _queueRead();
    });
    return _queueRead();
  }

  Future<void> _queueRead() => _reads = _reads.then((_) => _read());

  Future<void> _read() async {
    try {
      final response = await _channel.invokeMethod<Object?>(
        'takePendingAttachment',
      );
      if (response == null) return;
      if (response is Map && response['error'] == 'too_large') {
        error.value = '共有ファイルは64MBまで取り込めます';
        return;
      }
      final attachment = IncomingAttachment.fromHost(response);
      if (attachment == null) {
        error.value = '共有ファイルを取り込めませんでした';
        return;
      }
      error.value = null;
      pending.value = attachment;
    } on MissingPluginException {
      // Desktop and older hosts do not implement the mobile channel.
    } on PlatformException {
      error.value = '共有ファイルを取り込めませんでした';
    }
  }

  void clear(IncomingAttachment attachment) {
    if (identical(pending.value, attachment)) pending.value = null;
    unawaited(_discard(attachment._id));
  }

  Future<void> _discard(String id) async {
    try {
      await _channel.invokeMethod<void>('discardAttachment', id);
    } on MissingPluginException {
      // A native cache can also expire on the next launch.
    } on PlatformException {
      // Keep a completed handoff complete if cache removal fails.
    }
  }
}
