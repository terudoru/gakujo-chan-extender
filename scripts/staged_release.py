#!/usr/bin/env python3
"""Publish three platforms together and add validated iOS assets later."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


IOS_PENDING = 'iOS/iPadOS: デバッグ完了後に追加予定です。既存版は過去のリリースをご覧ください。'


def initial_notes(tag: str) -> str:
    return f'''More Better Gakujo {tag}

## ダウンロード
- **macOS**: `*.dmg`（Developer ID未署名。初回は「プライバシーとセキュリティ」から「このまま開く」を選択）
  ビルド・起動検証済み。全機能の実機検証は継続中です。
- **Windows**: `*.exe`（インストーラー） / `*.zip`（ポータブル版）
- **Android**: `*.apk`。`v0.68.0`以前と署名が異なるため、旧版からは上書き更新できません。アンインストールするとアプリ内データが削除されます。

<!-- MBG_IOS_START -->
- **{IOS_PENDING}**
<!-- MBG_IOS_END -->
'''


def replace_section(body: str, mode: str, platform_commit: str = '') -> str:
    if not re.fullmatch(r'[0-9a-f]{40}', platform_commit):
        raise ValueError('A full validated platform commit SHA is required')
    if mode == 'ios':
        marker = 'IOS'
        content = ('- **iOS/iPadOS**: `*.ipa`（未署名、サイドロード用）。'
                   f'ビルド元コミット: `{platform_commit}`。')
    else:
        raise ValueError('Unknown release scope')
    start, end = f'<!-- MBG_{marker}_START -->', f'<!-- MBG_{marker}_END -->'
    if body.count(start) != 1 or body.count(end) != 1 or body.index(start) >= body.index(end):
        raise ValueError('Release markers are missing or ambiguous; refusing to alter notes')
    return body[:body.index(start)] + start + '\n' + content + '\n' + body[body.index(end):]


def release(mode: str, directory: Path, tag: str, repo: str, platform_commit: str = '') -> None:
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?', tag):
        raise ValueError('Invalid release tag')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Invalid repository')
    extensions = {'all': ('dmg', 'apk', 'exe', 'zip'), 'ios': ('ipa',)}
    if mode not in extensions:
        raise ValueError('Unknown release scope')
    files = [directory / f'MoreBetterGakujo-{tag}.{ext}' for ext in extensions[mode]]
    for file in files:
        if not file.is_file() or file.stat().st_size == 0:
            raise ValueError(f'Missing release artifact: {file}')

    if mode == 'all':
        # A draft remains invisible to users until every asset has been uploaded
        # and its server-side SHA-256 has been verified.
        args = ['gh', 'release', 'create', tag, *map(str, files), '--repo', repo,
                '--verify-tag', '--title', tag, '--notes', initial_notes(tag), '--draft']
        if '-' in tag:
            args.append('--prerelease')
        subprocess.run(args, check=True)
        expected = {}
        for file in files:
            with file.open('rb') as stream:
                expected[file.name] = 'sha256:' + hashlib.file_digest(stream, 'sha256').hexdigest()
        for attempt in range(6):
            response = subprocess.run(['gh', 'release', 'view', tag, '--repo', repo,
                                       '--json', 'isDraft,assets'], check=True,
                                      capture_output=True, text=True)
            draft = json.loads(response.stdout)
            if not draft.get('isDraft'):
                raise ValueError('Release was published before asset verification')
            assets = draft.get('assets', [])
            if len(assets) == len(expected) and all(
                sum(asset.get('name') == name and asset.get('digest') == digest
                    for asset in assets) == 1 for name, digest in expected.items()
            ):
                break
            if attempt == 5:
                raise ValueError('Draft assets do not match the verified build artifacts')
            time.sleep(5)
        args = ['gh', 'release', 'edit', tag, '--repo', repo, '--draft=false']
        if '-' not in tag:
            args.append('--latest')
        subprocess.run(args, check=True)
        return

    result = subprocess.run(['gh', 'release', 'view', tag, '--repo', repo,
                             '--json', 'body,assets'], check=True, capture_output=True, text=True)
    existing = json.loads(result.stdout)
    notes = replace_section(existing.get('body') or '', mode, platform_commit)
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
        subprocess.run(args, check=True)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: staged_release.py {all|ios} ARTIFACT_DIR')
    release(sys.argv[1], Path(sys.argv[2]), os.environ['RELEASE_TAG'], os.environ['GH_REPO'],
            os.environ.get('PLATFORM_COMMIT', ''))
