const {app,BrowserWindow,ipcMain,dialog,shell,clipboard,protocol,net,Menu}=require('electron');
const fs=require('node:fs');const path=require('node:path');const crypto=require('node:crypto');const {pathToFileURL}=require('node:url');const {Readable}=require('node:stream');
const {Service}=require('./service.cjs');const {capture}=require('./processes.cjs');
protocol.registerSchemesAsPrivileged([{scheme:'media',privileges:{standard:true,secure:true,stream:true,supportFetchAPI:true}}]);
let win,service,lastExport;const media=new Map();
if(process.argv.includes('--smoke-test'))app.setPath('userData',path.join(app.getPath('temp'),'video-extractor-smoke-'+crypto.randomUUID()));
const root=app.isPackaged?path.join(process.resourcesPath,'engines'):path.join(__dirname,'..','engines',`${process.platform==='darwin'?'mac':'win'}-${process.arch}`);
if(!app.requestSingleInstanceLock())app.exit(0);
app.on('second-instance',()=>{if(win){if(win.isMinimized())win.restore();win.show();win.focus();}});
const ext=process.platform==='win32'?'.exe':'';const tools={ytdlp:path.join(root,'yt-dlp'+ext),ffmpeg:path.join(root,'ffmpeg'+ext),ffprobe:path.join(root,'ffprobe'+ext),runtime:process.execPath};
async function registerMedia(file){const inspected=await service.inspect(file);const token=crypto.randomUUID();media.clear();media.set(token,inspected);return {...inspected,file:undefined,token,url:`media://local/${token}`};}
async function chooseVideo(){const result=await dialog.showOpenDialog(win,{title:'选择要截取的视频',properties:['openFile'],filters:[{name:'视频',extensions:['mp4','mov','m4v','webm','mkv','avi']}]});return result.canceled?null:registerMedia(result.filePaths[0]);}
function getJob(id){const job=service.state.jobs.find(j=>j.id===id);if(!job)throw new Error('找不到任务记录。');return job;}
app.whenReady().then(async()=>{
 protocol.handle('media',request=>{
  const token=new URL(request.url).pathname.slice(1),item=media.get(token);if(!item)return new Response('Not found',{status:404});
  const size=fs.statSync(item.file).size;const range=request.headers.get('range');let start=0,end=size-1;
  if(range){const m=/^bytes=(\d+)-(\d*)$/.exec(range);if(!m)return new Response(null,{status:416});start=Number(m[1]);end=m[2]?Math.min(Number(m[2]),size-1):size-1;if(start>end||start>=size)return new Response(null,{status:416,headers:{'Content-Range':`bytes */${size}`}});}
  const mime={'.mp4':'video/mp4','.mov':'video/quicktime','.m4v':'video/mp4','.webm':'video/webm','.mkv':'video/x-matroska'}[path.extname(item.file).toLowerCase()]||'application/octet-stream';
  const headers={'Content-Type':mime,'Content-Length':String(end-start+1),'Accept-Ranges':'bytes'};if(range)headers['Content-Range']=`bytes ${start}-${end}/${size}`;
  return new Response(Readable.toWeb(fs.createReadStream(item.file,{start,end})),{status:range?206:200,headers});
 });
 try{service=new Service({stateFile:path.join(app.getPath('userData'),'tasks.json'),defaultDestination:path.join(app.getPath('downloads'),'Video Extractor'),tools,onChange:state=>win?.webContents.send('state',state)});}
 catch(e){dialog.showErrorBox('无法读取任务历史',e.message+'\n请保留数据文件并联系维护者，程序不会覆盖它。');app.quit();return;}
 if(process.argv.includes('--smoke-test')){try{await require('./smoke.cjs').run({app,service,tools});console.log('PACKAGED_SMOKE_PASS');app.exit(0);}catch(e){console.error(e);app.exit(1);}return;}
 win=new BrowserWindow({width:1100,height:790,minWidth:850,minHeight:640,backgroundColor:'#141514',title:'Video Extractor',icon:path.join(__dirname,'..','renderer','mascot.png'),webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
 win.loadFile(path.join(__dirname,'..','renderer','index.html'));
 win.webContents.setWindowOpenHandler(()=>({action:'deny'}));win.webContents.on('will-navigate',event=>event.preventDefault());
 win.on('close',event=>{if(service.active||service.exporting){const choice=dialog.showMessageBoxSync(win,{type:'question',title:'任务还在处理中',message:'退出会取消当前下载和导出。',buttons:['继续处理','退出并取消'],defaultId:0,cancelId:0});if(choice===0)event.preventDefault();}});
 const template=[...(process.platform==='darwin'?[{role:'appMenu'}]:[]),{label:'文件',submenu:[{label:'截取本地视频…',accelerator:'CmdOrCtrl+Shift+K',click:async()=>{try{const result=await chooseVideo();if(result)win.webContents.send('local-video',result);}catch(e){dialog.showErrorBox('无法打开视频',e.message);}}},{label:'打开保存文件夹',click:()=>shell.openPath(service.state.destination)},{type:'separator'},{role:'quit'}]},{label:'编辑',submenu:[{role:'undo'},{role:'redo'},{type:'separator'},{role:'cut'},{role:'copy'},{role:'paste'},{role:'selectAll'}]},{label:'视图',submenu:[{role:'resetZoom'},{role:'zoomIn'},{role:'zoomOut'},{role:'togglefullscreen'}]},{label:'帮助',submenu:[{label:'版本与引擎',click:()=>{const versions=JSON.parse(fs.readFileSync(path.join(root,'versions.json'),'utf8'));dialog.showMessageBox(win,{title:'Video Extractor',message:`Video Extractor ${app.getVersion()}`,detail:`yt-dlp ${versions.ytdlp}\nFFmpeg ${versions.ffmpeg}\n独立测试版 · 本机处理\n第三方许可证位于应用 resources/licenses。`});}}]}];
 Menu.setApplicationMenu(Menu.buildFromTemplate(template));
});
ipcMain.handle('api',async(event,action,...args)=>{
 try{
  if(!win||event.sender!==win.webContents||!event.senderFrame.url.startsWith('file:'))throw new Error('无效请求。');
  let value;
  switch(action){
   case 'state':value=service.snapshot();break;
   case 'chooseFolder':{const result=await dialog.showOpenDialog(win,{title:'选择保存位置',properties:['openDirectory','createDirectory']});if(!result.canceled)service.setDestination(result.filePaths[0]);value=service.snapshot();break;}
   case 'paste':value=clipboard.readText();break;
   case 'add':if(!service.snapshot().engineReady)throw new Error('内置引擎缺失，请重新安装。');value=service.add(args[0]);break;
   case 'cancel':service.cancel(args[0]);break;
   case 'retry':service.retry(args[0]);break;
   case 'remove':{const job=getJob(args[0]);const deleting=args[1]===true;const result=await dialog.showMessageBox(win,{type:'warning',title:deleting?'删除记录和文件':'移除记录',message:deleting?'同时删除此任务对应的文件？':'移除这条记录并保留文件？',detail:deleting?(job.file||'没有已保存文件'):'已保存的视频仍在原目录中。',buttons:['取消',deleting?'删除记录和文件':'移除记录'],defaultId:0,cancelId:0});if(result.response===1)service.remove(args[0],deleting);break;}
   case 'open':case 'reveal':{const job=getJob(args[0]);if(!job.file||!fs.existsSync(job.file))throw new Error('文件已移动或删除，可以移除记录或重新下载。');if(action==='open'){const result=await shell.openPath(job.file);if(result)throw new Error(result);}else shell.showItemInFolder(job.file);break;}
   case 'openFolder':fs.mkdirSync(service.state.destination,{recursive:true});value=await shell.openPath(service.state.destination);break;
   case 'chooseVideo':value=await chooseVideo();break;
   case 'clipVideo':{const job=getJob(args[0]);if(!job.file||!fs.existsSync(job.file))throw new Error('文件已移动或删除，请从「截取本地视频」重新选择。');value=await registerMedia(job.file);break;}
   case 'exportClip':{const source=media.get(args[0]);if(!source)throw new Error('视频已关闭，请重新选择。');const c=require('./domain.cjs').validateClip(args[1],source.duration);const stem=path.basename(source.file,path.extname(source.file));const result=await dialog.showSaveDialog(win,{title:'导出片段',defaultPath:path.join(path.dirname(source.file),`${stem}_${c.start.toFixed(3)}-${c.end.toFixed(3)}_${c.speed}x.mp4`),filters:[{name:'MP4 视频',extensions:['mp4']}]});if(result.canceled){value=null;break;}lastExport=await service.exportClip(source,result.filePath,c,p=>win.webContents.send('export-progress',p));value=lastExport;break;}
   case 'cancelExport':service.exporting?.cancel();break;
   case 'openExport':case 'revealExport':if(!lastExport||!fs.existsSync(lastExport))throw new Error('找不到导出文件。');if(action==='openExport')await shell.openPath(lastExport);else shell.showItemInFolder(lastExport);break;
   default:throw new Error('未知操作。');
  }
  return {ok:true,value};
 }catch(error){return {ok:false,error:error.message};}
});
app.on('window-all-closed',()=>app.quit());app.on('before-quit',()=>service?.stop());
