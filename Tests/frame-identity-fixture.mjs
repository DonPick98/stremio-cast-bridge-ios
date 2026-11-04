import {spawnSync} from 'node:child_process';

// Every picture carries its 1-based number in twelve large luma bars. Keep the
// bottom half black so independent caption-pixel assertions still apply.
export const identityFilter="nullsrc=size=120x60:rate=24000/1001,geq=lum='if(lt(Y,30),16+mod(floor((N+1)/pow(2,floor(X/10))),2)*210,16)':cb=128:cr=128,scale=1920:1080:flags=neighbor";
export function frameIdentities(file) {
 const result=spawnSync(process.env.CAST_FIXTURE_FFMPEG||'ffmpeg',['-v','error','-i',file,'-map','0:v:0','-vf','crop=iw:ih/2:0:0,scale=120:30:flags=area,format=gray','-fps_mode','passthrough','-f','rawvideo','pipe:1'],{maxBuffer:8*1024*1024});
 if(result.status!==0)throw new Error('Cannot decode synthetic frame identities: '+result.stderr?.toString().slice(-500));
 const stride=120*30,bytes=result.stdout;
 if(bytes.length%stride)throw new Error('Incomplete synthetic identity picture');
 const ids=[];
 for(let p=0;p<bytes.length;p+=stride) {
  let id=0;
  for(let bit=0;bit<12;bit++)if(bytes[p+15*120+bit*10+5]>128)id|=1<<bit;
  ids.push(id);
 }
 return ids;
}
