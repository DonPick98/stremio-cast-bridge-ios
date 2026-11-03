import {writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';

// Synthetic Blu-ray PGS display sets, following FFmpeg's pgssubdec segment
// parser. A white rectangle on a transparent canvas makes timing testable
// without copyrighted subtitles or a platform-specific font renderer.
const u16=n=>{const b=Buffer.alloc(2);b.writeUInt16BE(n);return b;};
const u24=n=>Buffer.from([n>>16,(n>>8)&255,n&255]);
const cat=(...a)=>Buffer.concat(a.map(x=>Buffer.from(x)));
function segment(time,type,data){
  const h=Buffer.alloc(13);h.write('PG');h.writeUInt32BE(Math.round(time*90000),2);
  h.writeUInt32BE(0,6);h[10]=type;h.writeUInt16BE(data.length,11);
  return cat(h,data);
}
export function makePGS(file,start=6,end=9){
  const width=640,height=360,boxWidth=120,boxHeight=24;
  const presentation=(number,visible)=>cat(u16(width),u16(height),[0x10],u16(number),[visible?0x80:0,0,0,visible?1:0],visible?cat(u16(0),[0,0],u16(260),u16(290)):[]);
  const window=cat([1,0],u16(0),u16(0),u16(width),u16(height));
  const palette=Buffer.from([0,0,0,16,128,128,0,1,235,128,128,255]);
  const rle=cat(...Array.from({length:boxHeight},()=>cat(Buffer.alloc(boxWidth,1),[0,0])));
  const object=cat(u16(0),[0,0xc0],u24(rle.length+4),u16(boxWidth),u16(boxHeight),rle);
  writeFileSync(file,cat(segment(0,0x16,presentation(0,false)),segment(0,0x80,[]),segment(start,0x16,presentation(1,true)),segment(start,0x17,window),segment(start,0x14,palette),segment(start,0x15,object),segment(start,0x80,[]),segment(end,0x16,presentation(2,false)),segment(end,0x80,[])));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)makePGS(process.argv[2]);
