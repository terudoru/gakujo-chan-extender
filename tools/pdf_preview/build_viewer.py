#!/usr/bin/env python3
"""Build the isolated viewer with the audited PDFium binary and worker patch."""

import argparse
import hashlib
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
WEB = HERE / 'build' / 'web'
WORKER = WEB / 'assets' / 'packages' / 'pdfrx' / 'assets' / 'pdfium_worker.js'
CLIENT = WEB / 'assets' / 'packages' / 'pdfrx' / 'assets' / 'pdfium_client.js'
WASM = WEB / 'assets' / 'packages' / 'pdfrx' / 'assets' / 'pdfium.wasm'
OUTPUT = ROOT / 'assets' / 'pdf_preview' / 'web'
FILES = (
    'index.html', 'orientation.js', 'flutter_bootstrap.js', 'main.dart.js',
    'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
    'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm',
    'canvaskit/webparagraph/canvaskit.js', 'canvaskit/webparagraph/canvaskit.wasm',
    'assets/AssetManifest.bin', 'assets/FontManifest.json', 'assets/NOTICES',
    'assets/fonts/fallback/Roboto-Regular.ttf', 'assets/fonts/MaterialIcons-Regular.otf',
    'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
    'assets/packages/material_ui/shaders/ink_sparkle.frag',
    'assets/packages/pdfrx/assets/pdfium_client.js',
    'assets/packages/pdfrx/assets/pdfium_worker.js',
    'assets/packages/pdfrx/assets/pdfium.wasm',
    'assets/shaders/ink_sparkle.frag', 'assets/shaders/stretch_effect.frag',
)
WORKER_SHA256 = '744f9bbbaefe3af9c3289e633ca8ee265b3d0d84df0b1fcb96f1d2ed686bb37b'
PDFIUM_SHA256 = 'e192a1af355b2c8af4f25783aac0fadc14c0471e310100ed96ff73f903b06c10'


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--pdfium-wasm', required=True, type=Path)
    args = parser.parse_args()
    pdfium = args.pdfium_wasm.read_bytes()
    if digest(pdfium) != PDFIUM_SHA256:
        raise SystemExit('Unexpected PDFium binary; verify the pinned release and hash.')

    flutter = shutil.which('flutter.bat') or shutil.which('flutter')
    if flutter is None:
        raise SystemExit('Flutter SDK is unavailable.')
    subprocess.run([flutter, 'build', 'web', '--release', '--no-pub',
                    '--no-web-resources-cdn', '--no-wasm-dry-run'], cwd=HERE, check=True)

    # Normalize line endings for a portable patch, then check the exact upstream
    # version. Never silently apply our security modifications to another worker.
    original = WORKER.read_text(encoding='utf-8').replace('\r\n', '\n').encode('utf-8')
    if digest(original) != WORKER_SHA256:
        raise SystemExit('Unexpected pdfrx worker; review the patch before updating.')
    WORKER.write_bytes(original)
    client = CLIENT.read_text(encoding='utf-8').replace('\r\n', '\n').encode('utf-8')
    if digest(client) != '6ef9f45c46d3c1cfd14ac3de4022f38cd34a040fa6b15ff797e4002f2355ccf8':
        raise SystemExit('Unexpected pdfrx client; review the patch before updating.')
    CLIENT.write_bytes(client)
    subprocess.run(['git', 'apply', '--directory=tools/pdf_preview/build/web',
                    'tools/pdf_preview/pdfium_worker.patch'], cwd=ROOT, check=True)
    subprocess.run(['git', 'apply', '--directory=tools/pdf_preview/build/web',
                    'tools/pdf_preview/pdfium_client.patch'], cwd=ROOT, check=True)
    WASM.write_bytes(pdfium)
    for name in FILES:
        destination = OUTPUT / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(WEB / name, destination)
    print(f'Built isolated viewer: {OUTPUT}')


if __name__ == '__main__':
    main()
