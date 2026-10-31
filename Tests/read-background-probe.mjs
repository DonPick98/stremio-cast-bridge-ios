import fs from 'node:fs';
import http from 'node:http';
const ready=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const url=new URL(ready.url);
if(url.hostname!=='127.0.0.1'||url.protocol!=='http:')throw new Error('Unexpected test endpoint');
const began=Date.now();let bytes=0,done=false;
function finish(){if(done)return;done=true;const tmp=process.argv[3]+'.tmp';fs.writeFileSync(tmp,JSON.stringify({bytes,seconds:(Date.now()-began)/1000}));fs.renameSync(tmp,process.argv[3]);}
const request=http.get(url,response=>{
 response.on('data',chunk=>{bytes+=chunk.length;});
 response.on('end',finish);response.on('error',finish);
});
request.on('error',finish);
setTimeout(()=>{finish();request.destroy();},15000);
