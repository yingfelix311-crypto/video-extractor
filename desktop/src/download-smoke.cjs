const fs=require('node:fs');const path=require('node:path');const http=require('node:http');const assert=require('node:assert/strict');const {start}=require('./processes.cjs');const {downloadArgs}=require('./domain.cjs');const {publishFile,within}=require('./service.cjs');
async function downloadSmoke({dir,fixture,tools}){
 const bytes=fs.readFileSync(fixture);const server=http.createServer((req,res)=>{res.writeHead(200,{'Content-Type':'video/mp4','Content-Length':bytes.length});res.end(bytes);});
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
 try{
  for(const audio of [false,true]){
   const destination=path.join(dir,audio?'中文目录 音频':'中文目录 视频');fs.mkdirSync(destination);const folder=path.join(destination,'stage');fs.mkdirSync(folder);
   const info=path.join(dir,audio?'audio-info.json':'video-info.json');const publicUrl='https://example.com/fixture.mp4';fs.writeFileSync(info,JSON.stringify({id:audio?'audio':'video',title:'中文测试视频 🎬',url:`http://127.0.0.1:${server.address().port}/fixture.mp4`,ext:'mp4',webpage_url:publicUrl,extractor:'generic',extractor_key:'Generic'}));
   const args=downloadArgs({url:publicUrl,folder,audio,quality:480},tools);args.splice(-2,2);args.push('--load-info-json',info);
   let reported;const trace=[];const proc=start(tools.ytdlp,args,(line,error)=>{trace.push(line);if(!error&&line.startsWith('FILE:'))reported=line.slice(5).trim();},{env:{...process.env,ELECTRON_RUN_AS_NODE:'1',PYTHONIOENCODING:'cp936',PYTHONUTF8:'0'}});const timeout=setTimeout(()=>proc.cancel(),60000);
   try{await proc.promise;}catch(e){throw new Error(e.message+'\n'+trace.slice(-12).join('\n'));}finally{clearTimeout(timeout);}
   assert.ok(reported,'yt-dlp did not emit a final path');assert.ok(within(reported,folder),'final path escaped staging');assert.ok(fs.existsSync(reported),`Engine path does not match actual file: ${reported}`);assert.ok(reported.includes('中文测试视频'));const saved=publishFile(reported,destination);assert.equal(path.extname(saved),audio?'.mp3':'.mp4');assert.ok(fs.statSync(saved).size>0);fs.unlinkSync(saved);fs.rmSync(folder,{recursive:true});
  }
  console.log('DOWNLOAD_SMOKE_PASS: bundled yt-dlp downloads video and MP3 with Chinese titles/directories under cp936, final paths match actual files.');
 }finally{await new Promise(resolve=>server.close(resolve));}
}
module.exports={downloadSmoke};
