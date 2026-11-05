import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {checkOverlaySeek} from './verify-overlay-seek.mjs';
const root=process.argv[2],report=JSON.parse(fs.readFileSync(path.join(root,'engine-validation.json'),'utf8'));
function check(key,suffix){
const file=path.join(root,'text-overlay-delay.'+suffix),state=report[key];
const timeline=checkOverlaySeek(file,process.argv[3],3.25);
const pictures=[1,3.5,6.6].map(time=>{
 const r=spawnSync('ffmpeg',['-v','error','-ss',String(time),'-i',file,'-frames:v','1','-vf','crop=iw:ih/2:0:ih/2,format=gray','-f','rawvideo','pipe:1'],{maxBuffer:4*1024*1024});
 const bright=r.stdout?.reduce((n,v)=>n+(v>160?1:0),0)??0;
 return {time,bright,passed:r.status===0&&r.stdout.length>10000&&(time===3.5?bright>60:bright<10)};
});
const sound=spawnSync('ffmpeg',['-v','error','-i',file,'-map','0:a:0','-ac','1','-ar','8000','-f','s16le','pipe:1'],{maxBuffer:2*1024*1024});
let crossings=0,energy=0,last=0,n=0;
for(let i=0;i+1<(sound.stdout?.length??0);i+=2){const v=sound.stdout.readInt16LE(i);if(n&&((v>=0)!==(last>=0)))crossings++;energy+=v*v;last=v;n++;}
const audio={frequency:crossings*8000/(2*n),rms:Math.sqrt(energy/n)/32768};
const passed=state?.passed===true&&state.cleanup===true&&timeline.passed&&pictures.every(p=>p.passed)&&sound.status===0&&n>68000&&Math.abs(audio.frequency-440)<20&&audio.rms>0.01;
const result={passed,timeline,pictures,audio,cleanup:state?.cleanup};
return {...result,kind:key,audioEncoder:state?.audioEncoder};
}
const rows=[check('textOverlay','mp4'),check('textOverlayVP8','webm')];
const result={passed:rows.every(r=>r.passed),rows};
fs.writeFileSync(path.join(root,'text-overlay-check.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
if(!result.passed)process.exitCode=1;
