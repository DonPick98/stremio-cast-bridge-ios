import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fs.mkdtempSync(path.join(os.tmpdir(),'cast-cadence-'));
const audit=fileURLToPath(new URL('./verify-video-quality.mjs',import.meta.url));
function ffmpeg(args){const r=spawnSync('ffmpeg',['-v','error','-y',...args],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);}
try {
 const source=path.join(root,'source.mkv');
 ffmpeg(['-f','lavfi','-i','testsrc2=size=320x180:rate=30000/1001:duration=4.004','-f','lavfi','-i','sine=frequency=880:sample_rate=48000:duration=4.004','-c:v','libx264','-pix_fmt','yuv420p','-crf','12','-c:a','aac',source]);
 ffmpeg(['-i',source,'-fps_mode','passthrough','-c:v','libx264','-crf','12','-c:a','aac',path.join(root,'good.mp4')]);
 ffmpeg(['-i',source,'-vf','select=not(eq(mod(n\\,4)\\,0))','-fps_mode','vfr','-c:v','libx264','-crf','12','-c:a','aac',path.join(root,'dropped.mp4')]);
 for(const [file,expected] of [['good.mp4',0],['dropped.mp4',1]]){
  const quality=Array.from({length:10},(_,i)=>({name:i===0?'h2642997':`control${i}`,source:'source.mkv',file,offset:0,copyVideo:false,tone:880,duration:4.004,passed:true}));
  fs.writeFileSync(path.join(root,'engine-validation.json'),JSON.stringify({quality}));
  const r=spawnSync(process.execPath,[audit,root],{encoding:'utf8'});
  assert.equal(r.status,expected,r.stderr+'\n'+r.stdout);
  const result=JSON.parse(fs.readFileSync(path.join(root,'video-quality-check.json')));
  assert.equal(result.passed,expected===0);
  console.log(JSON.stringify({fixture:file,passed:result.passed,frames:result.rows[0].actual.frames,ssim:result.rows[0].ssim}));
 }
 console.log('Quality audit self-test: equivalent frames across container clocks accepted; removed frames rejected');
}finally{fs.rmSync(root,{recursive:true,force:true});}
