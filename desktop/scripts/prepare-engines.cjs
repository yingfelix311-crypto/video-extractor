const fs=require('node:fs'); const path=require('node:path');const crypto=require('node:crypto'); const zlib=require('node:zlib');
const versions={ytdlp:'2026.08.19',ffmpeg:'b6.1.1'};
async function download(url,target){
 if(fs.existsSync(target))return;
 console.log('Downloading',path.basename(target));const response=await fetch(url,{signal:AbortSignal.timeout(180000)}); if(!response.ok)throw new Error(`${response.status} ${url}`);
 const body=Buffer.from(await response.arrayBuffer());fs.writeFileSync(target,url.endsWith('.gz')?zlib.gunzipSync(body):body);fs.chmodSync(target,0o755);
}
async function main(){
 const platform=process.platform==='darwin'?'mac':process.platform==='win32'?'win':null;
 const arch=process.arch; if(!platform||!['arm64','x64'].includes(arch)||platform==='win'&&arch!=='x64')throw new Error('Build on macOS arm64/x64 or Windows x64.');
 const out=path.join(__dirname,'..','engines',`${platform}-${arch}`); const licenses=path.join(__dirname,'..','resources','licenses');fs.mkdirSync(out,{recursive:true});fs.mkdirSync(licenses,{recursive:true});
 const exe=platform==='win'?'.exe':''; const asset=platform==='mac'?'yt-dlp_macos':'yt-dlp.exe';
 const ytdlpBase=`https://github.com/yt-dlp/yt-dlp/releases/download/${versions.ytdlp}/`;
 await download(ytdlpBase+asset,path.join(out,'yt-dlp'+exe));
 const checks=await fetch(ytdlpBase+'SHA2-256SUMS').then(r=>{if(!r.ok)throw new Error('yt-dlp checksum unavailable');return r.text();});
 const expected=checks.split('\n').find(s=>s.trim().endsWith(' '+asset))?.split(/\s+/)[0];
 const actual=crypto.createHash('sha256').update(fs.readFileSync(path.join(out,'yt-dlp'+exe))).digest('hex');if(!expected||actual!==expected)throw new Error('yt-dlp checksum mismatch');
 const ffPlatform=platform==='mac'?'darwin':'win32';const ffBase=`https://github.com/eugeneware/ffmpeg-static/releases/download/${versions.ffmpeg}/`;
 for(const tool of ['ffmpeg','ffprobe'])await download(`${ffBase}${tool}-${ffPlatform}-${arch}.gz`,path.join(out,tool+exe));
 await download(`${ffBase}${ffPlatform}-${arch}.LICENSE`,path.join(licenses,`FFmpeg-${platform}-${arch}-LICENSE.txt`));
 await download(`${ffBase}${ffPlatform}-${arch}.README`,path.join(licenses,`FFmpeg-${platform}-${arch}-README.txt`));
 await download(`https://raw.githubusercontent.com/yt-dlp/yt-dlp/${versions.ytdlp}/LICENSE`,path.join(licenses,'yt-dlp-LICENSE.txt'));
 await download(`https://raw.githubusercontent.com/yt-dlp/yt-dlp/${versions.ytdlp}/THIRD_PARTY_LICENSES.txt`,path.join(licenses,'yt-dlp-THIRD-PARTY-LICENSES.txt'));
 fs.writeFileSync(path.join(out,'versions.json'),JSON.stringify({...versions,platform,arch,sha256:Object.fromEntries(['yt-dlp','ffmpeg','ffprobe'].map(t=>[t,crypto.createHash('sha256').update(fs.readFileSync(path.join(out,t+exe))).digest('hex')]))},null,2));
 console.log('Engines ready:',out);
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
