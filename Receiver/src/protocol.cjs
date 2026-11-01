'use strict';
const NAMESPACE='urn:x-cast:app.castbridge.captions';
const MAX_TEXT_BYTES=2*1024*1024;
function finite(value,min,max){return typeof value==='number'&&Number.isFinite(value)&&value>=min&&value<=max;}
function token(value){return typeof value==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(value);}
function captionURL(value){
  try{const u=new URL(value),p=u.hostname.split('.').map(Number);
    const privateHost=p.length===4&&p.every(x=>Number.isInteger(x)&&x>=0&&x<=255)&&(p[0]===10||p[0]===192&&p[1]===168||p[0]===172&&p[1]>=16&&p[1]<=31);
    return privateHost&&u.protocol==='http:'&&!u.username&&!u.password&&/^\/captions\/[a-zA-Z0-9_-]{20,80}\//.test(u.pathname)?u.href:null;
  }catch(_){return null;}
}
function validate(input){
  if(!input||input.version!==1||!token(input.epoch)||!token(input.request)||!Number.isSafeInteger(input.revision)||input.revision<0)return null;
  if(!['select','clear','style','delay'].includes(input.type))return null;
  const out={version:1,type:input.type,epoch:input.epoch,request:input.request,revision:input.revision};
  if(input.type==='select'){
    if(!['vtt','ass'].includes(input.format)||!token(input.track)||!finite(input.rangeStart,0,1e8)||!finite(input.rangeEnd,input.rangeStart,1e8))return null;
    const url=captionURL(input.url);if(!url)return null;
    out.track=input.track;out.format=input.format;out.url=url;out.rangeStart=input.rangeStart;out.rangeEnd=input.rangeEnd;out.complete=input.complete===true;
    out.fonts=Array.isArray(input.fonts)?input.fonts.slice(0,8).map(captionURL).filter(Boolean):[];
    if(out.fonts.some(x=>new URL(x).origin!==new URL(url).origin))return null;
  }
  if(input.type==='delay'||input.type==='select'){
    if(!finite(input.delay,-300,300))return null;out.delay=input.delay;
  }
  if(input.style)out.style=style(input.style);
  return out;
}
function style(value={}){
  return {scale:finite(value.scale,0.6,2)?value.scale:1.1,color:['white','yellow','cyan','green'].includes(value.color)?value.color:'white',
    font:['sans','serif','mono'].includes(value.font)?value.font:'sans',background:finite(value.background,0,1)?value.background:0,
    position:finite(value.position,0.05,0.5)?value.position:0.08,outline:value.outline!==false};
}
module.exports={NAMESPACE,MAX_TEXT_BYTES,validate,captionURL,style,token,finite};
