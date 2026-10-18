import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('package_native', ROOT/'distribution/macos/package_native.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)

class PackageTests(unittest.TestCase):
    def test_release_name_tracks_app_version(self):
        self.assertEqual(package.release_name({'CFBundleShortVersionString':'1.4.0'}),
                         'Video-Extractor-Native-1.4.0-macOS-arm64')

    def test_release_version_cannot_escape_output_directory(self):
        with self.assertRaises(ValueError):
            package.release_name({'CFBundleShortVersionString':'../other'})

if __name__ == '__main__': unittest.main()
