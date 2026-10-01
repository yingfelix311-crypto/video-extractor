"""Local design preview with a native directory picker; never downloads or moves media."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import subprocess
import threading

HERE = Path(__file__).resolve().parent
STATE = HERE / '.destination.json'
PICKER = HERE / '.build/Folder Picker.app/Contents/MacOS/FolderPicker'
DEFAULT = str(Path.home() / 'Downloads/MeTube')
LOCK = threading.Lock()

def destination():
    try:
        return json.loads(STATE.read_text())['path']
    except (OSError, ValueError, KeyError):
        return DEFAULT

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HERE.parent), **kwargs)

    def json_reply(self, payload, status=200):
        raw = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == '/api/destination':
            return self.json_reply({'path': destination()})
        if any(part.startswith('.') for part in self.path.split('/')):
            return self.send_error(404)
        super().do_GET()

    def do_POST(self):
        if self.path != '/api/choose-folder':
            return self.send_error(404)
        # Only our same-origin UI can open a native panel. No arbitrary paths/commands.
        if (self.headers.get('Origin') != 'http://127.0.0.1:8766'
                or self.headers.get('X-Preview-Action') != 'choose-folder'
                or self.headers.get('Host') != '127.0.0.1:8766'):
            return self.json_reply({'error': '无法从这个页面打开文件夹选择器。'}, 403)
        if not LOCK.acquire(blocking=False):
            return self.json_reply({'error': '文件夹选择窗口已打开。'}, 409)
        try:
            result = subprocess.run([str(PICKER), destination()], capture_output=True,
                                    text=True, timeout=180, check=True)
            payload = json.loads(result.stdout)
            if 'path' in payload:
                folder = Path(payload['path'])
                if not folder.is_dir():
                    raise ValueError('Not a directory')
                STATE.write_text(json.dumps({'path': str(folder)}, ensure_ascii=False))
            self.json_reply(payload)
        except (OSError, ValueError, subprocess.SubprocessError):
            self.json_reply({'error': '未能选择文件夹，请重新点击选择。'}, 500)
        finally:
            LOCK.release()

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8766), Handler).serve_forever()
