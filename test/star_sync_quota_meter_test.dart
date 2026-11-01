import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_quota_meter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('persists usage and notices and resets on the local day', () async {
    var now = DateTime(2026, 11, 1, 23, 59);
    StarSyncQuotaMeter make() => StarSyncQuotaMeter(
      storage: const FlutterSecureStorage(),
      now: () => now,
    );
    final first = make();
    await first.charge(14900);
    expect(await first.allowsAutomatic(100), isTrue);
    expect(await first.allowsAutomatic(101), isFalse);
    expect(await first.claimSaveNotice(), isTrue);
    final restored = make();
    expect(await restored.currentUsage(), 14900);
    expect(await restored.claimSaveNotice(), isFalse);
    now = DateTime(2026, 11, 2);
    expect(await restored.currentUsage(), 0);
    expect(await restored.claimSaveNotice(), isTrue);
    await restored.charge(50);
    expect(await make().currentUsage(), 50);
  });

  test('serializes charges and refuses crossing the hard limit', () async {
    final meter = StarSyncQuotaMeter(storage: const FlutterSecureStorage());
    await meter.charge(24900);
    await Future.wait([meter.charge(50), meter.charge(50)]);
    await expectLater(meter.charge(5), throwsA(isA<StarSyncQuotaExceeded>()));
    expect(await meter.currentUsage(), 25000);
  });
}
