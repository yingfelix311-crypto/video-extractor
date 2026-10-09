const fs=require('node:fs'); const path=require('node:path'); const net=require('node:net');
function parseLink(text){
 if(typeof text!=='string'||text.length>16384) throw new Error('请粘贴一个有效的视频链接。');
 const links=text.match(/https?:\/\/[^\s<>"']+/gi)||[];
 if(links.length!==1) throw new Error('一次只支持一个视频链接。');
 const raw=links[0].replace(/[。，、；！？）】》]+$/u,''); const u=new URL(raw);
 const h=u.hostname.replace(/^\[|\]$/g,'').toLowerCase();
 if(u.username||u.password||!h.includes('.')||h==='localhost'||h.endsWith('.localhost')||h.endsWith('.local')||u.port&&!['80','443'].includes(u.port)) throw new Error('请选择公开的视频网址。');
 if(net.isIP(h)){
  if(h.includes(':')||/^(0\.|10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(h)) throw new Error('不支持本机或内网链接。');
 }
 return u.href;
}
function downloadArgs(job,tools){
 const args=['--ignore-config','--no-playlist','--no-overwrites','--newline','--no-colors','--no-cache-dir','--socket-timeout','20','--retries','2','--concurrent-fragments','2','--ffmpeg-location',tools.ffmpeg,'--js-runtimes',`node:${tools.runtime}`,'--paths',job.folder,'--output','%(title).180B [%(id)s].%(ext)s','--progress-template','download:PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s','--print','before_dl:TITLE:%(title)s','--print','after_move:FILE:%(filepath)s'];
 if(job.audio) args.push('-x','--audio-format','mp3','--audio-quality','0');
 else{
  const direct=/\.(mp4|webm|mov|m4v)(\?|$)/i.test(job.url);
  const q=[480,720,1080,2160].includes(Number(job.quality))?Number(job.quality):1080;
  args.push('-f',direct?'best':`bv*[height<=${q}]+ba/b[height<=${q}]`,'--merge-output-format','mp4','--remux-video','mp4');
 }
 return [...args,'--',parseLink(job.url)];
}
function validateClip(value,duration){
 const {start,end,speed}=value;
 if(![start,end,speed,duration].every(Number.isFinite)||start<0||end<=start||end>duration+0.00001||speed<0.25||speed>2) throw new Error('请检查起止时间和倍速：片段不能超出视频时长，倍速为 0.25–2×。');
 return {...value,outputDuration:(end-start)/speed};
}
function atempo(speed){const stages=[]; while(speed<0.5){stages.push('atempo=0.5');speed/=0.5;} stages.push(`atempo=${speed}`);return stages.join(',');}
function clipArgs(c){
 const args=['-hide_banner','-loglevel','error','-nostdin','-n','-ss',String(c.start),'-t',String(c.end-c.start),'-i',c.source,'-map','0:v:0','-vf',`setpts=(PTS-STARTPTS)/${c.speed}`,'-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p','-threads','2','-filter_threads','1'];
 if(c.hasAudio) args.push('-map','0:a:0','-af',`asetpts=PTS-STARTPTS,${atempo(c.speed)}`,'-c:a','aac','-b:a','192k');
 else args.push('-an');
 return [...args,'-movflags','+faststart','-progress','pipe:1',c.target];
}
function loadState(file){
 if(!fs.existsSync(file))return {version:1,destination:null,jobs:[]};
 const data=JSON.parse(fs.readFileSync(file,'utf8'));
 if(!Array.isArray(data.jobs))throw new Error('任务历史格式无效。');
 return {...data,jobs:data.jobs.map(j=>['queued','downloading','processing'].includes(j.status)?{...j,status:'interrupted',error:'上次任务因应用退出而中断，可点击重试。'}:j)};
}
function saveState(file,data){
 fs.mkdirSync(path.dirname(file),{recursive:true}); const temp=file+'.tmp';
 const fd=fs.openSync(temp,'w',0o600);try{fs.writeFileSync(fd,JSON.stringify(data,null,2));fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
 fs.renameSync(temp,file);
}
module.exports={parseLink,downloadArgs,clipArgs,validateClip,atempo,loadState,saveState};
