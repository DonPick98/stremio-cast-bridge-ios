'use strict';
const {validate,finite,token}=require('./protocol.cjs');
// This component has no API for loading, seeking or pausing video. Its clock is
// read-only and its only side effects are caption presentation and replies.
class CaptionSession{
  constructor({clock,fetchText,presentation,reply,now=()=>Date.now()}){
    Object.assign(this,{clock,fetchText,presentation,reply,now});this.epoch=null;this.offset=0;this.revision=-1;
    this.serial=0;this.track=null;this.delay=0;this.rangeEnd=0;this.complete=false;this.lastNeed=0;this.pending=null;
  }
  load({epoch,offset}){
    if(!token(epoch)||!finite(offset,0,1e8))return false;
    this.cancel();this.epoch=epoch;this.offset=offset;this.revision=-1;this.track=null;this.rangeEnd=0;
    this.complete=false;this.presentation.clear();return true;
  }
  cancel(){this.serial++;if(this.pending)this.pending.abort();this.pending=null;this.pendingURL=null;this.pendingTrack=null;this.desiredSelect=null;}
  async receive(raw){
    const m=validate(raw);if(!m||m.epoch!==this.epoch||m.revision<this.revision)return false;
    this.revision=m.revision;
    if(m.type==='clear'){this.cancel();this.track=null;this.presentation.clear();this.ack(m,'ready');return true;}
    if(m.type==='style'){if(m.style){this.style=m.style;this.presentation.setStyle(m.style);}this.ack(m,'ready');return true;}
    if(m.type==='delay'){this.delay=m.delay;this.presentation.setDelay(m.delay);this.tick(true);this.ack(m,'ready');return true;}
    this.delay=m.delay;if(m.style)this.style=m.style;
    if(this.track===m.track&&this.documentURL===m.url){
      this.rangeEnd=m.rangeEnd;this.complete=m.complete;
      if(this.style)this.presentation.setStyle(this.style);this.presentation.setDelay(this.delay);this.tick(true);this.ack(m,'ready');return true;
    }
    if(this.pendingURL===m.url&&this.pendingTrack===m.track){this.desiredSelect=m;return true;}
    this.cancel();
    const serial=this.serial;const abort=new AbortController();this.pending=abort;this.pendingURL=m.url;this.pendingTrack=m.track;this.desiredSelect=m;
    const updating=this.track===m.track;this.reply({version:1,type:'state',epoch:this.epoch,request:m.request,revision:m.revision,state:'pending'});
    try{
      const text=await this.fetchText(m.url,abort.signal);
      if(serial!==this.serial||this.epoch!==m.epoch)return false;
      await this.presentation.prepare({text,format:m.format,track:m.track,fonts:m.fonts,updating,signal:abort.signal});
      if(serial!==this.serial||this.epoch!==m.epoch)return false;
      const latest=this.desiredSelect||m;
      this.track=m.track;this.documentURL=m.url;this.rangeEnd=latest.rangeEnd;this.complete=latest.complete;this.pending=null;this.pendingURL=null;this.pendingTrack=null;
      if(this.style)this.presentation.setStyle(this.style);this.presentation.setDelay(this.delay);this.tick(true);this.ack(latest,'ready');return true;
    }catch(error){
      if(serial!==this.serial||this.epoch!==m.epoch||error?.name==='AbortError')return false;
      this.pending=null;this.pendingURL=null;this.pendingTrack=null;this.ack(this.desiredSelect||m,'unavailable');return false;
    }
  }
  tick(force=false){
    const relative=this.clock();if(!finite(relative,0,1e8)||!this.epoch)return;
    const absolute=relative+this.offset;this.presentation.setTime(absolute,force);
    if(this.track&&!this.complete&&absolute>=this.rangeEnd-8&&this.now()-this.lastNeed>=2000){
      this.lastNeed=this.now();this.reply({version:1,type:'need',epoch:this.epoch,track:this.track,position:absolute});
    }
  }
  ack(m,state){this.reply({version:1,type:'state',epoch:m.epoch,request:m.request,revision:m.revision,track:m.track,state});}
  destroy(){this.cancel();this.epoch=null;this.track=null;this.presentation.clear();}
}
module.exports={CaptionSession};
