"""Build a self-contained native app with a resumable first-launch backend installer."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inventory(root):
    return {p.relative_to(root).as_posix(): digest(p)
            for p in sorted(root.rglob('*')) if p.is_file()}


def release_name(info):
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}', version):
        raise ValueError('Invalid app version')
    return f'Video-Extractor-Native-{version}-macOS-arm64'


def prepare_runtime(runtime_root, destination):
    """Colima checks BOTH lima and limactl; a limactl-only package cannot boot."""
    tools = [('colima', '0.10.3', ['version']),
             ('docker', '29.8.2', ['--version']),
             ('limactl', '2.2.0', ['--version'])]
    for tool, version, flags in tools:
        source = runtime_root/'bin'/tool
        reported = subprocess.check_output([str(source), *flags], text=True, stderr=subprocess.STDOUT)
        if version not in reported or not source.stat().st_mode & 0o111:
            raise ValueError(f'Unexpected {tool} version or permissions: {reported}')
    share = runtime_root/'share/lima'
    for required in ['lima-guestagent.Linux-aarch64.gz', 'templates/default.yaml']:
        if not (share/required).is_file():
            raise ValueError(f'Missing Lima resource: {required}')
    (destination/'bin').mkdir(parents=True)
    for tool, _, _ in tools:
        shutil.copy2(runtime_root/'bin'/tool, destination/'bin'/tool)
    # Official v2.2.0 wrapper, vendored with its upstream SPDX notice.
    shutil.copy2(ROOT/'distribution/macos/lima', destination/'bin/lima')
    (destination/'bin/lima').chmod(0o755)
    shutil.copytree(share, destination/'share/lima')
    return inventory(destination)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--runtime-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'local.felix.shouxia' or info['CFBundleExecutable'] != 'Shouxia':
        raise ValueError('Only the original native app may be distributed')
    if (app/'Contents/Frameworks/Electron Framework.framework').exists():
        raise ValueError('Electron client is not the original app')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True, check=True)
    if 'Signature=adhoc' not in signature.stderr:
        raise ValueError('Package an ad-hoc build first; sign/notarize the complete payload afterwards')
    if args.output.exists():
        raise ValueError('Output already exists; choose a new directory')
    output = args.output
    output.mkdir(parents=True)
    name = release_name(info)
    packaged_app = output/'Video Extractor.app'
    subprocess.run(['ditto', str(app), str(packaged_app)], check=True)
    payload = packaged_app/'Contents/Resources/BackendInstaller'
    if payload.exists():
        raise ValueError('Input app already contains a backend installer; use a fresh build')
    payload.mkdir(parents=True)
    for filename in ['安装原版.command', 'runtime.env', 'preflight.sh', 'backend_setup.py']:
        shutil.copy2(ROOT/'distribution/macos'/filename, payload/filename)
    shutil.copytree(ROOT/'Shouxia/BackendPlugins/yt_dlp_plugins', payload/'BackendPlugins/yt_dlp_plugins',
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    files = prepare_runtime(args.runtime_root, payload/'runtime')
    shutil.copytree(ROOT/'distribution/macos/licenses', payload/'licenses')
    (payload/'runtime-files.txt').write_text('\n'.join(files)+'\n')
    manifest = {
        'product': 'native SwiftUI/AVFoundation app with first-launch backend setup',
        'version': info['CFBundleShortVersionString'],
        'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'nativeExecutableSHA256': digest(app/'Contents/MacOS/Shouxia'),
        'runtimeFiles': files,
        'backend': 'pinned image; no user state, VM disk, cookies, history or media',
        'status': 'prerelease, ad-hoc signed, not notarized; clean-Mac acceptance required',
    }
    (payload/'ORIGINAL-MANIFEST.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    (payload/'SHA256SUMS.txt').write_text('\n'.join(f'{value}  {file}' for file, value in inventory(payload).items())+'\n')
    # Preserve upstream signatures/entitlements; seal the outer app only.
    subprocess.run(['codesign', '--force', '--sign', '-', str(packaged_app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(packaged_app)], check=True)
    archive = output/(name+'.zip')
    subprocess.run(['ditto', '-c', '-k', '--keepParent', str(packaged_app), str(archive)], check=True)
    (output/'SHA256SUMS.txt').write_text(digest(archive)+'  '+archive.name+'\n')
    shutil.copy2(ROOT/'docs/INSTALL-MAC.md', output/'INSTALL.md')
    shutil.copy2(payload/'ORIGINAL-MANIFEST.json', output/'ORIGINAL-MANIFEST.json')
    print('Self-contained app archive:', archive)


if __name__ == '__main__':
    main()
