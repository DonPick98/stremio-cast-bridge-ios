import {writeFileSync} from 'node:fs';
const cat=(...a)=>Buffer.concat(a.map(x=>Buffer.from(x)));
const id=n=>{let h=n.toString(16);if(h.length%2)h='0'+h;return Buffer.from(h,'hex');};
const size=n=>n<127?Buffer.from([0x80|n]):n<16383?Buffer.from([0x40|(n>>8),n&255]):Buffer.from([0x20|(n>>16),(n>>8)&255,n&255]);
const el=(i,v)=>cat(id(i),size(v.length),v),u=(i,n)=>el(i,id(n)),str=(i,s)=>el(i,Buffer.from(s));
const info=el(0x1549a966,u(0x2ad7b1,1000000));
const track=(n,codec,lang)=>el(0xae,cat(u(0xd7,n),u(0x83,17),str(0x86,codec),str(0x22b59c,lang)));
const tracks=el(0x1654ae6b,cat(track(2,'S_TEXT/UTF8','eng'),track(3,'S_TEXT/ASS','ita')));
const group=(n,text)=>el(0xa0,cat(el(0xa1,cat([0x80|n,0,0,0],Buffer.from(text))),u(0x9b,2000)));
const time=u(0xe7,1000),a=group(2,'Hello & <world>'),b=group(3,'0,0,Default,,0,0,0,,Ciao\\N{\\i1}mondo');
const cluster=el(0x1f43b675,cat(time,a,b));
let seek=Buffer.alloc(0),clusterPos=0,cues;
const cue=(n,rel)=>el(0xbb,cat(u(0xb3,1000),el(0xb7,cat(u(0xf7,n),u(0xf1,clusterPos),u(0xf0,rel),u(0xb2,2000)))));
for(let i=0;i<10;i++){
  clusterPos=seek.length+info.length+tracks.length;
  cues=el(0x1c53bb6b,cat(cue(2,time.length),cue(3,time.length+a.length)));
  const entry=(ident,pos)=>el(0x4dbb,cat(el(0x53ab,id(ident)),u(0x53ac,pos)));
  seek=el(0x114d9b74,cat(entry(0x1549a966,seek.length),entry(0x1654ae6b,seek.length+info.length),entry(0x1c53bb6b,clusterPos+cluster.length+70000)));
}
const segment=cat(seek,info,tracks,cluster,Buffer.alloc(70000),cues,Buffer.alloc(1000));
writeFileSync(process.argv[2],cat(el(0x1a45dfa3,str(0x4282,'matroska')),id(0x18538067),[0xff],segment));
