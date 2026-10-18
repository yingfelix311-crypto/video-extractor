import contextlib
import functools
import http.server
import json
from pathlib import Path
import subprocess
import threading
import time
from urllib.request import Request,urlopen

root=Path('/tmp/ve-quality-fixture');root.mkdir(exist_ok=True)
for height,width in [(720,1280),(1440,2560),(2160,3840)]:
 subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i',f'color=c=blue:size={width}x{height}:rate=6','-f','lavfi','-i','sine=frequency=440:sample_rate=44100','-t','0.5','-c:v','libx264','-preset','ultrafast','-threads','1','-c:a','aac','-f','hls','-hls_time','1','-hls_list_size','0',str(root/f'{height}.m3u8')],check=True)
(root/'master.m3u8').write_text('#EXTM3U\n'+''.join(f'#EXT-X-STREAM-INF:BANDWIDTH={height*1000},RESOLUTION={width}x{height}\n{height}.m3u8\n' for height,width in [(720,1280),(1440,2560),(2160,3840)]))
(root/'low.m3u8').write_text('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=720000,RESOLUTION=1280x720\n720.m3u8\n')
class Handler(http.server.SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
handler=functools.partial(Handler,directory=str(root))
server=http.server.ThreadingHTTPServer(('127.0.0.1',18888),handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
def get(route):
 with urlopen('http://127.0.0.1:8081/'+route,timeout=10) as response:return json.load(response)
def post(route,payload):
 with urlopen(Request('http://127.0.0.1:8081/'+route,data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'}),timeout=40) as response:return json.load(response)
for _ in range(30):
 try:get('history');break
 except Exception:time.sleep(1)
receipts=[]
post('delete',{'ids':['http://127.0.0.1:18888/master.m3u8'],'where':'done','delete_files':False})
for ceiling,kind,source,expected_height in [('1440','video','master',1440),('2160','video','master',2160),('best','audio','master',None),('2160','video','low',720)]:
 payload={'url':f'http://127.0.0.1:18888/{source}.m3u8','quality':ceiling,'format':'mp3' if kind=='audio' else 'any','download_type':kind,'folder':'smoke-'+kind+'-'+ceiling}
 result=post('add',payload)
 assert result.get('status')=='ok',result
 for _ in range(120):
  history=get('history');raw=history.get('done',[]);done=list(raw.values()) if isinstance(raw,dict) else raw
  if done:
   item=done[0];break
  time.sleep(0.5)
 else:raise AssertionError('download did not finish')
 assert item['status']=='finished',item.get('error') or item.get('msg')
 file=Path('/downloads')/payload['folder']/item['filename']
 probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(file)]))
 videos=[s for s in probe['streams'] if s['codec_type']=='video'];audio=[s for s in probe['streams'] if s['codec_type']=='audio']
 assert audio,'audio missing'
 if kind=='video':assert videos[0]['height']==expected_height,(ceiling,videos[0]['height'])
 else:assert not videos and audio[0]['codec_name']=='mp3'
 receipts.append({'quality':ceiling,'kind':kind,'source':source,'bytes':file.stat().st_size,'height':videos[0]['height'] if videos else None,'audio':audio[0]['codec_name']})
 post('delete',{'ids':[item['url']],'where':'done','delete_files':False})
print(json.dumps(receipts,indent=2))
server.shutdown()
