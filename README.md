# More Better Gakujo Android

This is a standalone Flutter Android app for using Niigata University's Gakujo
portal in a WebView with More Better Gakujo-inspired conveniences.

Current Android APK builds include:

- 2FA code autofill from a locally stored Base32 secret.
- A settings screen for the 2FA secret, download behavior, and mobile/desktop
  page mode.
- Download save modes:
  - auto-sort by course and save under a configured folder
  - save directly under a configured folder
  - choose the save location each time
- Gakujo download capture for links and form/button-based downloads.
- Course-folder inference from Gakujo pages, including course tables, report /
  quiz / survey submission pages, notification pages, and fallback file-name
  patterns.

The release APK is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## License and upstream notices

This app is published as a standalone repository, not as a GitHub fork of the
browser extension repository.

It is inspired by and derived from ideas in the More-Better-Gakujo /
Gakujo-chan-extender lineage. The primary upstream project is:

- https://github.com/koji-genba/gakujo-chan-extender

Related fork:

- https://github.com/yangniao23/gakujo-chan-extender

Include this repository's `LICENSE.md` and `NOTICE.md` when redistributing
copies or substantial portions of the software.

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
flutter build apk --release
./android/gradlew -p android bundleRelease
```

The release APK is written to
`build/app/outputs/flutter-apk/app-release.apk`. The debug APK is written to
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
- Lets the user choose a download root folder on Android.
- Saves detected Gakujo downloads according to the selected save mode.
- Detects course names from the current Gakujo page, including table columns
  where `科目名` appears above or beside the value.
- Falls back to useful file-name patterns when the page does not expose a
  course name clearly.

## iOS Port Notes

The app code avoids Android-only APIs. When the generated iOS runner is added,
review the normal Flutter plugin setup for:

- `webview_flutter` iOS WebKit support.
- Keychain access from `flutter_secure_storage`.
- App transport/network settings if the university portal changes its TLS
  behavior.

No Gakujo-specific logic should need to move into Swift.
