import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {identityFilter} from './frame-identity-fixture.mjs';
const root=fs.mkdtempSync(path.join(os.tmpdir(),'cast-decoder-trial-'));
function encode(args){const r=spawnSync('ffmpeg',['-v','error','-y',...args],{encoding:'utf8'});if(r.status!==0)throw new Error(r.stderr);}
const source=path.join(root,'source.mkv');
try{
 encode(['-f','lavfi','-i',identityFilter,'-t','4','-an','-c:v','libx264','-preset','ultrafast','-threads','2',source]);
 const base=path.join(root,'decoder-trial-baseline.mkv'),accelerated=path.join(root,'decoder-trial-videotoolbox.mkv');
 fs.copyFileSync(source,base);fs.copyFileSync(base,accelerated);
 const report={seconds:4,trials:[{name:'baseline',status:'success'},{name:'videotoolbox',status:'success'}]};
 const check=()=>spawnSync(process.execPath,['Tests/verify-decoder-trial.mjs',root,source],{encoding:'utf8'});
 fs.writeFileSync(path.join(root,'decoder-trial.json'),JSON.stringify(report));
 if(check().status!==0)throw new Error('Valid identical trial was rejected');
 encode(['-i',base,'-vf','select=not(eq(n\\,17)),setpts=N/(24000/1001*TB)','-fps_mode','passthrough','-an','-c:v','libx264','-preset','ultrafast','-threads','2',accelerated]);
 if(check().status===0)throw new Error('A trial missing one frame was accepted');
 report.trials[1].status='unavailable';fs.writeFileSync(path.join(root,'decoder-trial.json'),JSON.stringify(report));
 if(check().status!==0)throw new Error('Unsupported experimental decoder must leave baseline valid');
 console.log('Decoder trial gate: valid media, dropped frame and unavailable backend covered.');
}finally{fs.rmSync(root,{recursive:true,force:true});}
