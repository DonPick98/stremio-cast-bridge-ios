const test=require('node:test'),assert=require('node:assert/strict');
const {CaptionSession}=require('../src/CaptionSession.cjs');
const {validate,captionURL}=require('../src/protocol.cjs');
const url=n=>`http://192.168.68.52:51808/captions/0123456789abcdef0123456789abcdef/${n}.vtt`;
const message=(n,extra={})=>({version:1,type:'select',epoch:'source-one',request:'request-'+n,revision:n,track:'track-'+n,format:'vtt',url:url(n),rangeStart:0,rangeEnd:90,complete:false,delay:0,...extra});
function harness(fetchText=async()=> 'WEBVTT\n\n'){
  const calls=[],replies=[];let time=0,now=10000;
  const presentation={clear:()=>calls.push(['clear']),prepare:async x=>calls.push(['prepare',x.text]),setTime:(x,f)=>calls.push(['time',x,f]),setDelay:x=>calls.push(['delay',x]),setStyle:x=>calls.push(['style',x])};
  const core=new CaptionSession({clock:()=>time,now:()=>now,fetchText,presentation,reply:x=>replies.push(x)});
  core.load({epoch:'source-one',offset:100});
  return {core,calls,replies,presentation,setTime:x=>time=x,setNow:x=>now=x};
}
test('source media clock and delay are separate; changes never have a video API',async()=>{
 const h=harness();h.setTime(7);await h.core.receive(message(1,{delay:0.5}));
 assert.ok(h.calls.some(x=>x[0]==='time'&&x[1]===107));assert.ok(h.calls.some(x=>x[0]==='delay'&&x[1]===0.5));
 await h.core.receive(message(2,{type:'delay',delay:-2}));assert.equal(h.calls.at(-2)[0],'delay');
 assert.equal(typeof h.core.loadMedia,'undefined');assert.equal(typeof h.core.seek,'undefined');
});
test('late old track cannot replace the latest track',async()=>{
 let finish;const h=harness(u=>u===url(1)?new Promise(r=>finish=r):Promise.resolve('new'));
 const old=h.core.receive(message(1));await h.core.receive(message(2));finish('old');await old;
 assert.equal(h.core.track,'track-2');assert.deepEqual(h.calls.filter(x=>x[0]==='prepare').map(x=>x[1]),['new']);
});
test('source replacement invalidates an in-flight caption',async()=>{
 let finish;const h=harness(()=>new Promise(r=>finish=r));const pending=h.core.receive(message(1));
 h.core.load({epoch:'source-two',offset:0});finish('old');await pending;
 assert.equal(h.core.track,null);assert.equal(h.calls.filter(x=>x[0]==='prepare').length,0);
});
test('off cancels a pending selection and leaves video untouched',async()=>{
 let finish;const h=harness(()=>new Promise(r=>finish=r));const pending=h.core.receive(message(1));
 await h.core.receive(message(2,{type:'clear'}));finish('old');await pending;assert.equal(h.core.track,null);
});
test('a delay change while loading survives completion',async()=>{
 let finish;const h=harness(()=>new Promise(r=>finish=r));const pending=h.core.receive(message(1));
 await h.core.receive(message(2,{type:'delay',delay:2}));finish('cue');await pending;
 assert.equal(h.core.delay,2);assert.equal(h.calls.filter(x=>x[0]==='delay').at(-1)[1],2);
});
test('style changes while loading survive completion',async()=>{
 let finish;const h=harness(()=>new Promise(r=>finish=r));const pending=h.core.receive(message(1,{style:{color:'white'}}));
 await h.core.receive(message(2,{type:'style',style:{color:'yellow',scale:1.5}}));finish('cue');await pending;
 assert.equal(h.calls.filter(x=>x[0]==='style').at(-1)[1].color,'yellow');
});
test('polling a pending immutable URL does not restart its fetch',async()=>{
 let finish,count=0;const h=harness(()=>{count++;return new Promise(r=>finish=r)});
 const pending=h.core.receive(message(1));await h.core.receive(message(2,{track:'track-1',url:url(1),delay:3}));
 finish('cue');await pending;assert.equal(count,1);assert.equal(h.core.delay,3);assert.equal(h.replies.at(-1).request,'request-2');
});
test('an unchanged document updates coverage without fetching again',async()=>{
 let count=0;const h=harness(async()=>{count++;return 'cue'});await h.core.receive(message(1));
 await h.core.receive(message(2,{track:'track-1',url:url(1),rangeEnd:180}));assert.equal(count,1);assert.equal(h.core.rangeEnd,180);
});
test('caption fetch failure reports only a caption failure',async()=>{
 const h=harness(async()=>{throw Error('network')});assert.equal(await h.core.receive(message(1)),false);
 assert.equal(h.replies.at(-1).state,'unavailable');assert.equal(h.core.epoch,'source-one');
});
test('stale revisions and epochs are ignored',async()=>{
 const h=harness();await h.core.receive(message(4));assert.equal(await h.core.receive(message(2)),false);
 assert.equal(await h.core.receive(message(5,{epoch:'other'})),false);assert.equal(h.core.track,'track-4');
});
test('coverage renewal uses receiver time and does not mistake silence for EOF',async()=>{
 const h=harness();await h.core.receive(message(1,{rangeEnd:120}));h.setTime(15);h.core.tick();
 assert.equal(h.replies.at(-1).type,'need');assert.equal(h.replies.at(-1).position,115);
 h.setNow(13000);await h.core.receive(message(2,{track:'track-1',url:url(1),rangeEnd:120,complete:true}));
 const count=h.replies.filter(x=>x.type==='need').length;h.core.tick();assert.equal(h.replies.filter(x=>x.type==='need').length,count);
});
test('only the private caption gateway is accepted; malformed input has no side effects',()=>{
 for(const u of ['https://example.com/sub.vtt','http://127.0.0.1/captions/012345678901234567890123/one','http://192.168.1.2/other','file:///tmp/sub.vtt','http://user:pass@192.168.1.2/captions/012345678901234567890123/one'])assert.equal(captionURL(u),null);
 assert.equal(validate(message(1,{delay:Infinity})),null);assert.equal(validate(message(1,{format:'javascript'})),null);
 assert.equal(validate(message(1,{revision:-1})),null);assert.ok(validate(message(1)));
});
