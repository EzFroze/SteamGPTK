#!/usr/bin/env python3
"""Run the real launch helpers against temporary prefixes; no Steam or Wine is started."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(sys.argv.pop(1) if len(sys.argv) > 1 else 'dylib/feats/compat_run.sh').read_text()


class LaunchFixes(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='steamgptk-launch-check-')
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.pfx = self.root / 'pfx'
        (self.pfx / 'drive_c/windows/system32').mkdir(parents=True)
        (self.root / 'runner/share/wine').mkdir(parents=True)
        self.inf = self.root / 'runner/share/wine/wine.inf'
        self.inf.write_text('Wine fixture')
        (self.pfx / '.update-timestamp').write_text(str(int(self.inf.stat().st_mtime)) + '\n')
        self.env = dict(os.environ, WINEPREFIX=str(self.pfx), CX_ROOT=str(self.root / 'runner'),
                        STEAM_COMPAT_DATA_PATH=str(self.root), log=str(self.root / 'log'))

    def run_helpers(self, names, body, **env):
        functions = []
        for name in names:
            pattern = r'\(\) \(\n.*?^\)\n' if name == 'install_bundle' else r'\(\) \{\n.*?^\}\n'
            match = re.search(r'^' + re.escape(name) + pattern, SOURCE, re.M | re.S)
            self.assertIsNotNone(match, 'missing launch helper: ' + name)
            functions.append(match.group())
        result = subprocess.run(['/bin/sh', '-ec', '\n'.join(functions) + '\n' + body],
                                env=dict(self.env, **env), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def test_native_visual_cpp_only_and_manual_override_order(self):
        windows = self.pfx / 'drive_c/windows/system32'
        (windows / 'msvcp140.dll').write_bytes(b'X' * 64 + b'Wine builtin DLL')
        (windows / 'vcruntime140.dll').write_bytes(b'X' * 64 + b'Microsoft runtime')
        got = self.run_helpers(['native_vc_runtime'], 'native_vc_runtime')
        self.assertEqual(got, 'vcruntime140=n,b;')
        got = self.run_helpers(['native_vc_runtime'],
                               'printf "%s%s" "$(native_vc_runtime)" "$WINEDLLOVERRIDES"',
                               WINEDLLOVERRIDES='vcruntime140=b')
        self.assertEqual(got, 'vcruntime140=n,b;vcruntime140=b')

    def test_non_steam_shortcut_ids(self):
        for value, expected in [('220', 'no'), ('0', 'no'), ('123x', 'no'),
                                ('9223372036888330240', 'yes'), ('18446744069448138752', 'yes'),
                                ('18446744073709551615', 'no'), ('00033554432', 'yes')]:
            with self.subTest(value=value):
                got = self.run_helpers(['shortcut_game_id'],
                    'if shortcut_game_id "$VALUE"; then echo yes; else echo no; fi', VALUE=value)
                self.assertEqual(got, expected)

    def test_retina_dpi_is_not_doubled_on_every_launch(self):
        for previous, dpi, enabled, expected in [('n', '00000060', '1', '"LogPixels"=dword:000000c0'),
                                                  ('y', '000000c0', '1', ''),
                                                  ('y', '000000c0', '0', '"LogPixels"=dword:00000060')]:
            (self.pfx / 'user.reg').write_text(
                '[Software\\\\Wine\\\\Mac Driver]\n"RetinaMode"="' + previous + '"\n'
                '[Control Panel\\\\Desktop]\n"LogPixels"=dword:' + dpi + '\n')
            got = self.run_helpers(['plan_logpixels'], 'plan_logpixels; printf "%s" "$dpi_value"',
                                   STEAMGPTK_RETINA=enabled)
            self.assertEqual(got, expected)

    def test_registry_import_skips_only_matching_current_prefix(self):
        (self.pfx / 'system.reg').write_text('[Software\\\\Test]\n"Value"="ready"\n')
        (self.pfx / 'user.reg').write_text('[Software\\\\Wine\\\\Mac Driver]\n"RetinaMode"="y"\n')
        settings = self.root / 'settings.reg'
        settings.write_text('Windows Registry Editor Version 5.00\r\n'
                            '[HKEY_LOCAL_MACHINE\\Software\\Test]\r\n"Value"="ready"\r\n'
                            '[HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]\r\n"RetinaMode"="y"\r\n')
        def applied():
            return self.run_helpers(['prefix_up_to_date', 'settings_already_applied'],
                'if settings_already_applied; then echo yes; else echo no; fi', settings_file=str(settings))
        self.assertEqual(applied(), 'yes')
        (self.pfx / 'system.reg').write_text('[Software\\\\Test]\n"Value"="changed"\n')
        self.assertEqual(applied(), 'no')
        (self.pfx / 'system.reg').write_text('[Software\\\\Test]\n"Value"="ready"\n')
        (self.pfx / '.update-timestamp').write_text('1\n')
        self.assertEqual(applied(), 'no')

    def test_preparation_lock_is_shared_with_app_and_not_leaked(self):
        names = ['claim_prefix', 'without_lock_fds']
        marker = self.root / 'should-not-start'
        got = self.run_helpers(names, '''
claim_prefix
if /usr/bin/lockf -s -t 0 "$STEAM_COMPAT_DATA_PATH/.steamgptk-prefix.lock" touch "$MARKER" 2>/dev/null; then
  echo unexpected; exit 1
fi
without_lock_fds /bin/sh -c '/bin/sleep 1 >/dev/null 2>&1 &'
exec 9>&-
/usr/bin/lockf -s -t 0 "$STEAM_COMPAT_DATA_PATH/.steamgptk-prefix.lock" /usr/bin/true
echo released
''', MARKER=str(marker))
        self.assertEqual(got, 'released')
        self.assertFalse(marker.exists())

    def test_preparation_creates_first_launch_compatdata_directory(self):
        fresh = self.root / 'new-library/steamapps/compatdata/220'
        self.run_helpers(['claim_prefix'], 'claim_prefix', STEAM_COMPAT_DATA_PATH=str(fresh))
        self.assertTrue((fresh / '.steamgptk-prefix.lock').is_file())

    def test_refused_prefix_releases_lock_before_rebuild_prompt(self):
        dll = self.pfx / 'drive_c/windows/system32/ntdll.dll'
        pe = bytearray(128)
        pe[60:64] = (64).to_bytes(4, 'little')
        pe[64:70] = b'PE\x00\x00\x4c\x01'
        dll.write_bytes(pe)
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        prompt = bin_dir / 'osascript'
        prompt.write_text('''#!/bin/sh
cat >/dev/null
/usr/bin/lockf -s -t 0 "$STEAM_COMPAT_DATA_PATH/.steamgptk-prefix.lock" touch "$REBUILD_ALLOWED"
''')
        prompt.chmod(0o755)
        marker = self.root / 'rebuild-allowed'
        self.run_helpers(['claim_prefix', 'without_lock_fds', 'prefix_machine', 'tool_name', 'refuse_foreign_prefix'], '''
if (claim_prefix; refuse_foreign_prefix); then exit 1; fi
test -f "$REBUILD_ALLOWED"
''', wine_unix='/runner/lib/wine/x86_64-unix', verb='waitforexitandrun',
                         PATH=str(bin_dir) + ':' + self.env['PATH'], REBUILD_ALLOWED=str(marker))
        self.assertTrue(marker.exists())

    def test_registry_import_preserves_helper_video_settings(self):
        calls = self.root / 'calls'
        imported = self.root / 'imported.reg'
        wine = self.root / 'wine'
        wine.write_text(r'''#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
cp "$WINEPREFIX/drive_c/${3#C:\\}" "$IMPORTED"
''')
        wine.chmod(0o755)
        server = self.root / 'wineserver'
        server.write_text('#!/bin/sh\nprintf "server %s\\n" "$*" >> "$CALLS"\n')
        server.chmod(0o755)
        names = ['without_lock_fds', 'plan_logpixels', 'video_lines', 'prefix_up_to_date',
                 'settings_already_applied', 'import_prefix_settings']
        self.run_helpers(names, 'import_prefix_settings', verb='run', STEAMGPTK_RETINA='1',
                         WINELOADER=str(wine), WINESERVER=str(server), CALLS=str(calls), IMPORTED=str(imported))
        self.assertEqual(calls.read_text().splitlines()[0].split()[:2], ['reg', 'import'])
        data = imported.read_bytes()
        self.assertIn(b'"ShowCrashDialog"=dword:00000000\r\n', data)
        self.assertIn(b'[HKEY_LOCAL_MACHINE\\Software\\Classes\\steam]', data)
        self.assertNotIn(b'RetinaMode', data)
        self.assertNotIn(b'LogPixels', data)
        self.assertFalse(list((self.pfx / 'drive_c').glob('steamgptk-settings.*')))

    def bundle_fixture(self):
        launcher = self.root / 'launchers/220'
        work = launcher / '.build.test'
        stage = work / 'new/Game.app'
        (stage / 'Contents').mkdir(parents=True)
        (stage / 'Contents/Info.plist').write_text('fixture plist')
        return dict(loader_root=str(launcher), loader_work=str(work), loader_stage=str(stage),
                    loader_app=str(launcher / 'Game.app'), np_support='/nonexistent')

    def test_unchanged_launcher_keeps_inode_and_registration_timestamp(self):
        env = self.bundle_fixture()
        shutil.copytree(env['loader_stage'], env['loader_app'])
        app = Path(env['loader_app'])
        before = app.stat().st_ino, (app / 'Contents/Info.plist').stat().st_mtime_ns
        self.run_helpers(['bundle_listing', 'bundle_matches', 'install_bundle'], 'install_bundle', **env)
        self.assertEqual((app.stat().st_ino, (app / 'Contents/Info.plist').stat().st_mtime_ns), before)
        self.assertFalse(Path(env['loader_work']).exists())

    def test_failed_launcher_install_rolls_back_existing_bundle(self):
        env = self.bundle_fixture()
        app = Path(env['loader_app'])
        (app / 'Contents').mkdir(parents=True)
        (app / 'Contents/Info.plist').write_text('old plist')
        self.run_helpers(['bundle_listing', 'bundle_matches', 'install_bundle'], '''
mv() { [ "$1" != "$loader_stage" ] || return 1; command mv "$@"; }
if install_bundle; then echo 'unexpected success'; exit 1; fi
''', **env)
        self.assertEqual((app / 'Contents/Info.plist').read_text(), 'old plist')
        self.assertFalse(list(app.parent.glob('.backup.*')))


if __name__ == '__main__':
    unittest.main()
