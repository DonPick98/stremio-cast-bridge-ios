import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {frameIdentities} from './frame-identity-fixture.mjs';

const root=process.argv[2];
const report=JSON.parse(fs.readFileSync(path.join(root,'decoder-trial.json'),'utf8'));
const trials=report.trials;
const baseline=trials.find(t=>t.name==='baseline');
if(baseline?.status!=='success')throw new Error('Baseline decoder trial did not complete');
const source=frameIdentities(process.argv[3]);
function verify(name){
 const file=path.join(root,`decoder-trial-${name}.mkv`);
 const p=spawnSync('ffprobe',['-v','error','-select_streams','v:0','-show_frames','-show_entries','frame=best_effort_timestamp_time','-of','json',file],{encoding:'utf8',maxBuffer:2e6});
 if(p.status!==0)throw new Error('Cannot decode trial '+name);
 const times=JSON.parse(p.stdout).frames.map(f=>Number(f.best_effort_timestamp_time));
 const ids=frameIdentities(file);
 const wanted=Math.round(report.seconds*24000/1001);
 if(times.length!==wanted||ids.length!==wanted||ids.some((id,i)=>id!==source[i]))throw new Error('Frame identity/count mismatch in '+name);
 const gap=Math.max(...times.slice(1).map((t,i)=>t-times[i]));
 if(!Number.isFinite(gap)||gap>1.5/(24000/1001))throw new Error('Frame timing gap in '+name);
 return file;
}
const a=verify('baseline');
const accelerated=trials.find(t=>t.name==='videotoolbox');
if(accelerated?.status!=='success'){
 console.log('VideoToolbox decoder unavailable in simulator; production path unchanged. Baseline identity/timing passed.');
}else{
 const b=verify('videotoolbox');
 const r=spawnSync('ffmpeg',['-v','info','-i',a,'-i',b,'-lavfi','[0:v]setpts=PTS-STARTPTS[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]ssim','-an','-f','null','-'],{encoding:'utf8',maxBuffer:2e6});
 const score=Number([...r.stderr.matchAll(/All:([0-9.]+)/g)].at(-1)?.[1]);
 if(r.status!==0||!Number.isFinite(score)||score<0.98)throw new Error('Decoder trial quality mismatch');
 console.log(JSON.stringify({identityAndTiming:true,ssim:score,trialMetrics:trials,phoneEnergyVerified:false}));
}
