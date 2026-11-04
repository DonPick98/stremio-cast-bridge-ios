import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=path.resolve(process.argv[2]),report=JSON.parse(fs.readFileSync(path.join(root,'engine-validation.json')));
function exec(binary,args){const r=spawnSync(binary,args,{encoding:'utf8',maxBuffer:8e6});if(r.status!==0)throw Error(r.stderr?.slice(-1000)||'Media audit failed');return r.stdout;}
const ffmpeg=process.env.FFMPEG_PATH||'ffmpeg',ffprobe=process.env.FFPROBE_PATH||'ffprobe',cache=new Map();
function probe(file){
 if(cache.has(file))return cache.get(file);
 const r=JSON.parse(exec(ffprobe,['-v','error','-select_streams','v:0','-show_streams','-show_frames','-show_format','-show_entries','stream=width,height,r_frame_rate:frame=best_effort_timestamp_time:format=duration','-of','json',file]));
 const times=r.frames.map(x=>Number(x.best_effort_timestamp_time)).filter(Number.isFinite).sort((a,b)=>a-b);
 const steady=times.slice(2,-2);
 // Regress across all timestamps: Matroska's millisecond clock would bias a
 // median single-frame interval for fractional rates such as 24000/1001.
 const meanIndex=(steady.length-1)/2,meanTime=steady.reduce((a,b)=>a+b,0)/steady.length;
 let xy=0,xx=0;steady.forEach((t,i)=>{xy+=(i-meanIndex)*(t-meanTime);xx+=(i-meanIndex)**2;});
 const step=xy/xx,cadenceError=Math.max(...steady.slice(1).map((t,i)=>Math.abs(t-steady[i]-step)));
 const declared=Number(r.format.duration),duration=Number.isFinite(declared)?declared:times.at(-1)+step;
 const value={width:r.streams[0].width,height:r.streams[0].height,fps:1/step,cadenceError,first:times[0],duration,frames:times.length};cache.set(file,value);return value;
}
function hashes(file){const timing=process.env.CAST_FPS_MODE_LEGACY?['-vsync','0']:['-fps_mode','passthrough'];return exec(ffmpeg,['-v','error','-i',file,'-map','0:v:0',...timing,'-f','framemd5','pipe:1']).split(/\r?\n/).filter(x=>x&&!x.startsWith('#')).map(x=>x.split(',').at(-1).trim());}
function sound(file,tone){
 const r=spawnSync(ffmpeg,['-v','error','-i',file,'-map','0:a:0','-f','s16le','-ac','1','-ar','8000','pipe:1'],{maxBuffer:2e6});
 let energy=0,changes=0,last=0,n=0;
 for(let i=0;i+1<r.stdout.length;i+=2){const v=r.stdout.readInt16LE(i);if(n&&((v>=0)!==(last>=0)))changes++;energy+=v*v;last=v;n++;}
 const frequency=n?changes*8000/(2*n):0,rms=n?Math.sqrt(energy/n)/32768:0;
 return {frequency,rms,passed:r.status===0&&rms>0.01&&Math.abs(frequency-tone)<20};
}
const rows=(report.quality||[]).map(item=>{
 try {
  const original=path.join(root,item.source),output=path.join(root,item.file),input=probe(original),actual=probe(output);
  // ffprobe and ffmpeg normally tolerate a corrupt final packet. A duration
  // within tolerance is not enough: decode every packet with errors fatal.
  exec(ffmpeg,['-v','error','-xerror','-i',output,'-map','0:v:0','-map','0:a:0','-f','null','-']);
  const sameDimensions=input.width===actual.width&&input.height===actual.height;
  const sameRate=Math.abs(input.fps-actual.fps)<0.005&&actual.cadenceError<0.002;
  const durationOK=Math.abs(item.duration-actual.duration)<0.35;
  const frameCountOK=item.offset>0||actual.frames>=input.frames*0.98;
  let ssim=null;
  if(item.name==='h2642997'){
   const checked=spawnSync(ffmpeg,['-hide_banner','-i',original,'-i',output,'-filter_complex','[0:v]setpts=PTS-STARTPTS[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]ssim','-an','-f','null','-'],{encoding:'utf8',maxBuffer:2e6});
   ssim=Number(checked.stderr.match(/All:([0-9.]+)/)?.[1]||0);
   if(checked.status!==0)throw Error('Fractional-cadence picture comparison failed');
  }
  let bitExact=null,seekError=null;
  if(item.copyVideo){const source=hashes(original),copied=hashes(output);if(item.offset===0)bitExact=JSON.stringify(source)===JSON.stringify(copied);else {const index=source.indexOf(copied[0]);seekError=index<0?null:Math.abs(index/input.fps-item.offset-actual.first);}}
  const audio=sound(output,item.tone);
  const passed=item.passed&&sameDimensions&&sameRate&&durationOK&&frameCountOK&&(ssim===null||ssim>0.95)&&audio.passed&&(item.copyVideo?(item.offset===0?bitExact:seekError!==null&&seekError<0.75):true);
  return {name:item.name,input,actual,bitExact,seekError,audio,frameCountOK,ssim,passed};
 }catch(error){return {name:item.name,passed:false,error:error.message};}
});
const result={passed:rows.length===10&&rows.every(x=>x.passed),rows};
fs.writeFileSync(path.join(root,'video-quality-check.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
if(!result.passed)process.exitCode=1;


