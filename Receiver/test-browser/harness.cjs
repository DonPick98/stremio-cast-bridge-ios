const {Presentation}=require('../src/Presentation.cjs');
const {CaptionSession}=require('../src/CaptionSession.cjs');
const video=document.querySelector('video'),overlay=document.querySelector('#captions');
const presentation=new Presentation(document.querySelector('#stage'),overlay);
const messages=[],docs=new Map();let revision=0,loads=0;
video.addEventListener('loadstart',()=>loads++);
const session=new CaptionSession({clock:()=>video.currentTime,fetchText:async(url,signal)=>{const value=docs.get(url);if(value===undefined)throw Error('missing');return value;},presentation,reply:m=>messages.push(m)});
session.load({epoch:'browser-test',offset:0});
function url(){return 'http://192.168.68.56:8080/captions/01234567890123456789012345678901/'+revision+'.vtt';}
window.harness={video,session,presentation,messages,loads:()=>loads,
 async select(text,format='vtt',track='test',delay=0){revision++;const path=url();docs.set(path,text);return session.receive({version:1,type:'select',epoch:'browser-test',revision,request:'test-'+revision,track,format,url:path,rangeStart:0,rangeEnd:200,complete:true,delay,fonts:[],style:{scale:1,color:'yellow',outline:true}});},
 async clear(){return session.receive({version:1,type:'clear',epoch:'browser-test',revision:++revision,request:'clear-'+revision});},
 async delay(value){return session.receive({version:1,type:'delay',epoch:'browser-test',revision:++revision,request:'delay-'+revision,delay:value});},
 async seek(value){video.currentTime=value;await new Promise(r=>video.addEventListener('seeked',r,{once:true}));session.tick(true);},
 text:()=>overlay.textContent,
};
video.src='video.mp4';video.muted=true;video.controls=true;
document.querySelector('#start').onclick=()=>video.play();
function tick(){session.tick();requestAnimationFrame(tick)}requestAnimationFrame(tick);
