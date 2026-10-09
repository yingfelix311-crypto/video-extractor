const {spawn}=require('node:child_process');
function start(executable,args,onLine=()=>{},options={}){
 const child=spawn(executable,args,{windowsHide:true,shell:false,detached:process.platform!=='win32',env:{...process.env,ELECTRON_RUN_AS_NODE:'1'},...options});
 let stderr='';let cancelled=false;
 for(const [stream,isError] of [[child.stdout,false],[child.stderr,true]]){
  let buffer=''; stream?.on('data',chunk=>{buffer+=chunk.toString();if(isError)stderr=(stderr+chunk.toString()).slice(-12000);let i;while((i=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,i).replace(/\r$/,'');buffer=buffer.slice(i+1);onLine(line,isError);}});
  stream?.on('end',()=>{if(buffer)onLine(buffer,isError);});
 }
 const promise=new Promise((resolve,reject)=>{
  child.once('error',reject);child.once('close',code=>{if(cancelled)reject(Object.assign(new Error('已取消任务。'),{cancelled:true}));else if(code===0)resolve();else reject(new Error(stderr.trim()||`处理引擎退出（${code}）。`));});
 });
 function cancel(){if(child.exitCode!==null)return;cancelled=true;
  if(process.platform==='win32')spawn('taskkill',['/pid',String(child.pid),'/T','/F'],{windowsHide:true,shell:false});
  else{try{process.kill(-child.pid,'SIGTERM');}catch{}const timer=setTimeout(()=>{try{process.kill(-child.pid,'SIGKILL');}catch{}},1500);timer.unref();}
 }
 return {child,promise,cancel};
}
async function capture(executable,args,timeout=20000){let output='';const proc=start(executable,args,(line,error)=>{if(!error)output+=line+'\n';});const timer=setTimeout(()=>proc.cancel(),timeout);try{await proc.promise;return output;}finally{clearTimeout(timer);}}
module.exports={start,capture};
