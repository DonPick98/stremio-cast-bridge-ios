import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {makePGS} from './make-pgs-fixture.mjs';
import {identityFilter} from './frame-identity-fixture.mjs';
const root=path.resolve(process.argv[2]||'codec-matrix');
fs.mkdirSync(root,{recursive:true});
const binary=process.env.CAST_FIXTURE_FFMPEG||'ffmpeg';
const encoders=spawnSync(binary,['-hide_banner','-encoders'],{encoding:'utf8'}).stdout||'';
const vorbis=encoders.includes('libvorbis')?'libvorbis':'vorbis';
const av1=encoders.includes('libaom-av1')?'libaom-av1':'libsvtav1';
function run(args){const r=spawnSync(binary,['-hide_banner','-loglevel','error','-y',...args],{encoding:'utf8',maxBuffer:2e6});if(r.status!==0)throw new Error(r.stderr?.slice(-1000)||'Fixture encoder failed');}
const base=path.join(root,'base.mp4');
run(['-f','lavfi','-i','testsrc2=size=320x180:rate=24','-t','6','-an','-c:v','libx264','-pix_fmt','yuv420p','-preset','ultrafast','-g','24','-threads','2',base]);
const cases=[];
const tone=['-f','lavfi','-i','sine=frequency=880:sample_rate=48000'];
for(const [name,codec,channels,ext] of [
 ['aac_stereo','aac',2,'mp4'],['aac_51','aac',6,'mkv'],['ac3_stereo','ac3',2,'mkv'],['ac3_51','ac3',6,'mkv'],
 ['eac3_51','eac3',6,'mkv'],['dts','dca',2,'mkv'],['truehd','truehd',2,'mkv'],['flac','flac',2,'mkv'],
 ['pcm','pcm_s16le',2,'mkv'],['mp3','libmp3lame',2,'mp4'],['vorbis','libvorbis',2,'mkv'],['opus','libopus',2,'mkv']]){
 const filename=`${name}.${ext}`;
 run(['-i',base,...tone,'-t','6','-map','0:v:0','-map','1:a:0','-c:v','copy','-c:a',codec==='libvorbis'?vorbis:codec,'-ac',String(channels),'-strict','-2','-metadata:s:a:0','language=eng',path.join(root,filename)]);
 cases.push({name,filename,burn:false,selectAlternate:false});
}
for(const [name,codec,ext,extra,audio] of [
 ['hevc8','libx265','mkv',['-preset','ultrafast','-x265-params','pools=2:frame-threads=2:log-level=error'],'aac'],
 ['hevc10','libx265','mkv',['-pix_fmt','yuv420p10le','-preset','ultrafast','-x265-params','pools=2:frame-threads=2:log-level=error'],'aac'],
 ['h264_high10','libx264','mkv',['-pix_fmt','yuv420p10le','-profile:v','high10','-preset','ultrafast'],'aac'],
 ['vp8','libvpx','webm',['-deadline','realtime','-cpu-used','8'],'libvorbis'],
 ['vp9','libvpx-vp9','webm',['-deadline','realtime','-cpu-used','8'],'libvorbis'],
 ['av1',av1,'mkv',av1==='libaom-av1'?['-cpu-used','8','-row-mt','1']:['-preset','13','-svtav1-params','lp=2'],'aac'],
 ['mpeg2','mpeg2video','ts',[],'mp2'],['mpeg4','mpeg4','avi',['-q:v','5'],'libmp3lame'],
 ['wmv2','wmv2','asf',[],'wmav2'],['h264_ts','libx264','ts',['-preset','ultrafast'],'aac'],
 ['h264_flv','libx264','flv',['-preset','ultrafast'],'aac']]){
 const filename=`${name}.${ext}`;
 run(['-f','lavfi','-i','testsrc2=size=320x180:rate=24',...tone,'-t','6','-c:v',codec,...extra,'-threads','2','-g','24','-c:a',audio==='libvorbis'?vorbis:audio,'-ac','2','-strict','-2',path.join(root,filename)]);
 cases.push({name,filename,burn:false,selectAlternate:false});
}
const multi='multiple_audio.mkv';
run(['-i',base,...tone,'-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','6','-map','0:v','-map','1:a','-map','2:a','-c:v','copy','-c:a:0','ac3','-c:a:1','aac','-ac','2','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=ita',path.join(root,multi)]);
cases.push({name:'multiple_audio',filename:multi,burn:false,selectAlternate:true});
const subtitle='embedded_text.mkv';
fs.writeFileSync(path.join(root,'captions.srt'),'1\n00:00:00,000 --> 00:00:01,800\nNative subtitle overlay\n');
run(['-i',base,...tone,'-i',path.join(root,'captions.srt'),'-t','6','-map','0:v','-map','1:a','-map','2:s','-c:v','copy','-c:a','ac3','-ac','2','-c:s','srt','-metadata:s:s:0','language=eng',path.join(root,subtitle)]);
cases.push({name:'embedded_text',filename:subtitle,burn:true,selectAlternate:false});
// DVD-sized MPEG-4 ASP with B frames, quarter-pixel motion, MP3/AC3 and SRT.
// Exercise the actual streaming gateway, including a non-keyframe seek.
run(['-f','lavfi','-i','testsrc2=size=720x480:rate=30000/1001',...tone,'-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-i',path.join(root,'captions.srt'),'-t','12','-map','0:v','-map','1:a','-map','2:a','-map','3:s','-c:v','mpeg4','-q:v','4','-bf','2','-flags','+qpel+mv4','-g','60','-threads','2','-c:a:0','libmp3lame','-c:a:1','ac3','-ac','2','-c:s','srt','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=ita','-metadata:s:s:0','language=eng',path.join(root,'quality-legacy-asp.mkv')]);
for(const [name,burn,start,selectAlternate] of [['legacy_asp',false,0,false],['legacy_asp_subtitles',true,0,false],['legacy_asp_seek',false,3.25,true],['legacy_asp_subtitles_seek',true,3.25,false]]) cases.push({name,filename:'quality-legacy-asp.mkv',burn,start,selectAlternate,native:true});
// The first subtitle is deliberately wrong and always visible. The selected
// second subtitle appears only at source 6-9 s, after a non-keyframe seek.
// Black frames allow the verifier to prove actual rendered text and timing,
// independently of a successful video decode or a transient PLAYING status.
fs.writeFileSync(path.join(root,'wrong.srt'),'1\n00:00:00,000 --> 00:00:12,000\nWRONG TRACK\n');
fs.writeFileSync(path.join(root,'seek.srt'),'1\n00:00:06,000 --> 00:00:09,000\nEMBEDDED CAPTION AFTER SEEK\n');
for(const codec of ['srt','ass']){
 const filename=`caption-${codec}-seek.mkv`;
 run(['-f','lavfi','-i','color=black:size=640x360:rate=24',...tone,'-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-i',path.join(root,'wrong.srt'),'-i',path.join(root,'seek.srt'),'-t','12','-map','0:v','-map','1:a','-map','2:a','-map','3:s','-map','4:s','-c:v','libx264','-pix_fmt','yuv420p','-preset','ultrafast','-g','48','-threads','2','-c:a','aac','-ac','2','-c:s',codec,'-metadata:s:a:0','language=eng','-metadata:s:a:1','language=ita','-metadata:s:s:0','language=eng','-metadata:s:s:1','language=ita',path.join(root,filename)]);
 cases.push({name:`caption_${codec}_seek`,filename,burn:true,start:3.25,selectAlternate:true,selectLastSubtitle:true});
}
// Startup versus seek: HEVC 10-bit 1080p, FLAC/EAC3/AAC/AAC, 13 ASS tracks.
// Select the second audio (440 Hz EAC3) and the first, correctly timed caption.
const animeMaps=['-map','0:v',...Array.from({length:4},(_,i)=>['-map',`${i+1}:a`]).flat(),'-map','5:s',...Array.from({length:12},()=>['-map','6:s']).flat()];
run(['-f','lavfi','-i',identityFilter,...tone,'-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-f','lavfi','-i','sine=frequency=660:sample_rate=48000','-f','lavfi','-i','sine=frequency=550:sample_rate=48000','-i',path.join(root,'seek.srt'),'-i',path.join(root,'wrong.srt'),'-t','12',...animeMaps,'-c:v','libx265','-pix_fmt','yuv420p10le','-preset','ultrafast','-x265-params','pools=2:frame-threads=2:log-level=error','-threads','2','-g','48','-c:a:0','flac','-c:a:1','eac3','-c:a:2','aac','-c:a:3','aac','-ac','2','-c:s','ass','-metadata:s:a:0','language=jpn','-metadata:s:a:1','language=eng','-metadata:s:s:0','language=eng',path.join(root,'caption-hevc-eac3.mkv')]);
for(const [name,start] of [['caption_hevc_eac3_start',0],['caption_hevc_eac3_seek',3.25]]) cases.push({name,filename:'caption-hevc-eac3.mkv',burn:true,start,audioIndex:1});
const font='/System/Library/Fonts/Supplemental/Arial.ttf';
if(!fs.existsSync(font))throw new Error('Synthetic caption font fixture is required');
fs.copyFileSync(font,path.join(root,'caption-font.ttf'));
run(['-i',path.join(root,'caption-hevc-eac3.mkv'),'-map','0','-c','copy','-attach',font,'-metadata:s:t:0','filename=caption-font.ttf','-metadata:s:t:0','mimetype=application/x-truetype-font',path.join(root,'caption-with-font.mkv')]);
fs.renameSync(path.join(root,'caption-with-font.mkv'),path.join(root,'caption-hevc-eac3.mkv'));
// Sparse bitmap captions and a long GOP exercise the failing post-seek route.
makePGS(path.join(root,'correct.sup'),6,9);
makePGS(path.join(root,'wrong.sup'),0,12);
run(['-f','lavfi','-i','color=black:size=640x360:rate=24',...tone,'-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-i',path.join(root,'wrong.sup'),'-i',path.join(root,'correct.sup'),'-t','12','-map','0:v','-map','1:a','-map','2:a','-map','3:s','-map','4:s','-c:v','libx265','-pix_fmt','yuv420p10le','-preset','ultrafast','-x265-params','pools=2:frame-threads=2:log-level=error','-g','192','-threads','2','-c:a','aac','-ac','6','-c:s','copy','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=ita','-metadata:s:s:0','language=eng','-metadata:s:s:1','language=ita',path.join(root,'caption-pgs.mkv')]);
for(const [name,start] of [['caption_pgs_start',0],['caption_pgs_seek',3.25]])cases.push({name,filename:'caption-pgs.mkv',burn:true,start,selectAlternate:true,selectLastSubtitle:true});
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(cases,null,2));
fs.writeFileSync(path.join(root,'late.srt'),'1\n00:01:40,000 --> 00:01:45,000\nLATE CAPTION\n');
run(['-f','lavfi','-i','color=black:size=160x90:rate=1',...tone,'-i',path.join(root,'late.srt'),'-t','150','-map','0:v','-map','1:a','-map','2:s','-c:v','libx264','-preset','ultrafast','-g','1','-threads','2','-c:a','aac','-c:s','srt',path.join(root,'caption-late.mkv')]);
run(['-stream_loop','-1','-i',base,...tone,'-t','1200','-map','0:v','-map','1:a','-c:v','copy','-c:a','ac3','-ac','2',path.join(root,'background-probe.mkv')]);
console.log(`Generated ${cases.length} synthetic codec cases`);
for(const [name,size,rate] of [['1080-23976','1920x1080','24000/1001'],['25','320x180','25'],['2997','320x180','30000/1001'],['720-60','1280x720','60']]){
 run(['-f','lavfi','-i',`testsrc2=size=${size}:rate=${rate}`,...tone,'-t','4','-c:v','libx264','-preset','veryfast','-crf','23','-threads','2','-g',String(Math.round(rate.split('/').map(Number).reduce((a,b)=>a/b))),'-c:a','ac3','-ac','2',path.join(root,`quality-${name}.mkv`)]);
}
run(['-f','lavfi','-i','testsrc2=size=320x180:rate=24',...tone,'-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','12','-map','0:v','-map','1:a','-map','2:a','-c:v','libx264','-preset','ultrafast','-threads','2','-g','48','-c:a:0','truehd','-strict','-2','-c:a:1','aac','-ac','2','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=ita',path.join(root,'quality-seek.mkv')]);


