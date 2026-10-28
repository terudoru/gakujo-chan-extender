#!/usr/bin/env python3
"""Create a macOS-first release and add verified platform assets later."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


WINDOWS_ANDROID_PENDING = 'Windows / Android: 検証・ビルド後にこのリリースへ追加します。'
IOS_PENDING = 'iOS/iPadOS: デバッグ完了後に追加予定です。既存版は過去のリリースをご覧ください。'
RELEASE_PENDING = 'macOS 先行公開です。Windows / Android の検証後に安定版へ切り替えます。'


def initial_notes(tag: str) -> str:
    return f'''More Better Gakujo {tag}

{RELEASE_PENDING}

## ダウンロード
- **macOS**: `*.dmg`（Developer ID未署名。初回は「プライバシーとセキュリティ」から「このまま開く」を選択）
  ビルド・起動検証済み。全機能の実機検証は継続中です。

<!-- MBG_WINDOWS_ANDROID_START -->
- **{WINDOWS_ANDROID_PENDING}**
<!-- MBG_WINDOWS_ANDROID_END -->

<!-- MBG_IOS_START -->
- **{IOS_PENDING}**
<!-- MBG_IOS_END -->
'''


def replace_section(body: str, mode: str, apple_commit: str = '') -> str:
    if mode == 'windows_android':
        marker = 'WINDOWS_ANDROID'
        content = ('- **Windows**: `*.exe`（インストーラー） / `*.zip`（ポータブル版）\n'
                   '- **Android**: `*.apk`。`v0.68.0`以前と署名が異なるため、'
                   '旧版からは上書き更新できません。アンインストールするとアプリ内データが削除されます。')
        body = body.replace(RELEASE_PENDING, 'Windows / Android / macOS を公開しています。')
    elif mode == 'ios':
        if not re.fullmatch(r'[0-9a-f]{40}', apple_commit):
            raise ValueError('A full validated iOS commit SHA is required')
        marker = 'IOS'
        content = ('- **iOS/iPadOS**: `*.ipa`（未署名、サイドロード用）。'
                   f'ビルド元コミット: `{apple_commit}`。')
    else:
        raise ValueError('Unknown release scope')
    start, end = f'<!-- MBG_{marker}_START -->', f'<!-- MBG_{marker}_END -->'
    if body.count(start) != 1 or body.count(end) != 1 or body.index(start) >= body.index(end):
        raise ValueError('Release markers are missing or ambiguous; refusing to alter notes')
    return body[:body.index(start)] + start + '\n' + content + '\n' + body[body.index(end):]


def release(mode: str, directory: Path, tag: str, repo: str, apple_commit: str = '') -> None:
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?', tag):
        raise ValueError('Invalid release tag')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Invalid repository')
    extensions = {'macos': ('dmg',), 'windows_android': ('apk', 'exe', 'zip'), 'ios': ('ipa',)}
    if mode not in extensions:
        raise ValueError('Unknown release scope')
    files = [directory / f'MoreBetterGakujo-{tag}.{ext}' for ext in extensions[mode]]
    for file in files:
        if not file.is_file() or file.stat().st_size == 0:
            raise ValueError(f'Missing release artifact: {file}')

    if mode == 'macos':
        # `gh release create` fails if the release already exists; it does not
        # silently replace previously published assets or notes on a retry.
        args = ['gh', 'release', 'create', tag, str(files[0]), '--repo', repo,
                '--verify-tag', '--title', tag, '--notes', initial_notes(tag), '--prerelease']
        subprocess.run(args, check=True)
        return

    result = subprocess.run(['gh', 'release', 'view', tag, '--repo', repo,
                             '--json', 'body,assets'], check=True, capture_output=True, text=True)
    existing = json.loads(result.stdout)
    notes = replace_section(existing.get('body') or '', mode, apple_commit)
    assets = existing.get('assets', [])
    to_upload = []
    for file in files:
        matches = [asset for asset in assets if asset.get('name') == file.name]
        if len(matches) > 1:
            raise ValueError(f'Duplicate release asset: {file.name}')
        if not matches:
            to_upload.append(file)
        else:
            with file.open('rb') as stream:
                expected = 'sha256:' + hashlib.file_digest(stream, 'sha256').hexdigest()
            if matches[0].get('digest') != expected:
                raise ValueError(f'Existing release asset differs: {file.name}')
    for file in to_upload:
        subprocess.run(['gh', 'release', 'upload', tag, str(file), '--repo', repo], check=True)
    with tempfile.TemporaryDirectory(prefix='mbg-release-notes-') as temp:
        notes_path = Path(temp) / 'notes.md'
        notes_path.write_text(notes, encoding='utf-8')
        args = ['gh', 'release', 'edit', tag, '--repo', repo, '--notes-file', str(notes_path)]
        if mode == 'windows_android' and '-' not in tag:
            args.extend(['--prerelease=false', '--latest'])
        subprocess.run(args, check=True)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: staged_release.py {macos|windows_android|ios} ARTIFACT_DIR')
    release(sys.argv[1], Path(sys.argv[2]), os.environ['RELEASE_TAG'], os.environ['GH_REPO'],
            os.environ.get('APPLE_COMMIT', ''))
