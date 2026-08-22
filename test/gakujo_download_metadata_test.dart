import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:test/test.dart';

void main() {
  test('saved download remains successful when history storage fails',
      () async {
    final store = GakujoDownloadHistoryStore(
      secureStorage: _FailingWriteSecureStorage(),
    );
    Object? reportedError;

    final recorded = await recordGakujoDownloadMetadataBestEffort(
      historyStore: store,
      historyEntry: GakujoDownloadHistoryEntry(
        fileName: '保存済み資料.pdf',
        courseName: '情報リテラシー',
        savedAt: DateTime.now(),
        location: r'C:\Downloads\保存済み資料.pdf',
      ),
      onError: (error, stackTrace) {
        reportedError = error;
      },
    );

    expect(recorded, isFalse);
    expect(reportedError, isA<StateError>());
  });
}

class _FailingWriteSecureStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw StateError('secure storage unavailable');
  }
}
