"""Exercise two real Inno upgrades against a disposable synthetic installation."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
ISCC = Path(os.environ.get('INNO_ISCC_PATH') or
            Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/Inno Setup 6/ISCC.exe')


@unittest.skipUnless(os.name == 'nt' and ISCC.is_file(), 'Inno Setup 6 is required')
class WindowsInstallerUpgradeTest(unittest.TestCase):
    def test_upgrade_removes_only_unmodified_previously_installed_files(self):
        scratch = ROOT / 'build' / 'installer-upgrade-tests'
        scratch.mkdir(parents=True, exist_ok=True)
        case = Path(tempfile.mkdtemp(prefix='case-', dir=scratch)).resolve()
        self.addCleanup(self._remove_case, case, scratch.resolve())
        source = case / 'source'
        installed = case / 'installed'
        output = case / 'output'
        source.mkdir()
        output.mkdir()

        def write(rel, data):
            path = source / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data, encoding='utf-8')

        def build_and_install(name, destination=installed):
            subprocess.run([
                str(ISCC), '/Qp', '/DInstallerTestMode=1',
                f'/DInstallerTestRoot={installed}', f'/DMyBuildDir={source}',
                f'/DMyOutputDir={output}', f'/DMyOutputBaseFilename={name}',
                str(ROOT / 'distribution/windows/morebettergakujo.iss'),
            ], check=True, capture_output=True, text=True, timeout=120)
            subprocess.run([
                str(output / (name + '.exe')), '/VERYSILENT', '/SUPPRESSMSGBOXES',
                '/NORESTART', f'/DIR={destination}',
            ], check=True, capture_output=True, timeout=120)

        write('morebettergakujo_flutter.exe', 'synthetic executable')
        write('old/obsolete.txt', 'old release')
        write('modified.txt', 'old managed file')
        write('linked/target.txt', 'outside content')
        write('keep.txt', 'version one')
        build_and_install('v1')
        manifest = installed / '.mbg-installed-files.txt'
        self.assertTrue(manifest.is_file(), 'first installation records its files')
        self.assertEqual(len(manifest.read_text(encoding='utf-8-sig').splitlines()), 5)

        (installed / 'modified.txt').write_text('user changed this', encoding='utf-8')
        (installed / 'personal.txt').write_text('user file', encoding='utf-8')
        outside = case / 'outside.txt'
        outside.write_text('outside', encoding='utf-8')
        outside_dir = case / 'outside-dir'
        outside_dir.mkdir()
        outside_target = outside_dir / 'target.txt'
        outside_target.write_text('outside content', encoding='utf-8')
        link = installed / 'linked'
        (link / 'target.txt').unlink()
        link.rmdir()
        env = os.environ.copy()
        env['MBG_TEST_JUNCTION'] = str(link)
        env['MBG_TEST_JUNCTION_TARGET'] = str(outside_dir)
        subprocess.run([
            'powershell', '-NoProfile', '-NonInteractive', '-Command',
            "$ErrorActionPreference='Stop'; $null=New-Item -ItemType Junction "
            '-Path $env:MBG_TEST_JUNCTION -Target $env:MBG_TEST_JUNCTION_TARGET',
        ], check=True, capture_output=True, env=env, timeout=20)
        self.addCleanup(lambda: link.rmdir() if link.exists() else None)
        digest = hashlib.sha256(outside.read_bytes()).hexdigest()
        with manifest.open('a', encoding='utf-8') as f:
            f.write(f'{digest}|..\\outside.txt\n')
        (source / 'old/obsolete.txt').unlink()
        (source / 'modified.txt').unlink()
        (source / 'linked/target.txt').unlink()
        write('keep.txt', 'version two')
        write('new.txt', 'new release')
        build_and_install('v2')

        self.assertFalse((installed / 'old/obsolete.txt').exists())
        self.assertFalse((installed / 'old').exists(), 'empty obsolete directories are removed')
        self.assertEqual((installed / 'modified.txt').read_text(), 'user changed this')
        self.assertEqual((installed / 'personal.txt').read_text(), 'user file')
        self.assertEqual(outside.read_text(), 'outside')
        self.assertEqual(outside_target.read_text(), 'outside content')
        self.assertEqual((installed / 'keep.txt').read_text(), 'version two')
        self.assertEqual((installed / 'new.txt').read_text(), 'new release')
        self.assertEqual(len(manifest.read_text(encoding='utf-8-sig').splitlines()), 3)

        custom = case / 'custom'
        custom.mkdir()
        custom_old = custom / 'old.txt'
        custom_old.write_text('custom path file', encoding='utf-8')
        custom_digest = hashlib.sha256(custom_old.read_bytes()).hexdigest()
        (custom / '.mbg-installed-files.txt').write_text(
            f'{custom_digest}|old.txt\n', encoding='utf-8')
        build_and_install('custom', custom)
        self.assertEqual(custom_old.read_text(), 'custom path file',
                         'cleanup must not trust a custom writable install root')

        subprocess.run([str(installed / 'unins000.exe'), '/VERYSILENT', '/NORESTART'],
                       check=True, capture_output=True, timeout=120)
        self.assertFalse(manifest.exists(), 'uninstall removes the generated manifest')
        self.assertEqual((installed / 'personal.txt').read_text(), 'user file')

    def test_declining_cleanup_preserves_files_for_a_later_upgrade(self):
        scratch = ROOT / 'build' / 'installer-upgrade-tests'
        scratch.mkdir(parents=True, exist_ok=True)
        case = Path(tempfile.mkdtemp(prefix='case-', dir=scratch)).resolve()
        self.addCleanup(self._remove_case, case, scratch.resolve())
        source, installed, output = (case / name for name in ('source', 'installed', 'output'))
        source.mkdir()
        output.mkdir()

        (source / 'morebettergakujo_flutter.exe').write_text('synthetic executable')
        (source / 'obsolete.txt').write_text('old release')
        original = ROOT / 'distribution/windows/morebettergakujo.iss'
        script = original.read_text(encoding='utf-8')
        default_choice = '  RemoveOldFiles := True;'
        self.assertEqual(script.count(default_choice), 1)
        # In silent test mode there is no prompt. Override only its default
        # choice in this disposable compiler input to exercise the No branch.
        script = script.replace(default_choice, '  RemoveOldFiles := False;', 1)
        script = script.replace(
            r'SetupIconFile=..\..\windows\runner\resources\app_icon.ico',
            'SetupIconFile=' + str(ROOT / 'windows/runner/resources/app_icon.ico'),
        )
        decline_script = case / 'decline.iss'
        decline_script.write_text(script, encoding='utf-8')

        def install(name, installer_script):
            subprocess.run([
                str(ISCC), '/Qp', '/DInstallerTestMode=1',
                f'/DInstallerTestRoot={installed}', f'/DMyBuildDir={source}',
                f'/DMyOutputDir={output}', f'/DMyOutputBaseFilename={name}',
                str(installer_script),
            ], check=True, capture_output=True, text=True, timeout=120)
            subprocess.run([
                str(output / (name + '.exe')), '/VERYSILENT', '/SUPPRESSMSGBOXES',
                '/NORESTART', f'/DIR={installed}',
            ], check=True, capture_output=True, timeout=120)

        install('v1', original)
        (source / 'obsolete.txt').unlink()
        install('v2-decline', decline_script)
        manifest = installed / '.mbg-installed-files.txt'
        self.assertEqual((installed / 'obsolete.txt').read_text(), 'old release')
        self.assertIn('obsolete.txt', manifest.read_text(encoding='utf-8-sig'))

        install('v3-clean', original)
        self.assertFalse((installed / 'obsolete.txt').exists())
        self.assertNotIn('obsolete.txt', manifest.read_text(encoding='utf-8-sig'))

    @staticmethod
    def _remove_case(case, scratch):
        if case.parent != scratch or not case.name.startswith('case-'):
            raise RuntimeError('Refusing to remove an unexpected test directory')
        shutil.rmtree(case)


if __name__ == '__main__':
    unittest.main()
