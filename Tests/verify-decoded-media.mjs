import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root=path.resolve(process.argv[2]);
const ffmpeg=process.env.FFMPEG_PATH||'ffmpeg';
const report=JSON.parse(fs.readFileSync(path.join(root,'engine-validation.json'),'utf8'));
function run(args){const p=spawnSync(ffmpeg,['-v','error',...args],{maxBuffer:4*1024*1024});if(p.error)throw p.error;return p;}
function sound(file){
 const p=run(['-i',file,'-map','0:a:0','-f','s16le','-ac','1','-ar','8000','pipe:1']);
 let energy=0,changes=0,last=0,n=0;
 for(let i=0;i+1<p.stdout.length;i+=2){const v=p.stdout.readInt16LE(i);if(n&&((v>=0)!==(last>=0)))changes++;energy+=v*v;last=v;n++;}
 return {ok:p.status===0,samples:n,frequency:n?changes*8000/(2*n):0,rms:n?Math.sqrt(energy/n)/32768:0};
}
const reference=sound(process.argv[3]);
const files=report.matrix.map(r=>({name:r.name,file:`matrix-${r.name}.${r.videoMode==='softwareVP8'?'webm':'mp4'}`,frames:144,samples:38000,tone:r.name==='multiple_audio'?440:880}));
report.gateway.forEach((r,i)=>files.push({name:`gateway-${i}`,file:`gateway-${i}.${r.mode==='softwareVP8'?'webm':'mp4'}`,frames:i===3?144:96,samples:i===3?38000:28000,tone:i===3?880:reference.frequency}));
const rows=files.map(item=>{
 const file=path.join(root,item.file),audio=sound(file);
 const video=run(['-i',file,'-map','0:v:0','-vsync','0','-progress','pipe:1','-f','null','-']);
 const frames=Number([...video.stdout.toString().matchAll(/^frame=(\d+)/gm)].at(-1)?.[1]||0);
 return {name:item.name,frames,expectedFrames:item.frames,...audio,passed:audio.ok&&video.status===0&&audio.samples>=item.samples&&audio.rms>0.01&&Math.abs(audio.frequency-item.tone)<20&&frames>=item.frames*0.9};
});
const result={passed:report.passed&&rows.length===30&&rows.every(r=>r.passed),rows};
fs.writeFileSync(path.join(root,'decoded-output-check.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
if(!result.passed)process.exitCode=1;
