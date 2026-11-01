import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
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
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(cases,null,2));
run(['-stream_loop','-1','-i',base,...tone,'-t','120','-map','0:v','-map','1:a','-c:v','copy','-c:a','ac3','-ac','2',path.join(root,'background-probe.mkv')]);
console.log(`Generated ${cases.length} synthetic codec cases`);
