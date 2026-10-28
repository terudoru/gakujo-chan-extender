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

    def test_macos_creates_release_without_other_platform_assets(self):
        with patch.object(staged.subprocess, 'run') as run:
            staged.release('macos', self.directory, self.tag, self.repo)
        args = run.call_args.args[0]
        self.assertEqual(args[:3], ['gh', 'release', 'create'])
        self.assertIn('--verify-tag', args)
        self.assertIn('--prerelease', args)
        self.assertEqual(len([x for x in args if x.endswith('.dmg')]), 1)
        self.assertIn(staged.WINDOWS_ANDROID_PENDING, args[args.index('--notes') + 1])
        self.assertIn(staged.IOS_PENDING, args[args.index('--notes') + 1])

    def test_add_assets_preserves_other_notes_and_skips_identical_file(self):
        apk = self.directory / f'MoreBetterGakujo-{self.tag}.apk'
        existing = {'body': staged.initial_notes(self.tag) + '\nOther notes\n', 'assets': [
            {'name': apk.name, 'digest': 'sha256:' + hashlib.sha256(apk.read_bytes()).hexdigest()}]}
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            if args[2] == 'view':
                return type('Response', (), {'stdout': json.dumps(existing)})()
            if args[2] == 'edit':
                notes = Path(args[args.index('--notes-file') + 1]).read_text(encoding='utf-8')
                self.assertIn('Other notes', notes)
                self.assertIn(staged.IOS_PENDING, notes)
                self.assertNotIn(staged.WINDOWS_ANDROID_PENDING, notes)
                self.assertNotIn(staged.RELEASE_PENDING, notes)
                self.assertIn('--prerelease=false', args)
                self.assertIn('--latest', args)
            return None
        with patch.object(staged.subprocess, 'run', side_effect=run):
            staged.release('windows_android', self.directory, self.tag, self.repo)
        self.assertEqual([x[2] for x in calls], ['view', 'upload', 'upload', 'edit'])
        self.assertTrue(all(not any(str(a).endswith('.apk') for a in x)
                            for x in calls if x[2] == 'upload'))

    def test_collision_or_invalid_markers_never_uploads(self):
        existing = {'body': staged.initial_notes(self.tag), 'assets': [
            {'name': f'MoreBetterGakujo-{self.tag}.exe', 'digest': 'sha256:wrong'}]}
        with patch.object(staged.subprocess, 'run') as run:
            run.return_value.stdout = json.dumps(existing)
            with self.assertRaisesRegex(ValueError, 'differs'):
                staged.release('windows_android', self.directory, self.tag, self.repo)
            self.assertEqual(run.call_count, 1)
        with self.assertRaisesRegex(ValueError, 'markers'):
            staged.replace_section('unrelated notes', 'windows_android')

    def test_ios_notes_require_commit_and_preserve_windows_section(self):
        body = staged.replace_section(staged.initial_notes(self.tag), 'windows_android')
        with self.assertRaisesRegex(ValueError, 'commit'):
            staged.replace_section(body, 'ios', 'main')
        updated = staged.replace_section(body, 'ios', 'a' * 40)
        self.assertIn('a' * 40, updated)
        self.assertIn('**Windows**', updated)
        self.assertNotIn(staged.IOS_PENDING, updated)


if __name__ == '__main__':
    unittest.main()
