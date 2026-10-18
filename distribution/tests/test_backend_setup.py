import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class BackendSetupTests(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location('backend_setup', ROOT/'distribution/macos/backend_setup.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_installs_verified_plugin_and_is_idempotent(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)/'persistent'
            link = Path(folder)/'plugins/shouxia'
            data = b'# a plugin\n'
            digest = hashlib.sha256(data).hexdigest()
            self.assertTrue(module.install_plugin(data, digest, root, link))
            self.assertFalse(module.install_plugin(data, digest, root, link))
            self.assertEqual((root/'yt_dlp_plugins/extractor/shouxia_douyin.py').read_bytes(), data)
            self.assertEqual(link.resolve(), root.resolve())

    def test_invalid_hash_does_not_create_or_overwrite_anything(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)/'persistent'
            with self.assertRaises(ValueError):
                module.install_plugin(b'bad', '0'*64, root, Path(folder)/'link')
            self.assertFalse(root.exists())

    def test_foreign_plugin_link_is_preserved(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)/'persistent'
            link = Path(folder)/'shouxia'
            link.mkdir()
            data = b'# a plugin\n'
            with self.assertRaises(ValueError):
                module.install_plugin(data, hashlib.sha256(data).hexdigest(), root, link)
            self.assertTrue(link.is_dir())
            self.assertFalse(root.exists())

    def test_replacement_retains_previous_plugin(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)/'persistent'
            link = Path(folder)/'plugins/shouxia'
            for data in [b'# old\n', b'# new\n']:
                module.install_plugin(data, hashlib.sha256(data).hexdigest(), root, link)
            backups = list((root.parent/'plugin-backups').glob('*/shouxia_douyin.py'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), b'# old\n')

if __name__ == '__main__':
    unittest.main()
