# flutter_secure_storage_windows (vendored)

Upstream: https://github.com/mogol/flutter_secure_storage, version 4.2.2,
BSD 3-Clause (see `LICENSE`). `lib/`, `windows/`, package metadata and upstream
documentation are kept. The upstream Dart tests are omitted because their cleanup
uses the application support directory; local tests use only a temporary directory.

Local changes, all marked "More Better Gakujo patch":

- File reads only return an empty store for Windows file/path-not-found errors.
  Other I/O failures throw `PlatformException(code: 'read_failed')`, preventing a
  read-modify-write from overwriting keys it could not read.
- Undecryptable or malformed files are renamed to `<path>.corrupt-<timestamp>`
  before returning an empty store. Preservation failures propagate; corrupt file
  contents and parse exceptions are never logged.
- Encrypted writes remove a stale `<path>.tmp`, write and flush that temporary
  file, then rename it over the destination. Failed writes leave the previous
  destination intact and propagate instead of retrying indefinitely.
- The existing Future-chain lock is shared across plugin instances in the same
  isolate, covering reads, writes, deletes and legacy migration. No cache behavior
  changes are introduced. This does not coordinate other isolates or processes.
- A test-only path/file factory constructor enables isolated DPAPI regression
  tests in `test/file_reliability_test.dart` without opening application storage.

Run the local tests on Windows from the application root after `flutter pub get`:

```sh
flutter test third_party/flutter_secure_storage_windows/test/file_reliability_test.dart
```

When upgrading, re-apply these changes or drop the vendored copy if upstream
covers them. Original upstream README follows.

---

# flutter_secure_storage_windows

This is the platform-specific implementation of `flutter_secure_storage` for Windows.

## Features

In the Windows implementation of the flutter_secure_storage plugin, sensitive data is securely stored using a combination of local file storage and the Windows Credential Manager. The storage mechanism ensures both confidentiality and integrity through encryption and controlled access.

When a key-value pair is stored, the value is encrypted using the AES-GCM (Galois/Counter Mode) encryption algorithm. The plugin generates a unique encryption key, securely managed and stored in the Windows Credential Manager. This key is used to encrypt the value, and the resulting encrypted data is saved to a file in the application's support directory. Each file is named after the key (with a .secure extension) and contains the encrypted value along with a nonce (used for AES-GCM encryption) and an authentication tag to verify the integrity of the data during decryption.

The directory for storing these files is dynamically determined based on the application's context, ensuring isolation and protection against unauthorized access. Additionally, for backward compatibility, the plugin can store and retrieve data directly from the Windows Credential Manager if needed. This hybrid approach leverages the security of encrypted local storage and the reliability of the Credential Manager, ensuring robust data protection for Flutter applications running on Windows.

## Installation

Ensure the required C++ ATL libraries are installed alongside Visual Studio Build Tools.

## Usage

Refer to the main [flutter_secure_storage README](../README.md) for common usage instructions.

## License

This project is licensed under the BSD 3 License. See the [LICENSE](../LICENSE) file for details.
