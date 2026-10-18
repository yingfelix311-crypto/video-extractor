#!/usr/bin/env python3
"""Maintainer-only native app signing. This does not notarize the installer/runtime."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

MACHO = {bytes.fromhex(x) for x in ('cffaedfe', 'feedfacf', 'cafebabe', 'bebafeca', 'cefaedfe', 'feedface', 'cafebabf', 'bfbafeca')}


def inspect_app(app):
    if app.is_symlink() or not app.is_dir() or app.suffix != '.app':
        raise ValueError('Input must be a native .app directory, not a symlink.')
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'local.felix.shouxia' or info.get('CFBundleExecutable') != 'Shouxia':
        raise ValueError('Only the current Video Extractor native bundle is accepted.')
    executable = app/'Contents/MacOS/Shouxia'
    if not executable.is_file() or executable.is_symlink():
        raise ValueError('Native executable is missing or a symlink.')
    for path in app.rglob('*'):
        if path.is_symlink():
            raise ValueError('Unexpected symlink: review the bundle before signing.')
        if path.is_file() and path != executable:
            with path.open('rb') as stream:
                if stream.read(4) in MACHO or path.stat().st_mode & 0o111:
                    raise ValueError('Unexpected nested code: sign/review each component explicitly first.')
    with executable.open('rb') as stream:
        if stream.read(4) not in MACHO:
            raise ValueError('Shouxia is not a Mach-O executable.')
    return info


def select_identity(listing, fingerprint):
    fingerprint = fingerprint.upper()
    if not re.fullmatch('[0-9A-F]{40}', fingerprint):
        raise ValueError('Supply the SHA-1 fingerprint of a valid Developer ID Application identity.')
    pattern = rf'\b{fingerprint}\s+"Developer ID Application: [^"\n]+"'
    if not re.search(pattern, listing):
        raise ValueError('No matching valid Developer ID Application identity with a private key was found.')
    return fingerprint


def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True, capture_output=capture).stdout


def validate_output(app, output):
    if output.exists() or output.is_symlink():
        raise ValueError('Output already exists; choose a new directory. Nothing will be overwritten.')
    # Resolve parent aliases too: absolute() alone can hide an output inside the input.
    canonical_app = app.resolve(strict=True)
    canonical_output = output.resolve(strict=False)
    if canonical_output == canonical_app or canonical_app in canonical_output.parents or canonical_output in canonical_app.parents:
        raise ValueError('Output must be separate from the input bundle.')
    return canonical_output


def verify_architecture(executable):
    run('lipo', str(executable), '-verify_arch', 'arm64', capture=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--identity', required=True, help='40-character SHA-1 identity fingerprint; never a private key')
    parser.add_argument('--profile', required=True, help='Existing notarytool keychain profile name')
    parser.add_argument('--output', type=Path, required=True, help='New directory; existing paths are refused')
    parser.add_argument('--check', action='store_true', help='Read-only local prerequisites; no signing/submission')
    args = parser.parse_args()
    app = args.app.absolute()
    inspect_app(app)
    if sys.platform != 'darwin':
        raise ValueError('Run this helper on macOS.')
    for tool in ('notarytool', 'stapler'):
        run('xcrun', '--find', tool, capture=True)
    identity = select_identity(run('security', 'find-identity', '-v', '-p', 'codesigning', capture=True), args.identity)
    if not args.profile.strip():
        raise ValueError('A keychain profile is required. Store credentials with notarytool first.')
    output = validate_output(app, args.output)
    verify_architecture(app/'Contents/MacOS/Shouxia')
    if args.check:
        print('Local prerequisites pass. Keychain-profile authentication and Apple acceptance are not yet verified.')
        return
    # Keep all intermediate code outside the installed/source bundle. No --deep signing.
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='native-notary-', dir=output) as tmp:
        stage = Path(tmp)
        copied = stage/'Video Extractor.app'
        run('ditto', str(app), str(copied))
        run('codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp', str(copied))
        run('codesign', '--verify', '--strict', '--verbose=2', str(copied))
        submission = stage/'submission.zip'
        run('ditto', '-c', '-k', '--keepParent', str(copied), str(submission))
        result = json.loads(run('xcrun', 'notarytool', 'submit', str(submission), '--keychain-profile', args.profile,
                                '--wait', '--output-format', 'json', capture=True))
        (output/'notarization.json').write_text(json.dumps(result, indent=2)+'\n')
        if result.get('status') != 'Accepted':
            raise ValueError('Apple did not accept this submission. No distributable archive was produced.')
        run('xcrun', 'stapler', 'staple', str(copied))
        run('xcrun', 'stapler', 'validate', str(copied))
        run('codesign', '--verify', '--strict', '--verbose=2', str(copied))
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', str(copied))
        final_app = output/copied.name
        shutil.move(str(copied), final_app)
        run('ditto', '-c', '-k', '--keepParent', str(final_app), str(output/'Video-Extractor-app-notarized.zip'))
    print(f'App-only notarized output: {output}. Installer and downloaded runtime remain separate release gates.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Notarization stopped: {error}', file=sys.stderr)
        sys.exit(1)
