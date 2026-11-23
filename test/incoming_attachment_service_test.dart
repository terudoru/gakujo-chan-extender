import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/incoming_attachment_service.dart';

const channel = MethodChannel('incoming-attachment-test');
const codec = StandardMethodCodec();
const cache = '/app/cache/mbg-incoming-attachments';
const id = 'b032547d-a641-4687-a51b-2bbcb83d05c1';
const laterId = '68488b4d-5443-42b9-a40e-007f7ddf1296';

Map<String, String> attachment(
  String name,
  String mimeType, {
  String cacheId = id,
}) => {'path': '$cache/$cacheId/$name', 'name': name, 'mimeType': mimeType};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  Future<void> attachmentAvailable() async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('attachmentAvailable')),
      null,
    );
  }

  test(
    'takes cold-launch and warm shares and only clears the selected file',
    () async {
      Object? next = attachment('答案.pdf', 'application/pdf');
      var reads = 0;
      final purged = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'discardAttachment') {
          purged.add(call.arguments as String);
          return null;
        }
        expect(call.method, 'takePendingAttachment');
        reads++;
        final available = next;
        next = null;
        return available;
      });
      final service = IncomingAttachmentService(channel: channel);
      await service.initialize();
      await service.initialize();
      expect(reads, 1);
      final first = service.pending.value!;
      expect(first.name, '答案.pdf');

      next = attachment('課題.PNG', 'image/png', cacheId: laterId);
      await attachmentAvailable();
      final latest = service.pending.value!;
      expect(latest.name, '課題.PNG');
      service.clear(first);
      expect(service.pending.value, same(latest));
      service.clear(latest);
      expect(service.pending.value, isNull);
      expect(purged, [id, laterId]);
    },
  );

  test(
    'a failed share reports the error and keeps the prior file available',
    () async {
      Object? next = attachment('答案.pdf', 'application/pdf');
      messenger.setMockMethodCallHandler(channel, (_) async => next);
      final service = IncomingAttachmentService(channel: channel);
      await service.initialize();
      final first = service.pending.value;

      next = {'error': 'too_large'};
      await attachmentAvailable();
      expect(service.pending.value, same(first));
      expect(service.error.value, contains('64MB'));

      next = attachment('答案2.pdf', 'application/pdf');
      await attachmentAvailable();
      expect(service.pending.value?.name, '答案2.pdf');
      expect(service.error.value, isNull);
    },
  );

  test('matches MIME, wildcard and extension against the assignment input', () {
    final file = IncomingAttachment.fromHost(
      attachment('課題.PNG', 'image/png'),
    )!;
    expect(file.supportsAccept(const []), isTrue);
    expect(file.supportsAccept(const ['*/*']), isTrue);
    expect(file.supportsAccept(const [' .PDF, .png ']), isTrue);
    expect(file.supportsAccept(const ['image/*']), isTrue);
    expect(file.supportsAccept(const ['IMAGE/PNG']), isTrue);
    expect(file.supportsAccept(const ['application/pdf', '.jpeg']), isFalse);
  });

  test('only accepts native cache copies with consistent file metadata', () {
    final file = attachment('答案.pdf', 'application/pdf');
    expect(IncomingAttachment.fromHost(file), isNotNull);
    for (final path in [
      '/storage/emulated/0/答案.pdf',
      'content://provider/答案.pdf',
      '$cache/../$id/答案.pdf',
      '$cache/not-a-cache-id/答案.pdf',
      '$cache/$id/違う答案.pdf',
    ]) {
      expect(IncomingAttachment.fromHost({...file, 'path': path}), isNull);
    }
    expect(
      IncomingAttachment.fromHost({
        ...file,
        'mimeType': 'text/plain; charset=utf-8',
      }),
      isNull,
    );
  });
}
