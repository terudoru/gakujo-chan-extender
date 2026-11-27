# Hosted 履修手帖 bridge v2

The toolbar menu's **履修手帖** opens `https://gakujo.terudoru.com/syllabus/`
in its own WebView. **履修プランナー**, MBGREG1, MBGPLAN1, and their existing
capture/delivery scripts remain separate and byte-compatible. No academic
registration action is added.

## Native session and storage

Planner and star sync use the same `StarSyncGoogleAuth` object. Planner sign-in
calls its native adapter without optional scopes: it never requests `drive.file`.
The existing adapters request `drive.appdata` plus `openid` and `email` for native
account identity. Existing download-saving consent is neither requested nor
exposed to the planner. Tokens stay inside native auth/HTTP code and secure
storage; no bridge result, URL, log, or backup contains them.

Sign-out signs out the whole app and suspends pending Drive downloads through
the existing sign-out action. An existing star-sync account binding prevents
silently switching to another Google account: disable star sync before choosing
a different account. The planner does not rewrite the existing star-sync binding
or data formats. Browser and native OAuth clients **must belong to the same Google
Cloud project** to see the same appDataFolder.

Each visit owns one controller until the route closes. The normal persistent
website profile is used on Android, iOS, macOS, Windows and Linux; cookies,
localStorage and IndexedDB use the platform's existing on-disk profile. Closing
the route releases the controller; reopening reloads the hosted page with that
profile. No planner data is copied into MBG backup files. Cross-launch persistence
outside Windows still needs device verification.

## Protocol boundary

`lib/src/planner_bridge/planner_broker.dart` implements all eight contract ops.
Replies use `mbg:planner-bridge`, `v:2`, echo `id`, and expose only the specified
result shapes or sanitized contract error codes. A 30-second deadline prevents
late mutation after token/metadata waits. Requests are pinned to the native auth,
student and document generations; navigation and disposal invalidate requests.
Session changes are detected at each request and every 250 ms while open and
emit the contract's id-less session event. Signed-in sessions include the Drive
owner's `permissionId`, fetched from `about.user` and cached only for that native
auth generation; an old lookup cannot identify a replacement account.
Sign-in and sign-out replies are delivered before their queued session events.

Drive listing is restricted to `appDataFolder` and a `mbg-planner-` prefix.
`mbg-gakujo-handoff.v1.json` and `mbg-gakujo-timetable.v1.json` are available
through `nameExact` and file reads. The host advertises `gakujo-timetable` in
`hello` when it supports the timetable file. Prefix queries exclude both files,
and requests with both selectors are rejected. Exact list results include
`mimeType`, `spaces`, `modifiedTime`, and the Drive `incompleteSearch` flag.
The bridge rejects create and delete operations on either file, including
previously unlisted IDs. Read
and delete fetch metadata first, verify `spaces` includes `appDataFolder`, then
check names. Create/delete use the three fixed names or the exact snapshot
pattern, including UUID v4 variant bits; UTF-8 bodies are limited to 4 MiB. Native
HTTP requests refuse redirects. Create/delete recheck the original generation
immediately before network transmission, including after token acquisition.

Student scopes use exactly SHA-256 of UTF-8 `mbg.planner.student.v1\n` followed by
the login ID, base64url without padding. The test vector is
`TEST-STUDENT-001` → `gQOOFkE1jpRlRuhqfRatobgKFo4t4Iyo9D50UxxITR8`.
The active confirmed portal identity must match the captured login or saved ID;
only its scope is returned. Unsaved manually submitted IDs are hashed immediately
and held only as scopes in memory. If a prior process's authenticated identity
cannot be tied to a known ID, the host returns null rather than guessing.

The planner sync engine owns student-binding file creation/checking, mismatch
UI and purge (including deleting the binding), per the shared contract. The host
allows that file but does not create a second competing binding implementation.
Star-sync reset regression tests seed planner key, binding, deletion marker and
snapshot files and verify that their bytes survive reset.

## Platform limitations and proposed contract clarifications

The shared WebView API supplies a message string, without authenticated frame
metadata. The public `MbgPlannerBridge` is installed only in the trusted top
document, through a fresh random capability bound to a private channel. A caller
must possess that document capability; raw channel calls from other frames are
ignored. A new document cannot receive an old reply: the delivery closure also
checks its document capability. Cross-origin frames cannot obtain the top-frame
capability. Same-origin scripts can invoke a top-frame function, so absolute
caller-frame attribution requires new native plugin APIs on each platform.
Proposed amendment: define the top document and its same-origin script authority
as the trust boundary, or require native frame metadata before claiming strict
caller-frame isolation. The latter is not provided by this implementation.

Windows additionally blocks non-host and non-`/syllabus/` navigations in native
`NavigationStarting`, before sending a request; the optional path allowlist leaves
existing WebViews unchanged. Dart navigation delegates enforce the same origin
and path on other platforms and send HTTP(S) external links outside. Child-frame
navigations are refused. The bridge is injected after page load and signals
`mbg:planner-host`, so the hosted planner must repeat detection on that event.

Proposed scope wording: “request drive.appdata as the only Drive scope; native
identity scopes openid/email are permitted.” Requiring literally only appdata
would require changes to the app's shared account-identification stack.

## Fixtures and verification

`test/fixtures/planner_bridge_v2_vectors.json` is the byte-identical copy of the
履修手帖 repository's `planner/test/fixtures/bridge-v2-vectors.json` contract.
It includes every op, session events, name cases, binding and hash vectors.
The broker tests consume all cases; illustrative error messages are checked for
shape while native replies keep sanitized codes as their messages. The 履修手帖
repository remains authoritative. No production TypeScript or generated v1
scripts were changed; the native URL test's TypeScript adapter now handles path
policies.

Run `npm --prefix web_scripts run check`, `flutter analyze lib test`, and
`flutter test`. Focused tests are `planner_broker_test.dart`,
`planner_page_test.dart`, and `star_sync_drive_key_test.dart`.
For credential-free Windows QA, set `MBG_PLANNER_PROFILE` to a fresh scratch
directory and run `flutter run -d windows -t
test/support/planner_bridge_windows_smoke.dart`; it uses the production hosted
screen with native sign-in disabled and a separate profile.
