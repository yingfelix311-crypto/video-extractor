const fs=require('node:fs');const path=require('node:path');const assert=require('node:assert/strict');const {capture,start}=require('./processes.cjs');const {Service}=require('./service.cjs');
async function run({app,service,tools}){
 const dir=app.getPath('userData');const fixture=path.join(dir,'test-source.mp4');
 const versions=await capture(tools.ytdlp,['--version']);assert.ok(versions.trim());
 const runtime=await capture(tools.runtime,['--version']);assert.match(runtime,/v\d+\./);
 await capture(tools.ffmpeg,['-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=160x90:rate=30','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','3','-c:v','libx264','-threads','1','-c:a','aac','-y',fixture]);
 const original=fs.readFileSync(fixture);const media=await service.inspect(fixture);assert.ok(media.duration>=2.9);assert.ok(media.hasAudio);
 for(const speed of [.5,1,1.35,2]){
  const target=path.join(dir,`speed-${speed}.mp4`);await service.exportClip(media,target,{start:1,end:2.5,speed});const output=await service.inspect(target);assert.ok(Math.abs(output.duration-1.5/speed)<.15);assert.ok(output.hasAudio);
  await assert.rejects(service.exportClip(media,target,{start:1,end:2.5,speed}),/已存在/);
  fs.unlinkSync(target);
 }
 assert.deepEqual(fs.readFileSync(fixture),original);
 const cancelled=path.join(dir,'cancelled.mp4');const pending=service.exportClip(media,cancelled,{start:0,end:2.5,speed:.25});service.exporting.cancel();await assert.rejects(pending);assert.ok(!fs.existsSync(cancelled));assert.ok(!fs.readdirSync(dir).some(x=>x.startsWith('.video-extractor-clip')));
 service.state.jobs=[{id:'fixture',url:'https://example.com/fixture',status:'finished',file:fixture}];service.persist();service.remove('fixture',true);assert.ok(!fs.existsSync(fixture));
 const restarted=new Service({stateFile:service.stateFile,defaultDestination:dir,tools});assert.equal(restarted.state.jobs.length,0);assert.ok(!fs.existsSync(fixture));
 console.log('Verified bundled yt-dlp and JS runtime, source preserved, 4 clip rates, audio, overwrite refusal, cancellation cleanup, record/file deletion and restart.');
 fs.rmSync(dir,{recursive:true,force:true});
}
module.exports={run};
