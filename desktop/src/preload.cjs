const {contextBridge,ipcRenderer}=require('electron');
const invoke=(action,...args)=>ipcRenderer.invoke('api',action,...args).then(result=>{if(!result.ok)throw new Error(result.error);return result.value;});
contextBridge.exposeInMainWorld('extractor',{
 state:()=>invoke('state'),chooseFolder:()=>invoke('chooseFolder'),add:(input)=>invoke('add',input),cancel:(id)=>invoke('cancel',id),retry:(id)=>invoke('retry',id),remove:(id,files)=>invoke('remove',id,files),open:(id)=>invoke('open',id),reveal:(id)=>invoke('reveal',id),chooseVideo:()=>invoke('chooseVideo'),clipVideo:(id)=>invoke('clipVideo',id),exportClip:(token,selection)=>invoke('exportClip',token,selection),cancelExport:()=>invoke('cancelExport'),openExport:()=>invoke('openExport'),revealExport:()=>invoke('revealExport'),openFolder:()=>invoke('openFolder'),paste:()=>invoke('paste'),
 onState:callback=>{ipcRenderer.on('state',(_e,state)=>callback(state));},onExportProgress:callback=>{ipcRenderer.on('export-progress',(_e,progress)=>callback(progress));},onLocalVideo:callback=>{ipcRenderer.on('local-video',(_e,media)=>callback(media));}
});
