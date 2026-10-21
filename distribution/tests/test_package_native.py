import importlib.util
from pathlib import Path
import unittest
import os
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('package_native', ROOT/'distribution/macos/package_native.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)

class PackageTests(unittest.TestCase):
    def runtime_fixture(self, root):
        (root/'bin').mkdir(parents=True)
        for name, version in [('colima','0.10.3'), ('docker','29.8.2'), ('limactl','2.2.0')]:
            tool=root/'bin'/name
            tool.write_text('#!/bin/sh\necho '+version+'\n')
            tool.chmod(0o755)
        (root/'share/lima/templates').mkdir(parents=True)
        (root/'share/lima/templates/default.yaml').write_text('fixture')
        (root/'share/lima/lima-guestagent.Linux-aarch64.gz').write_bytes(b'fixture')

    def test_release_name_tracks_app_version(self):
        self.assertEqual(package.release_name({'CFBundleShortVersionString':'1.4.0'}),
                         'Video-Extractor-Native-1.4.0-macOS-arm64')

    def test_release_version_cannot_escape_output_directory(self):
        with self.assertRaises(ValueError):
            package.release_name({'CFBundleShortVersionString':'../other'})

    def test_package_includes_executable_lima_wrapper_even_when_runtime_root_lacks_it(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); source=root/'source'; self.runtime_fixture(source)
            files=package.prepare_runtime(source,root/'payload')
            self.assertIn('bin/lima',files)
            self.assertTrue(os.access(root/'payload/bin/lima',os.X_OK))
            environment=dict(os.environ,LIMACTL=str(root/'payload/bin/limactl'))
            result=subprocess.run([str(root/'payload/bin/lima'),'--version'],env=environment,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('2.2.0',result.stdout)

    def test_missing_guest_agent_stops_packaging(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); self.runtime_fixture(root/'source')
            (root/'source/share/lima/lima-guestagent.Linux-aarch64.gz').unlink()
            with self.assertRaisesRegex(ValueError,'Missing Lima resource'):
                package.prepare_runtime(root/'source',root/'payload')

    def test_archive_contains_one_self_contained_signed_app(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); self.runtime_fixture(root/'source')
            app=Path(os.environ.get('NATIVE_TEST_APP',str(ROOT/'Shouxia/build/Video Extractor.app')))
            result=subprocess.run([sys.executable,str(ROOT/'distribution/macos/package_native.py'),
                '--app',str(app),'--runtime-root',str(root/'source'),'--output',str(root/'output')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            archive=next((root/'output').glob('*.zip'))
            with zipfile.ZipFile(archive) as zipped:
                paths=[p for p in zipped.namelist() if not p.startswith('__MACOSX/')]
                self.assertTrue(all(p=='Video Extractor.app/' or p.startswith('Video Extractor.app/') for p in paths))
                self.assertTrue(any(p.endswith('BackendInstaller/runtime/bin/lima') for p in paths))
                self.assertFalse(any('/Video Extractor.app/' in p for p in paths))
            subprocess.run(['ditto','-x','-k',str(archive),str(root/'extracted')],check=True)
            extracted=root/'extracted/Video Extractor.app'
            subprocess.run(['codesign','--verify','--deep','--strict',str(extracted)],check=True)
            verify=subprocess.run(['bash',str(extracted/'Contents/Resources/BackendInstaller/安装原版.command'),'--verify-only'],capture_output=True,text=True)
            self.assertEqual(verify.returncode,0,verify.stdout+verify.stderr)

if __name__ == '__main__': unittest.main()
