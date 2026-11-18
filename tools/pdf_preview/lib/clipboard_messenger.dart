import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Routes every Flutter copy action, including text selection shortcuts, to
/// the app. The sandboxed viewer cannot use the browser's clipboard API.
class PreviewClipboardBinding extends WidgetsFlutterBinding {
  PreviewClipboardBinding({required this.writeText, required this.onError});

  final Future<void> Function(String) writeText;
  final VoidCallback onError;

  @override
  BinaryMessenger createBinaryMessenger() => PreviewClipboardMessenger(
    super.createBinaryMessenger(),
    writeText: writeText,
    onError: onError,
  );
}

class PreviewClipboardMessenger extends BinaryMessenger {
  PreviewClipboardMessenger(
    this.delegate, {
    required this.writeText,
    required this.onError,
  });

  final BinaryMessenger delegate;
  final Future<void> Function(String) writeText;
  final VoidCallback onError;
  static const _codec = JSONMethodCodec();
  Future<void> _lastCopy = Future<void>.value();

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel == 'flutter/platform' && message != null) {
      final call = _codec.decodeMethodCall(message);
      if (call.method == 'Clipboard.setData') {
        return _copy((call.arguments as Map)['text'] as String);
      }
    }
    return delegate.send(channel, message);
  }

  Future<ByteData> _copy(String text) async {
    final operation = _lastCopy.then((_) => writeText(text));
    // A failed copy must not block a later attempt. Queue writes so a slow
    // request cannot overwrite a newer selection after it has been copied.
    _lastCopy = operation.then<void>((_) {}, onError: (Object _) {});
    try {
      await operation;
      return _codec.encodeSuccessEnvelope(null);
    } catch (_) {
      onError();
      return _codec.encodeErrorEnvelope(
        code: 'copy_failed',
        message: 'テキストをコピーできませんでした。もう一度お試しください。',
      );
    }
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // Required by BinaryMessenger for callers still using this API.
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(channel, data, callback);
}
