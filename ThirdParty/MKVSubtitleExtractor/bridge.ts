// Cast Bridge adapter for mkv-subtitle-extractor, MIT (Shy), pinned in UPSTREAM.md.
// Only complete, frame-count-verified indexed ASS/SSA tracks are accepted.
import {RangeReader} from './src/io/range-reader.js';
import {parseSegment} from './src/mkv/segment.js';
import {parseTracks} from './src/mkv/tracks.js';
import {parseCues} from './src/mkv/cues.js';
import {readTargetedBlocks} from './src/mkv/clusters.js';
import {assembleAss} from './src/subtitle/ass.js';
import {parseElementHeader,iterateChildren,readUint,readUtf8} from './src/ebml/parser.js';

export async function indexedASS(url:string,ordinal:number,language:string) {
  const reader=new RangeReader(url);
  await reader.init();
  const seg=await parseSegment(reader);
  const seek=(id:number)=>{const e=seg.seekEntries.find(x=>x.id===id);if(!e)throw Error('index');return e.position+seg.segmentDataOffset;};
  async function element(at:number) {
    const h=parseElementHeader(await reader.read(at,12),0);
    if(h.unknownSize||h.dataSize<0||h.dataSize>524288)throw Error('limit');
    const data=await reader.read(at,h.dataOffset+h.dataSize);
    if(data.length!==h.dataOffset+h.dataSize)throw Error('truncated');
    return {data,h};
  }
  const all=await parseTracks(reader,seg.segmentDataOffset,seek(0x1654AE6B)-seg.segmentDataOffset);
  const chosen=all[ordinal];
  if(!chosen||!['S_TEXT/ASS','S_TEXT/SSA'].includes(chosen.codecId))throw Error('codec');
  const lang=(s:string)=>({eng:'en',ita:'it'}[s.toLowerCase()]||s.toLowerCase());
  if(language!=='und'&&chosen.language&&lang(chosen.language)!==lang(language))throw Error('track');
  const {data:tracks,h:th}=await element(seek(0x1654AE6B));
  const hex=(data:Uint8Array,o:number,n:number)=>Array.from(data.subarray(o,o+n)).map(x=>x.toString(16).padStart(2,'0')).join('').replace(/^0+/,'');
  let uid='';
  for(const entry of iterateChildren(tracks,th.dataOffset,th.dataSize)) {
    if(entry.id!==0xAE)continue;
    const children=Array.from(iterateChildren(tracks,entry.dataOffset,entry.dataSize));
    const number=children.find(x=>x.id===0xD7);
    if(!number||readUint(tracks,number.dataOffset,number.dataSize)!==chosen.trackNumber)continue;
    if(children.some(x=>x.id===0x6D80))throw Error('encoding');
    const id=children.find(x=>x.id===0x73C5);if(id)uid=hex(tracks,id.dataOffset,id.dataSize);
  }
  if(!uid)throw Error('uid');
  const {data:tags,h:tagHeader}=await element(seek(0x1254C367));
  let expected=0;
  for(const tag of iterateChildren(tags,tagHeader.dataOffset,tagHeader.dataSize)) {
    if(tag.id!==0x7373)continue;
    const children=Array.from(iterateChildren(tags,tag.dataOffset,tag.dataSize));
    const targets=children.find(x=>x.id===0x63C0);if(!targets)continue;
    const ids=Array.from(iterateChildren(tags,targets.dataOffset,targets.dataSize)).filter(x=>x.id===0x63C5);
    if(!ids.some(x=>hex(tags,x.dataOffset,x.dataSize)===uid))continue;
    for(const simple of children.filter(x=>x.id===0x67C8)) {
      const fields=Array.from(iterateChildren(tags,simple.dataOffset,simple.dataSize));
      const name=fields.find(x=>x.id===0x45A3),value=fields.find(x=>x.id===0x4487);
      if(name&&value&&readUtf8(tags,name.dataOffset,name.dataSize)==='NUMBER_OF_FRAMES') {
        const v=readUtf8(tags,value.dataOffset,value.dataSize);
        if(!/^\d{1,5}$/.test(v))throw Error('count');expected=Number(v);
      }
    }
  }
  if(expected<1||expected>12000)throw Error('count');
  // Cap index size before upstream parse allocates entries.
  await element(seek(0x1C53BB6B));
  const cues=(await parseCues(reader,seg.segmentDataOffset,seek(0x1C53BB6B)-seg.segmentDataOffset)).filter(c=>c.track===chosen.trackNumber);
  if(cues.length!==expected||cues.some(c=>c.relativePosition===undefined)||new Set(cues.map(c=>c.clusterPosition+':'+c.relativePosition)).size!==expected)throw Error('coverage');
  // Upstream targeted reads assume equal cluster header lengths. Verify it.
  let headerSize=0,next=0;
  const positions=Array.from(new Set(cues.map(c=>c.clusterPosition)));
  async function verifyHeaders(){while(next<positions.length){
    const pos=positions[next++];
    const h=parseElementHeader(await reader.read(seg.segmentDataOffset+pos,12),0);
    if(h.id!==0x1F43B675||h.unknownSize)throw Error('cluster');
    if(headerSize&&headerSize!==h.dataOffset)throw Error('cluster');headerSize=h.dataOffset;
  }}
  await Promise.all(Array.from({length:Math.min(4,positions.length)},verifyHeaders));
  const blocks=await readTargetedBlocks(reader,seg.segmentDataOffset,cues,new Set([chosen.trackNumber]),seg.info.timestampScale,4);
  if(blocks.length!==expected||blocks.some(b=>!Number.isFinite(b.timestampMs)||b.timestampMs<0))throw Error('coverage');
  const output=assembleAss(chosen,blocks);
  if(output.length>1048576)throw Error('limit');
  return {text:new TextDecoder().decode(output),frames:expected,bytes:reader.bytesDownloaded,requests:reader.requestCount};
}
