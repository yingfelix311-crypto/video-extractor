const {test}=require('node:test');const assert=require('node:assert/strict');const {start}=require('../src/processes.cjs');
test('UTF-8 titles and paths survive bytes split across stdout and stderr chunks',async()=>{
 const expected='FILE:C:\\下载目录\\测试视频🎬.mp4';const script=`const b=Buffer.from(${JSON.stringify(expected+'\r\n')});process.stdout.write(b.subarray(0,9));process.stderr.write(b.subarray(0,9));setTimeout(()=>{process.stdout.write(b.subarray(9));process.stderr.write(b.subarray(9));},100);`;
 const lines=[];await start(process.execPath,['-e',script],(line,error)=>lines.push({line,error})).promise;
 assert.deepEqual(lines.filter(x=>!x.error).map(x=>x.line),[expected]);assert.deepEqual(lines.filter(x=>x.error).map(x=>x.line),[expected]);
});
