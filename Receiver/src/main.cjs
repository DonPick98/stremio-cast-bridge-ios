'use strict';
const {NAMESPACE,MAX_TEXT_BYTES,captionURL}=require('./protocol.cjs');
const {CaptionSession}=require('./CaptionSession.cjs');
const {Presentation}=require('./Presentation.cjs');
const video=document.querySelector('video');
const context=cast.framework.CastReceiverContext.getInstance();
const manager=context.getPlayerManager();let sender=null;
const presentation=new Presentation(document.querySelector('#stage'),document.querySelector('#captions'));
async function fetchText(url,signal){
  const response=await fetch(url,{signal,cache:'no-store',credentials:'omit'});
  if(!response.ok||Number(response.headers.get('Content-Length')||0)>MAX_TEXT_BYTES)throw Error('caption_fetch');
  if(!response.body?.getReader){const text=await response.text();if(new TextEncoder().encode(text).length>MAX_TEXT_BYTES)throw Error('caption_limit');return text;}
  const reader=response.body.getReader(),chunks=[];let bytes=0;
  try{while(true){const {value,done}=await reader.read();if(done)break;bytes+=value.length;if(bytes>MAX_TEXT_BYTES)throw Error('caption_limit');chunks.push(value);}}
  finally{reader.releaseLock();}
  const data=new Uint8Array(bytes);let at=0;for(const chunk of chunks){data.set(chunk,at);at+=chunk.length;}
  return new TextDecoder('utf-8',{fatal:true}).decode(data);
}
function reply(message){if(sender)try{context.sendCustomMessage(NAMESPACE,sender,message);}catch(_){}}
const captions=new CaptionSession({clock:()=>video.currentTime,fetchText,presentation,reply});
let stateURL=null,pollTimer=null,pollAbort=null,loading=true;
function stopPolling(){clearTimeout(pollTimer);pollTimer=null;if(pollAbort)pollAbort.abort();pollAbort=null;}
async function poll(){
  if(loading||!stateURL||!captions.epoch)return;
  const epoch=captions.epoch,abort=new AbortController();pollAbort=abort;
  const timeout=setTimeout(()=>abort.abort(),5000);
  try{
    const url=new URL(stateURL);url.searchParams.set('epoch',epoch);url.searchParams.set('position',String(video.currentTime+captions.offset));url.searchParams.set('paused',video.paused?'1':'0');
    const response=await fetch(url.href,{signal:abort.signal,credentials:'omit',cache:'no-store'});
    if(response.ok){const text=await response.text();if(text.length<=16384&&epoch===captions.epoch)await captions.receive(JSON.parse(text));}
  }catch(_){}finally{clearTimeout(timeout);if(pollAbort===abort)pollAbort=null;if(epoch===captions.epoch&&!loading)pollTimer=setTimeout(poll,1000);}
}
context.addCustomMessageListener(NAMESPACE,event=>{
  sender=event.senderId;const data=event.data;
  if(data?.type==='hello'){reply({version:1,type:'hello',independent:true,formats:['vtt','ass']});return;}
  if(data?.type==='configure'){
    if(data.epoch===captions.epoch&&captionURL(data.stateURL)){stateURL=captionURL(data.stateURL);if(!loading){stopPolling();poll();}}
    return;
  }
  captions.receive(data).catch(()=>{});
});
manager.setMessageInterceptor(cast.framework.messages.MessageType.LOAD,request=>{
  loading=true;stopPolling();
  const data=request.media?.customData?.bridge;
  if(data){captions.load(data);stateURL=captionURL(data.stateURL);}else{captions.destroy();stateURL=null;}
  return request;
});
manager.addEventListener(cast.framework.events.EventType.PLAYER_LOAD_COMPLETE,()=>{loading=false;for(let i=0;i<video.textTracks.length;i++)video.textTracks[i].mode='disabled';captions.tick(true);stopPolling();poll();});
video.addEventListener('ended',()=>{loading=true;stopPolling();captions.destroy();});
video.addEventListener('seeked',()=>captions.tick(true));video.addEventListener('pause',()=>captions.tick(true));
function tick(){captions.tick();requestAnimationFrame(tick);}requestAnimationFrame(tick);
context.setLoggerLevel(cast.framework.LoggerLevel.NONE);
context.start({mediaElement:video,disableIdleTimeout:true});
