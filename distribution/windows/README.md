# Windows installer

This directory contains the Inno Setup installer definition for the Flutter Windows build.

## Build

Run this on Windows from the repository root:

```powershell
flutter build windows --release
```

Then open `distribution\windows\morebettergakujo.iss` in Inno Setup and compile it, or use `ISCC.exe`:

```powershell
ISCC.exe distribution\windows\morebettergakujo.iss
```

You can also run the packaging helper:

```powershell
.\scripts\package_windows_inno.ps1
```

The installer is written to:

```text
dist\windows\MoreBetterGakujo-v0.67.0.exe
```

The installer places the app under `Program Files`, creates Start Menu entries, registers an uninstaller, and optionally creates a desktop shortcut. Updates use Inno Setup's normal in-place upgrade rather than executing the previous installation's uninstaller with administrator privileges. User-specific app data should stay outside the install directory, such as under `%AppData%`.

At the default installation path, the installer records the paths and SHA-256 hashes of files it installs. During a later update it removes files recorded by the previous installer only if the new version no longer supplies them and their contents are unchanged. Modified and unrecorded files are preserved. The first update from a version without a manifest can remove only the known legacy debug artifacts; other older files cannot be identified safely. Automatic cleanup is disabled for custom installation paths, where directory permissions may allow untrusted users to modify the tree during an elevated update.
