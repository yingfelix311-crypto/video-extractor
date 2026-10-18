"""Install only the shipped, hash-checked extractor; never read browser data."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import uuid


def validate_plugin_paths(root):
    # /downloads is the trusted bind mount. Reject user-created redirections
    # below it before privileged writes, backup creation or marker cleanup.
    paths = [root.parent, root, root/'yt_dlp_plugins',
             root/'yt_dlp_plugins/extractor', root.parent/'plugin-backups',
             root/'.activation-pending']
    if any(path.is_symlink() for path in paths):
        raise ValueError('解析插件目录包含符号链接，未修改')


def finalize_plugin(root):
    validate_plugin_paths(root)
    (root/'.activation-pending').unlink(missing_ok=True)


def install_plugin(data, expected_hash, root, link):
    if hashlib.sha256(data).hexdigest() != expected_hash:
        raise ValueError('解析插件校验失败')
    validate_plugin_paths(root)
    if link.exists() or link.is_symlink():
        if not link.is_symlink() or link.resolve() != root.resolve():
            raise ValueError('已有解析插件目录不属于此安装器，未修改')
    target = root/'yt_dlp_plugins/extractor/shouxia_douyin.py'
    if target.is_symlink():
        raise ValueError('解析插件文件不能是符号链接')
    changed = not target.exists() or target.read_bytes() != data or not link.exists()
    pending = root/'.activation-pending'
    if not changed:
        return pending.exists()
    if target.exists():
        backup = root.parent/'plugin-backups'/uuid.uuid4().hex
        backup.mkdir(parents=True)
        shutil.copy2(target, backup/target.name)
    target.parent.mkdir(parents=True, exist_ok=True)
    # Record the need for service activation before replacing plugin bytes.
    pending.write_text(expected_hash + '\n')
    handle, temporary = tempfile.mkstemp(dir=target.parent, prefix='.install-')
    try:
        with os.fdopen(handle, 'wb') as stream:
            stream.write(data)
        os.chmod(temporary, 0o644)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    link.parent.mkdir(parents=True, exist_ok=True)
    if not link.is_symlink():
        link.symlink_to(root, target_is_directory=True)
    return True


def verify_runtime():
    from yt_dlp import YoutubeDL
    from yt_dlp.networking.impersonate import ImpersonateTarget
    for name in ['ffmpeg', 'ffprobe']:
        if not shutil.which(name):
            raise ValueError(name + ' 尚未安装')
    if not (shutil.which('deno') or shutil.which('node')):
        raise ValueError('尚未安装 JavaScript 运行时')
    if not YoutubeDL({'quiet': True})._impersonate_target_available(
            ImpersonateTarget.from_str('chrome-131:android-14')):
        raise ValueError('下载后台缺少抖音所需的 curl_cffi Android 支持')


def main():
    mode = sys.argv[1]
    verify_runtime()
    if mode == '--install':
        # Refuse service restarts while the backend owns active work.
        from urllib.request import urlopen
        with urlopen('http://127.0.0.1:8081/history', timeout=5) as response:
            history = json.load(response)
        if history.get('queue') or history.get('pending'):
            raise ValueError('后台仍有任务，请完成后重新运行安装器')
        changed = install_plugin(sys.stdin.buffer.read(), sys.argv[2],
                                 Path('/downloads/.shouxia/yt-dlp-plugins'),
                                 Path('/etc/yt-dlp/plugins/shouxia'))
        print('changed' if changed else 'unchanged')
    elif mode in ('--check', '--activate'):
        from yt_dlp import YoutubeDL
        extractor = YoutubeDL({'quiet': True}).get_info_extractor('Douyin')
        if not extractor._real_extract.__module__.endswith('shouxia_douyin'):
            raise ValueError('抖音解析插件尚未加载')
        root = Path('/downloads/.shouxia/yt-dlp-plugins')
        validate_plugin_paths(root)
        if mode == '--activate':
            finalize_plugin(root)
        elif (root/'.activation-pending').exists():
            raise ValueError('解析插件等待后台重启，请重新运行安装器')
        print('下载依赖和抖音解析插件已就绪')
    else:
        raise ValueError('无效的配置模式')

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('后台配置失败：' + str(error), file=sys.stderr)
        sys.exit(1)
