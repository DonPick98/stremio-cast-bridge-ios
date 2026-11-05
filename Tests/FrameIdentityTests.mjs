import {spawnSync} from 'node:child_process';
import {mkdtempSync,rmSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {identityFilter,frameIdentities} from './frame-identity-fixture.mjs';
import {checkOverlaySeek} from './verify-overlay-seek.mjs';
const root=mkdtempSync(path.join(os.tmpdir(),'cast-identity-'));
try {
function run(args){let r=spawnSync('ffmpeg',['-v','error','-y',...args],{encoding:'utf8',maxBuffer:2e6});if(r.status!==0)throw Error(r.stderr);}
run(['-f','lavfi','-i',identityFilter,'-t','6','-c:v','libx265','-pix_fmt','yuv420p10le','-preset','ultrafast','-x265-params','pools=2:frame-threads=2:log-level=error','-g','48',root+'/source.mkv']);
for(const bad of [false,true]){
 run(['-ss','3.25','-i',root+'/source.mkv',...(bad?['-vf',"select='not(eq(n,4))',setpts=N*1001/(24000*TB)"]:[]),'-an','-c:v','libx264','-preset','ultrafast','-fps_mode','passthrough',root+(bad?'/bad.mp4':'/good.mp4')]);
 const result=checkOverlaySeek(root+(bad?'/bad.mp4':'/good.mp4'),root+'/source.mkv');
 console.log(JSON.stringify({bad,...result}));assert.equal(result.passed,!bad);
}
const original=frameIdentities(root+'/source.mkv');assert(original.every((id,i)=>id===i+1));
console.log('Synthetic frame identities: exact source sequence, intact seek accepted, concealed drop rejected');

} finally {rmSync(root,{recursive:true,force:true});}
