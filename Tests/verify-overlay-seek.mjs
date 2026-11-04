import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

function probe(file) {
 const p=spawnSync(process.env.FFPROBE_PATH||'ffprobe',['-v','error','-select_streams','v:0','-show_frames','-show_streams','-show_format','-show_entries','frame=best_effort_timestamp_time:stream=avg_frame_rate:format=duration','-of','json',file],{encoding:'utf8',maxBuffer:4*1024*1024});
 if(p.status!==0)throw new Error(`Cannot probe synthetic seek media: ${p.stderr}`);
 return JSON.parse(p.stdout);
}

// Count alone misses a hole concealed by duplicated frames. Check the complete
// decoded timeline, including its first picture and every inter-frame gap.
export function checkOverlaySeek(file,reference,position=3.25) {
 const source=probe(reference),output=probe(file);
 const [num,den]=source.streams[0].avg_frame_rate.split('/').map(Number);
 const fps=num/den,duration=Number(source.format.duration)-position;
 const frames=(output.frames||[]).map(f=>Number(f.best_effort_timestamp_time));
 const gaps=frames.slice(1).map((t,i)=>t-frames[i]);
 const expectedFrames=Math.round(duration*fps);
 const maxGap=gaps.length?Math.max(...gaps):Infinity;
 const first=frames[0]??Infinity,last=frames.at(-1)??-Infinity;
 const passed=Number.isFinite(fps)&&fps>0&&duration>0&&
  frames.length>=expectedFrames*0.98&&frames.every(Number.isFinite)&&
  first>=-1/fps&&first<=2/fps&&gaps.every(g=>g>0)&&
  maxGap<=2/fps&&last>=duration-3/fps&&last<=duration+0.3;
 return {passed,frames:frames.length,expectedFrames,fps,first,last,maxGap};
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 const root=path.resolve(process.argv[2]);
 const report=JSON.parse(fs.readFileSync(path.join(root,'engine-validation.json'),'utf8'));
 const row=report.matrix.find(r=>r.name==='caption_hevc_eac3_seek');
 if(!row?.passed)throw new Error('Native HEVC/EAC3 overlay seek did not complete');
 const result=checkOverlaySeek(path.join(root,`matrix-${row.name}.${row.videoMode==='softwareVP8'?'webm':'mp4'}`),process.argv[3]);
 fs.writeFileSync(path.join(root,'overlay-seek-check.json'),JSON.stringify(result,null,2));
 console.log(JSON.stringify(result));
 if(!result.passed)process.exitCode=1;
}
