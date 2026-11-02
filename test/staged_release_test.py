import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('staged_release', ROOT / 'scripts/staged_release.py')
staged = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staged)


class StagedReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mbg-release-test-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.tag = 'v0.70.1'
        self.repo = 'owner/project'
        for ext in ('dmg', 'apk', 'exe', 'zip', 'ipa'):
            (self.directory / f'MoreBetterGakujo-{self.tag}.{ext}').write_bytes(ext.encode())

        for suffix in ('-linux-x64.tar.gz', '-linux-amd64.deb'):
            (self.directory / f'MoreBetterGakujo-{self.tag}{suffix}').write_bytes(suffix.encode())

    def test_all_platforms_publish_only_after_draft_assets_match(self):
        assets = []
        for ext in ('dmg', 'apk', 'exe', 'zip'):
            file = self.directory / f'MoreBetterGakujo-{self.tag}.{ext}'
            assets.append({'name': file.name, 'digest': 'sha256:' + hashlib.sha256(file.read_bytes()).hexdigest()})
        for suffix in ('-linux-x64.tar.gz', '-linux-amd64.deb'):
            file = self.directory / f'MoreBetterGakujo-{self.tag}{suffix}'
            assets.append({'name': file.name, 'digest': 'sha256:' + hashlib.sha256(file.read_bytes()).hexdigest()})
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            if args[2] == 'view':
                return type('Response', (), {'stdout': json.dumps({'isDraft': True, 'assets': assets})})()
            return None
        with patch.object(staged.subprocess, 'run', side_effect=run):
            staged.release('all', self.directory, self.tag, self.repo)
        self.assertEqual([args[2] for args in calls], ['create', 'view', 'edit'])
        self.assertIn('--draft', calls[0])
        self.assertIn('--verify-tag', calls[0])
        self.assertEqual(len([x for x in calls[0] if x.endswith(('.dmg', '.apk', '.exe', '.zip', '.tar.gz', '.deb'))]), 6)
        self.assertIn('**Linux**', calls[0][calls[0].index('--notes') + 1])
        self.assertIn(staged.IOS_PENDING, calls[0][calls[0].index('--notes') + 1])
        self.assertIn('--draft=false', calls[-1])
        self.assertIn('--latest', calls[-1])

    def test_all_requires_both_linux_assets_before_creating_release(self):
        for suffix in ('-linux-x64.tar.gz', '-linux-amd64.deb'):
            file = self.directory / f'MoreBetterGakujo-{self.tag}{suffix}'
            data = file.read_bytes()
            file.unlink()
            with patch.object(staged.subprocess, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'Missing release artifact'):
                    staged.release('all', self.directory, self.tag, self.repo)
                run.assert_not_called()
            file.write_bytes(data)

    def test_prerelease_uses_full_tag_for_linux_assets(self):
        tag = self.tag + '-beta.1'
        for ext in ('dmg', 'apk', 'exe', 'zip'):
            (self.directory / f'MoreBetterGakujo-{tag}.{ext}').write_bytes(ext.encode())
        for suffix in ('-linux-x64.tar.gz', '-linux-amd64.deb'):
            (self.directory / f'MoreBetterGakujo-{tag}{suffix}').write_bytes(suffix.encode())
        with patch.object(staged.subprocess, 'run') as run:
            run.side_effect = RuntimeError('create reached')
            with self.assertRaisesRegex(RuntimeError, 'create reached'):
                staged.release('all', self.directory, tag, self.repo)
            for suffix in ('-linux-x64.tar.gz', '-linux-amd64.deb'):
                self.assertIn(str(self.directory / f'MoreBetterGakujo-{tag}{suffix}'), run.call_args.args[0])
            self.assertIn('--prerelease', run.call_args.args[0])

    def test_ios_addition_preserves_other_notes_and_skips_identical_file(self):
        ipa = self.directory / f'MoreBetterGakujo-{self.tag}.ipa'
        existing = {'body': staged.initial_notes(self.tag) + '\nOther notes\n', 'assets': [
            {'name': ipa.name, 'digest': 'sha256:' + hashlib.sha256(ipa.read_bytes()).hexdigest()}]}
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            if args[2] == 'view':
                return type('Response', (), {'stdout': json.dumps(existing)})()
            if args[2] == 'edit':
                notes = Path(args[args.index('--notes-file') + 1]).read_text(encoding='utf-8')
                self.assertIn('Other notes', notes)
                self.assertNotIn(staged.IOS_PENDING, notes)
                self.assertIn('**Windows**', notes)
            return None
        with patch.object(staged.subprocess, 'run', side_effect=run):
            staged.release('ios', self.directory, self.tag, self.repo, 'b' * 40)
        self.assertEqual([x[2] for x in calls], ['view', 'edit'])

    def test_collision_or_invalid_markers_never_uploads(self):
        existing = {'body': staged.initial_notes(self.tag), 'assets': [
            {'name': f'MoreBetterGakujo-{self.tag}.ipa', 'digest': 'sha256:wrong'}]}
        with patch.object(staged.subprocess, 'run') as run:
            run.return_value.stdout = json.dumps(existing)
            with self.assertRaisesRegex(ValueError, 'differs'):
                staged.release('ios', self.directory, self.tag, self.repo, 'b' * 40)
            self.assertEqual(run.call_count, 1)
        with self.assertRaisesRegex(ValueError, 'markers'):
            staged.replace_section('unrelated notes', 'ios', 'b' * 40)

    def test_ios_notes_require_commit_and_preserve_windows_section(self):
        body = staged.initial_notes(self.tag)
        with self.assertRaisesRegex(ValueError, 'commit'):
            staged.replace_section(body, 'ios', 'main')
        updated = staged.replace_section(body, 'ios', 'a' * 40)
        self.assertIn('a' * 40, updated)
        self.assertIn('**Windows**', updated)
        self.assertNotIn(staged.IOS_PENDING, updated)

    def test_draft_with_incorrect_assets_is_never_published(self):
        with patch.object(staged.subprocess, 'run') as run, patch.object(staged.time, 'sleep'):
            run.return_value.stdout = json.dumps({'isDraft': True, 'assets': []})
            with self.assertRaisesRegex(ValueError, 'do not match'):
                staged.release('all', self.directory, self.tag, self.repo)
            self.assertTrue(all(call.args[0][2] != 'edit' for call in run.call_args_list))


if __name__ == '__main__':
    unittest.main()
