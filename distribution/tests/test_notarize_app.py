import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('notarize_app', Path(__file__).resolve().parents[1]/'macos/notarize_app.py')
notary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notary)


class AppSigningTests(unittest.TestCase):
    def app(self, root):
        app = root/'Video Extractor.app'
        (app/'Contents/MacOS').mkdir(parents=True)
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'local.felix.shouxia', 'CFBundleExecutable': 'Shouxia',
            'CFBundleShortVersionString': '1.4.1'}))
        (app/'Contents/MacOS/Shouxia').write_bytes(b'\xcf\xfa\xed\xfe' + b'fixture')
        return app

    def test_only_current_native_bundle_is_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.app(Path(tmp))
            self.assertEqual(notary.inspect_app(app)['CFBundleShortVersionString'], '1.4.1')
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'other'}))
            with self.assertRaises(ValueError):
                notary.inspect_app(app)

    def test_nested_code_requires_its_own_review(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.app(Path(tmp))
            (app/'Contents/MacOS/helper').write_bytes(b'\xcf\xfa\xed\xfeextra')
            with self.assertRaisesRegex(ValueError, 'nested code'):
                notary.inspect_app(app)

    def test_symlink_is_not_followed_into_unrelated_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.app(Path(tmp))
            (app/'Contents/Resources').symlink_to(Path(tmp), target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'symlink'):
                notary.inspect_app(app)

    def test_only_fingerprint_of_valid_developer_id_is_accepted(self):
        fingerprint = 'A'*40
        listing = f'  1) {fingerprint} "Developer ID Application: Example (TEAM123456)"\n'
        self.assertEqual(notary.select_identity(listing, fingerprint), fingerprint)
        for requested in ('-', 'Example', 'B'*40):
            with self.assertRaises(ValueError):
                notary.select_identity(listing, requested)
        with self.assertRaises(ValueError):
            notary.select_identity(listing.replace('Developer ID Application:', 'Apple Development:'), fingerprint)

    def test_output_parent_alias_cannot_put_copy_inside_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = self.app(root)
            alias = root/'alias'
            alias.symlink_to(app, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'separate'):
                notary.validate_output(app, alias/'candidate')
            self.assertFalse((app/'candidate').exists())

    def test_separate_output_is_canonical_and_existing_output_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = self.app(root)
            alias = root/'root-alias'
            alias.symlink_to(root, target_is_directory=True)
            self.assertEqual(notary.validate_output(app, alias/'candidate'), root.resolve()/'candidate')
            (root/'candidate').mkdir()
            with self.assertRaisesRegex(ValueError, 'exists'):
                notary.validate_output(app, alias/'candidate')


if __name__ == '__main__':
    unittest.main()
