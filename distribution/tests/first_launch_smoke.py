"""Opt-in real video/MP3 check. Uses public project media and removes only its own tasks."""
import argparse
import json
import time
import uuid
import subprocess
from pathlib import Path, PurePosixPath
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--backend', default='http://127.0.0.1:8081')
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--docker', default=str(Path.home()/'.local/bin/docker'))
    args = parser.parse_args()
    token = uuid.uuid4().hex
    source = 'https://raw.githubusercontent.com/yingfelix311-crypto/video-extractor/main/docs/marketing/demo-source.mp4'

    def request(route, payload=None):
        body = json.dumps(payload).encode() if payload is not None else None
        with urlopen(Request(args.backend.rstrip('/')+'/'+route, data=body,
                             headers={'Content-Type': 'application/json'}), timeout=30) as response:
            return json.load(response)

    def records(history, name):
        values = history.get(name, [])
        return list(values.values()) if isinstance(values, dict) else values

    history = request('history')
    if records(history, 'queue') or records(history, 'pending'):
        raise RuntimeError('Finish existing downloads before running the smoke check')
    receipts = []
    for kind in ['video', 'audio']:
        url = source+'?first-launch-smoke='+token+'-'+kind
        folder = 'VideoExtractor/Smoke-'+token+'-'+kind
        added = False
        try:
            result = request('add', {'url': url, 'quality': 'best', 'format': 'mp3' if kind == 'audio' else 'any',
                                     'download_type': kind, 'folder': folder})
            if result.get('status') != 'ok':
                raise RuntimeError('Smoke task was not accepted: '+str(result.get('msg', result.get('status'))))
            added = True
            deadline = time.monotonic()+args.timeout
            while time.monotonic() < deadline:
                history = request('history')
                item = next((x for x in records(history, 'done') if x.get('url') == url and x.get('folder') == folder), None)
                if item:
                    if item.get('status') != 'finished':
                        raise RuntimeError('Smoke task failed: '+str(item.get('error') or item.get('msg') or item.get('status')))
                    filename = item.get('filename', '')
                    if not filename or (kind == 'audio' and not filename.lower().endswith('.mp3')):
                        raise RuntimeError('Unexpected output format')
                    if PurePosixPath(filename).name != filename:
                        raise RuntimeError('Unexpected output path')
                    probe=json.loads(subprocess.check_output([args.docker,'--context','colima-metube','exec','metube',
                        'ffprobe','-v','error','-show_streams','-show_format','-of','json','/downloads/'+folder+'/'+filename]))
                    streams=probe['streams']
                    videos=[s for s in streams if s.get('codec_type')=='video']
                    audio=[s for s in streams if s.get('codec_type')=='audio']
                    if float(probe['format']['duration']) <= 0:
                        raise RuntimeError('Empty output duration')
                    if kind=='video' and not videos:
                        raise RuntimeError('Video stream missing')
                    if kind=='audio' and (videos or not audio or audio[0].get('codec_name')!='mp3'):
                        raise RuntimeError('MP3 stream missing')
                    receipts.append({'kind': kind, 'status': item['status'], 'filename': filename, 'folder': folder,
                                     'duration':float(probe['format']['duration']), 'bytes':int(probe['format']['size'])})
                    break
                time.sleep(1)
            else:
                raise TimeoutError('Smoke task did not finish in time')
        finally:
            if added:
                # The URL includes a random token; no pre-existing user task is selected.
                history = request('history')
                active = [x for name in ['queue', 'pending'] for x in records(history, name) if x.get('url') == url]
                if not active:
                    request('delete', {'ids': [url], 'where': 'done', 'delete_files': True})
                else:
                    print('Smoke task is still active; retained for inspection: '+folder)
    print(json.dumps(receipts, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
