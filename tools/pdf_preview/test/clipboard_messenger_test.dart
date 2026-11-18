import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbg_pdf_preview/clipboard_messenger.dart';

class _Delegate extends BinaryMessenger {
  final sent = <String>[];
  final response = ByteData(1);

  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    sent.add(channel);
    return response;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {}
}

void main() {
  const codec = JSONMethodCodec();

  test('copy preserves text and waits for the OS acknowledgement', () async {
    final delegate = _Delegate();
    final written = <String>[];
    final acknowledgement = Completer<void>();
    final messenger = PreviewClipboardMessenger(
      delegate,
      writeText: (text) {
        written.add(text);
        return acknowledgement.future;
      },
      onError: () => fail('Copy unexpectedly failed'),
    );
    const text = '日本語\r\n改行と絵文字😀';
    var finished = false;
    final response = messenger.send(
      'flutter/platform',
      codec.encodeMethodCall(
        const MethodCall('Clipboard.setData', {'text': text}),
      ),
    )!;
    unawaited(response.then((_) => finished = true));
    await Future<void>.delayed(Duration.zero);
    expect(written, [text]);
    expect(finished, isFalse);
    expect(delegate.sent, isEmpty);
    acknowledgement.complete();
    expect(codec.decodeEnvelope((await response)!), isNull);
    expect(finished, isTrue);
  });

  test('failed writes return failure without exposing copied text', () async {
    var failures = 0;
    final messenger = PreviewClipboardMessenger(
      _Delegate(),
      writeText: (_) async => throw StateError('private copied content'),
      onError: () => failures++,
    );
    final response = await messenger.send(
      'flutter/platform',
      codec.encodeMethodCall(
        const MethodCall('Clipboard.setData', {'text': '秘密'}),
      ),
    );
    expect(failures, 1);
    expect(
      () => codec.decodeEnvelope(response!),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'copy_failed')
            .having((error) => error.details, 'details', isNull),
      ),
    );
  });

  test(
    'copies stay in order and a failed write does not block the next',
    () async {
      final first = Completer<void>();
      final written = <String>[];
      final messenger = PreviewClipboardMessenger(
        _Delegate(),
        writeText: (text) {
          written.add(text);
          return text == 'first' ? first.future : Future<void>.value();
        },
        onError: () {},
      );
      Future<ByteData?> copy(String text) => messenger.send(
        'flutter/platform',
        codec.encodeMethodCall(MethodCall('Clipboard.setData', {'text': text})),
      )!;
      final one = copy('first');
      final two = copy('second');
      await Future<void>.delayed(Duration.zero);
      expect(written, ['first']);
      first.completeError(StateError('failure'));
      final failedReply = await one;
      expect(
        () => codec.decodeEnvelope(failedReply!),
        throwsA(isA<PlatformException>()),
      );
      expect(codec.decodeEnvelope((await two)!), isNull);
      expect(written, ['first', 'second']);
    },
  );

  test(
    'other platform methods and channels retain their original route',
    () async {
      final delegate = _Delegate();
      final messenger = PreviewClipboardMessenger(
        delegate,
        writeText: (_) async => fail('Unexpected clipboard write'),
        onError: () => fail('Unexpected copy error'),
      );
      for (final method in [
        'Clipboard.getData',
        'Clipboard.hasStrings',
        'SystemNavigator.pop',
      ]) {
        expect(
          await messenger.send(
            'flutter/platform',
            codec.encodeMethodCall(MethodCall(method)),
          ),
          same(delegate.response),
        );
      }
      expect(
        await messenger.send('other/channel', null),
        same(delegate.response),
      );
      expect(delegate.sent, [
        'flutter/platform',
        'flutter/platform',
        'flutter/platform',
        'other/channel',
      ]);
    },
  );
}
