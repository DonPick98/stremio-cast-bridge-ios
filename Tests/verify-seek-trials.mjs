import fs from 'node:fs';
import path from 'node:path';
import {checkOverlaySeek} from './verify-overlay-seek.mjs';
const root=process.argv[2],report=JSON.parse(fs.readFileSync(path.join(root,'seek-trials.json'),'utf8'));
for(const row of report.trials){
 try {row.frames=row.captured ? checkOverlaySeek(path.join(root,`seek-trial-${row.name}.mp4`),path.join(root,'source.mkv'),report.position):{passed:false};}
 catch {row.frames={passed:false,error:'decode'};}
}
fs.writeFileSync(path.join(root,'seek-trial-checks.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report));
// This diagnostic job is not the production acceptance suite. At least one
// non-baseline candidate must satisfy the unchanged strict frame gate.
if(!report.trials.some(r=>r.name!=='baseline'&&r.frames.passed))process.exitCode=1;
