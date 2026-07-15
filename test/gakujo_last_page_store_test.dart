import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/gakujo_last_page_store.dart';
import 'package:test/test.dart';

void main() {
  test('saveIfAllowed stores an allowed Gakujo URL', () async {
    const url = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do';
    final storage = _MemorySecureStorage();
    final store = GakujoLastPageStore(secureStorage: storage);

    await store.saveIfAllowed(url, debugAllowed: false);

    expect(storage.values[GakujoLastPageStore.lastUrlKey], url);
  });

  test('saveIfAllowed ignores disallowed and null URLs', () async {
    const savedUrl =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do';
    final storage = _MemorySecureStorage({
      GakujoLastPageStore.lastUrlKey: savedUrl,
    });
    final store = GakujoLastPageStore(secureStorage: storage);

    await store.saveIfAllowed('https://example.com/', debugAllowed: false);
    await store.saveIfAllowed(null, debugAllowed: false);

    expect(storage.values[GakujoLastPageStore.lastUrlKey], savedUrl);
  });

  test('load returns a stored allowed Gakujo URL', () async {
    const url = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do';
    final storage = _MemorySecureStorage({
      GakujoLastPageStore.lastUrlKey: url,
    });
    final store = GakujoLastPageStore(secureStorage: storage);

    expect(await store.load(debugAllowed: false), url);
    expect(storage.values[GakujoLastPageStore.lastUrlKey], url);
  });

  test('load clears and rejects a stored disallowed URL', () async {
    final storage = _MemorySecureStorage({
      GakujoLastPageStore.lastUrlKey: 'https://example.com/',
    });
    final store = GakujoLastPageStore(secureStorage: storage);

    expect(await store.load(debugAllowed: false), isNull);
    expect(storage.values.containsKey(GakujoLastPageStore.lastUrlKey), isFalse);
  });

  test('load clears and rejects a transient timeout page', () async {
    const timeoutUrl =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/theme/default/TimeoutAlert.html';
    final storage = _MemorySecureStorage({
      GakujoLastPageStore.lastUrlKey: timeoutUrl,
    });
    final store = GakujoLastPageStore(secureStorage: storage);

    expect(await store.load(debugAllowed: false), isNull);
    expect(storage.values.containsKey(GakujoLastPageStore.lastUrlKey), isFalse);
  });

  test('clear removes the stored URL', () async {
    final storage = _MemorySecureStorage({
      GakujoLastPageStore.lastUrlKey:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do',
    });
    final store = GakujoLastPageStore(secureStorage: storage);

    await store.clear();

    expect(storage.values.containsKey(GakujoLastPageStore.lastUrlKey), isFalse);
  });

  test('debug fixture URLs are restored only when debug is allowed', () async {
    const fixtureUrl = 'file:///android_asset/qa/two_factor.html';
    final storage = _MemorySecureStorage();
    final store = GakujoLastPageStore(secureStorage: storage);

    await store.saveIfAllowed(fixtureUrl, debugAllowed: true);

    expect(await store.load(debugAllowed: true), fixtureUrl);
    expect(await store.load(debugAllowed: false), isNull);
    expect(storage.values.containsKey(GakujoLastPageStore.lastUrlKey), isFalse);
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage([Map<String, String>? initial])
      : values = Map<String, String>.from(initial ?? const {});

  final Map<String, String> values;

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
    return values[key];
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
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}
