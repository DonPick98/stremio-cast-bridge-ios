'use strict';
const parser=require('../vendor/stremio/subtitlesParser');
const render=require('../vendor/stremio/subtitlesRenderer');
const upperBound=require('../vendor/stremio/binarySearchUpperBound');
const createASS=require('../vendor/stremio/assRenderer');
function replace(node,nodes=[]){while(node.firstChild)node.removeChild(node.firstChild);for(const child of nodes)node.appendChild(child);}
class Presentation{
  constructor(container,overlay){this.container=container;this.overlay=overlay;this.cues=null;this.ass=null;this.format=null;this.delay=0;this.time=0;this.serial=0;this.index=null;}
  async prepare({text,format,track,fonts,updating,signal}){
    const serial=++this.serial;
    if(format==='vtt'){
      const cues=text.trim()==='WEBVTT'?{times:[]}:await parser.parse(text);
      if(signal.aborted||serial!==this.serial)return;
      if(this.ass){await this.ass.destroy();this.ass=null;}
      this.cues=cues;this.format='vtt';this.index=null;this.track=track;return;
    }
    if(updating&&this.ass&&this.format==='ass'){
      if(!signal.aborted&&serial===this.serial){this.ass.setTrack(text);this.track=track;}return;
    }
    const next=createASS({containerElement:this.container});
    const cancelled=()=>next.destroy();signal.addEventListener('abort',cancelled,{once:true});
    try{await next.load({id:track,fonts},text);
      if(signal.aborted||serial!==this.serial){await next.destroy();return;}
      const old=this.ass;this.ass=next;this.format='ass';this.cues=null;this.track=track;replace(this.overlay);
      if(old)await old.destroy();
    }catch(error){await next.destroy();throw error;}finally{signal.removeEventListener('abort',cancelled);}
  }
  setStyle(s){this.overlay.style.fontSize=`${Math.round(32*s.scale)}px`;this.overlay.style.color=s.color;
    this.overlay.style.fontFamily=s.font==='mono'?'monospace':s.font==='serif'?'serif':'Arial,sans-serif';
    this.overlay.style.bottom=`${s.position*100}%`;this.overlay.style.setProperty('--caption-background',`rgba(0,0,0,${s.background})`);
    this.overlay.style.textShadow=s.outline?'0 1px 2px black, 1px 0 2px black, -1px 0 2px black, 0 -1px 2px black':'none';
  }
  setDelay(value){this.delay=value;if(this.ass)this.ass.setDelay(value*1000);this.index=null;}
  setTime(value,force=false){this.time=value;
    if(this.ass){this.ass.setTime(value*1000,force);return;}
    if(!this.cues)return;
    const at=upperBound(this.cues.times,Math.max(0,value-this.delay)*1000);
    if(!force&&at===this.index)return;this.index=at;
    const nodes=render.render(this.cues,at);replace(this.overlay,nodes);
  }
  clear(){this.serial++;this.cues=null;this.index=null;this.format=null;replace(this.overlay);if(this.ass){this.ass.destroy();this.ass=null;}}
}
module.exports={Presentation};
