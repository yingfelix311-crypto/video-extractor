const {test}=require('node:test'); const assert=require('node:assert/strict');
const {parseLink,downloadArgs,clipArgs,validateClip,atempo,loadState,saveState}=require('../src/domain.cjs');
const fs=require('node:fs'); const os=require('node:os'); const path=require('node:path');
test('links extract one public URL and reject internal or ambiguous inputs',()=>{
 assert.equal(parseLink('复制 https://youtu.be/abc。'), 'https://youtu.be/abc');
 for(const value of ['hi','file:///tmp/a','http://localhost/a','http://127.1/a','http://[::1]/a','http://192.168.1.2/a','http://169.254.169.254/a','https://a.com https://b.com']) assert.throws(()=>parseLink(value));
});
test('download uses isolated config, one video, captured destination and selected quality',()=>{
 const args=downloadArgs({url:'https://youtu.be/abc',audio:false,quality:480,folder:'/tmp/space folder'}, {ffmpeg:'/tmp/tools',runtime:'/tmp/node'});
 assert.ok(args.includes('--ignore-config')); assert.ok(args.includes('--no-playlist')); assert.ok(args.includes('bv*[height<=480]+ba/b[height<=480]'));
 assert.ok(args.includes('/tmp/space folder')); assert.ok(args.includes('--no-overwrites'));
 assert.ok(downloadArgs({url:'https://example.com/v.mp4',audio:true,quality:480,folder:'/tmp/x'},{ffmpeg:'/tmp',runtime:'/tmp/node'}).includes('mp3'));
});
test('clip guards finite range, duration and speed; scales sound and video',()=>{
 for(const x of [{start:2,end:1,speed:1},{start:0,end:11,speed:1},{start:0,end:1,speed:0},{start:NaN,end:1,speed:1}]) assert.throws(()=>validateClip(x,10));
 const args=clipArgs({source:'/tmp/a.mp4',target:'/tmp/new.mp4',start:1,end:3,speed:0.25,hasAudio:true});
 assert.ok(args.includes('-n')); assert.ok(args.some(x=>x.includes('setpts=(PTS-STARTPTS)/0.25'))); assert.equal(atempo(0.25),'atempo=0.5,atempo=0.5');
 assert.ok(args.includes('0:a:0')); assert.ok(args.includes('-threads')); assert.equal(validateClip({start:1,end:3,speed:2},10).outputDuration,1);
});
test('removed records stay removed across reload and interrupted tasks never restart automatically',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'video-extractor-state-')); const file=path.join(dir,'state.json');
 try {saveState(file,{destination:dir,jobs:[{id:'a',status:'downloading'},{id:'b',status:'finished'}]}); const state=loadState(file); assert.equal(state.jobs[0].status,'interrupted'); state.jobs=[];saveState(file,state);assert.deepEqual(loadState(file).jobs,[]);} finally{fs.rmSync(dir,{recursive:true,force:true});}
});
test('download protocol explicitly emits UTF-8 on every Windows locale',()=>{
 const args=downloadArgs({url:'https://example.com/v.mp4',folder:'/tmp/stage',quality:480},{ffmpeg:'/tmp/ffmpeg',runtime:process.execPath});assert.equal(args[args.indexOf('--encoding')+1],'utf-8');
});
