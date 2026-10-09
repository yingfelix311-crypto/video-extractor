const fs=require('node:fs');const path=require('node:path');const crypto=require('node:crypto');
const {parseLink,downloadArgs,clipArgs,validateClip,loadState,saveState}=require('./domain.cjs');const {start,capture}=require('./processes.cjs');
function within(file,base){const relative=path.relative(path.resolve(base),path.resolve(file));return relative!==''&&!relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative);}
function publishFile(source,destination){
 if(!fs.existsSync(source))throw new Error('处理引擎未生成文件。');
 // Hard-link creation is atomic and cannot replace an existing file. Temp/output are on the same volume.
 const ext=path.extname(source),stem=path.basename(source,ext);let target;
 for(let i=0;i<10000;i++){
  target=path.join(destination,stem+(i?` (${i})`:'')+ext);
  try{fs.linkSync(source,target);fs.unlinkSync(source);return target;}catch(e){if(e.code==='EEXIST')continue;throw e;}
 }
 throw new Error('同名文件太多，请选择其他目录。');
}
class Service{
 constructor({stateFile,defaultDestination,tools,onChange=()=>{}}){
  this.stateFile=stateFile;this.tools=tools;this.onChange=onChange;this.active=null;this.exporting=null;this.lastSave=0;this.stopping=false;
  this.state=loadState(stateFile);this.state.destination??=defaultDestination;this.persist();
 }
 snapshot(){return {...this.state,engineReady:fs.existsSync(this.tools.ytdlp)&&fs.existsSync(this.tools.ffmpeg)&&fs.existsSync(this.tools.ffprobe),exporting:!!this.exporting,jobs:this.state.jobs.map(j=>({...j,fileExists:!!j.file&&fs.existsSync(j.file)}))};}
 persist(){saveState(this.stateFile,this.state);this.lastSave=Date.now();this.onChange(this.snapshot());}
 progress(){if(Date.now()-this.lastSave>500)this.persist();else this.onChange(this.snapshot());}
 setDestination(directory){if(typeof directory!=='string'||!fs.statSync(directory).isDirectory())throw new Error('保存文件夹不存在。');this.state.destination=directory;this.persist();}
 add(input){
  const url=parseLink(input.url);if(this.state.jobs.some(j=>j.url===url&&['queued','downloading','processing'].includes(j.status)))throw new Error('此链接已有任务。');
  if(this.state.jobs.length>=1000)throw new Error('历史记录已达 1000 条，请清理后再添加。');
  const id=crypto.randomUUID();const destination=this.state.destination;fs.mkdirSync(destination,{recursive:true});
  const job={id,url,title:'正在读取视频信息…',audio:input.audio===true,quality:Number(input.quality)||1080,status:'queued',percent:0,destination,folder:path.join(destination,`.video-extractor-${id}`),createdAt:new Date().toISOString()};
  this.state.jobs.unshift(job);this.persist();this.pump();return job.id;
 }
 async pump(){
  if(this.stopping||this.active)return;const job=this.state.jobs.slice().reverse().find(j=>j.status==='queued');if(!job)return;
  this.active={id:job.id,proc:null};job.status='downloading';job.error=null;this.persist();let staged;
  try{
   fs.mkdirSync(job.folder,{recursive:true});
   const proc=start(this.tools.ytdlp,downloadArgs(job,this.tools),(line)=>{
    if(line.startsWith('TITLE:'))job.title=line.slice(6);
    if(line.startsWith('FILE:'))staged=line.slice(5).trim();
    if(line.startsWith('PROGRESS:')){const values=line.slice(9).split('|');job.percent=Math.min(100,Math.max(0,parseFloat(values[0])||0));job.speed=values[1];job.eta=values[2];if(job.percent>=100)job.status='processing';this.progress();}
   });this.active.proc=proc;await proc.promise;
   if(!staged||!within(staged,job.folder))throw new Error('下载文件路径无效，请重试。');
   job.file=publishFile(staged,job.destination);job.title=job.title==='正在读取视频信息…'?path.basename(job.file):job.title;job.status='finished';job.percent=100;
  }catch(error){job.status=error.cancelled?'cancelled':'error';job.error=error.message;}
  finally{try{fs.rmSync(job.folder,{recursive:true,force:true});}catch{}this.active=null;this.persist();this.pump();}
 }
 cancel(id){const job=this.state.jobs.find(j=>j.id===id);if(!job)return;if(this.active?.id===id)this.active.proc?.cancel();else if(job.status==='queued'){job.status='cancelled';this.persist();}}
 retry(id){const job=this.state.jobs.find(j=>j.id===id);if(!job||!['error','cancelled','interrupted'].includes(job.status))throw new Error('该任务不需要重试。');job.destination=this.state.destination;job.folder=path.join(job.destination,`.video-extractor-${job.id}`);job.status='queued';job.error=null;job.percent=0;this.persist();this.pump();}
 remove(id,deleteFile=false){const job=this.state.jobs.find(j=>j.id===id);if(!job)throw new Error('找不到记录。');if(['queued','downloading','processing'].includes(job.status))throw new Error('请先取消正在处理的任务。');
  if(deleteFile&&job.file){try{fs.unlinkSync(job.file);}catch(e){if(e.code!=='ENOENT')throw new Error('删除文件失败：'+e.message);}}
  // Clear state only after file removal succeeds. No scans/import on startup.
  this.state.jobs=this.state.jobs.filter(j=>j.id!==id);this.persist();
 }
 async inspect(file){
  const info=JSON.parse(await capture(this.tools.ffprobe,['-v','error','-show_format','-show_streams','-of','json','--',file]));
  const duration=Number(info.format?.duration);if(!Number.isFinite(duration)||duration<=0||!info.streams?.some(s=>s.codec_type==='video'))throw new Error('此文件没有可读取的视频轨道。');
  return {file,name:path.basename(file),duration,hasAudio:info.streams.some(s=>s.codec_type==='audio')};
 }
 async exportClip(media,target,selection,onProgress=()=>{}){
  if(this.exporting)throw new Error('已有片段正在导出，请等待完成。');
  const clip=validateClip(selection,media.duration);if(path.resolve(target)===path.resolve(media.file)||fs.existsSync(target))throw new Error('文件已存在，请更换文件名。原视频不会被覆盖。');
  const directory=path.dirname(target);const temporary=path.join(directory,`.video-extractor-clip-${crypto.randomUUID()}.mp4`);
  const proc=start(this.tools.ffmpeg,clipArgs({...clip,source:media.file,target:temporary,hasAudio:media.hasAudio}),(line)=>{if(line.startsWith('out_time_us='))onProgress(Math.min(1,Number(line.slice(12))/1e6/clip.outputDuration));});
  this.exporting=proc;this.onChange(this.snapshot());
  try{await proc.promise;fs.linkSync(temporary,target);fs.unlinkSync(temporary);return target;}
  finally{try{fs.rmSync(temporary,{force:true});}catch{}this.exporting=null;this.onChange(this.snapshot());}
 }
 stop(){this.stopping=true;this.active?.proc?.cancel();this.exporting?.cancel();}
}
module.exports={Service,publishFile,within};
