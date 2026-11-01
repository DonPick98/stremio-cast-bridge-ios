import fs from 'node:fs';
import http from 'node:http';
const ready=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const url=new URL(ready.url);
if(url.hostname!=='127.0.0.1'||url.protocol!=='http:')throw new Error('Unexpected test endpoint');
const began=Date.now();let bytes=0,done=false,connected=false,status=0,errorCode='',first=0,last=0,lateBytes=0;
function finish(){if(done)return;done=true;const tmp=process.argv[3]+'.tmp';const metrics={bytes,seconds:(Date.now()-began)/1000,connected,status,errorCode,dataSpan:first?(last-first)/1000:0,lateBytes};fs.writeFileSync(tmp,JSON.stringify(metrics));fs.renameSync(tmp,process.argv[3]);console.log('Background reader finished',new Date().toISOString(),JSON.stringify(metrics));}
console.log('Background reader started',new Date().toISOString());
const request=http.get(url,response=>{
 status=response.statusCode;
 response.on('data',chunk=>{bytes+=chunk.length;const now=Date.now();if(!first)first=now;last=now;if(now-began>=50000)lateBytes+=chunk.length;response.pause();setTimeout(()=>response.resume(),Math.max(10,chunk.length*1000/131072));});
 response.on('end',finish);response.on('error',e=>{errorCode=e.code||'response';finish();});
});
request.on('socket',socket=>socket.once('connect',()=>{connected=true;}));
request.on('error',e=>{errorCode=e.code||'request';finish();});
setTimeout(()=>{finish();request.destroy();},65000);
