# More Better Gakujo Flutter

This is the portable Flutter version of the Android WebView app. The shared
Dart layer owns the Gakujo URL allowlist, Base32 normalization, TOTP generation,
secure secret access, and `ninshoCode` autofill script generation so the same
behavior can be shipped on Android and iOS.

## License and upstream notices

This app is prepared as a standalone Flutter repository derived from the
More-Better-Gakujo / Gakujo Chan Extender lineage. The original browser
extension lineage is licensed under the MIT License. Include this repository's
`LICENSE.md` and `NOTICE.md` when redistributing copies or substantial portions
of the software.

## Setup

Install Flutter, then fetch dependencies:

```sh
cd morebettergakujo-flutter
flutter pub get
```

The checked-in Dart files are the source of truth. Android and iOS runners are
included so Android can be built now and iOS can be compiled once local Xcode
and CocoaPods setup is complete.

## Checks

```sh
flutter test
flutter run -d android
flutter build apk
./android/gradlew -p android bundleRelease
```

The debug APK is written to
`build/app/outputs/flutter-apk/app-debug.apk`. The release AAB is written to
`build/app/outputs/bundle/release/app-release.aab`.

For local builds without a private keystore, the release build falls back to
debug signing. For a Play-ready AAB, create `android/key.properties` locally:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
```

`android/key.properties` is ignored by git.

Keep `android/upload-keystore.jks` and `android/key.properties` backed up. APK
updates must be signed with the same key, otherwise Android users will need to
uninstall the old app before installing the new one.

Do not commit `android/upload-keystore.jks`, `android/key.properties`, or
`android/local.properties`; they are intentionally ignored.

For local Android 2FA fixture QA, start an emulator and run:

```sh
flutter build apk --debug
./scripts/flutter_android_local_2fa_qa.sh
```

The QA script installs the debug APK, opens the debug-only
`file:///android_asset/qa/two_factor.html` fixture, injects a synthetic Base32
secret through Android intent extras, and verifies that the fixture is submitted
after autofill without writing the six-digit token to logcat. Screenshots, UI
XML, and logcat are written under `build/qa/`.

For iOS after opening the generated runner on macOS:

```sh
flutter run -d ios
flutter build ipa
```

## Behavior Ported From Kotlin

- Opens `https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do`.
- Blocks navigation outside `https://gakujo.iess.niigata-u.ac.jp/*`.
- Debug builds additionally allow only `file:///android_asset/qa/*` for local
  fixture QA.
- Saves only the long Base32 2FA secret, never the six-digit one-time code.
- Stores the secret through `flutter_secure_storage`, which maps to Android
  Keystore-backed storage and iOS Keychain-backed storage.
- Generates a six-digit TOTP token in Dart.
- Injects JavaScript after allowed page loads and retries briefly until
  `input[name="ninshoCode"]` exists, then submits the surrounding form or submit
  button so the login can continue automatically.
- Lets the user choose a download root folder on Android, then saves detected
  Gakujo downloads under `course/file`, using the clicked link or button text
  instead of the fallback `campussquare.do` name whenever possible.

## iOS Port Notes

The app code avoids Android-only APIs. When the generated iOS runner is added,
review the normal Flutter plugin setup for:

- `webview_flutter` iOS WebKit support.
- Keychain access from `flutter_secure_storage`.
- App transport/network settings if the university portal changes its TLS
  behavior.

No Gakujo-specific logic should need to move into Swift.
