const test=require('node:test'),assert=require('node:assert/strict'),VTT=require('vtt.js');
global.window={VTTCue:VTT.VTTCue,VTTRegion:VTT.VTTRegion};
const parser=require('../vendor/stremio/subtitlesParser');
test('Mozilla parser flushes a completed FFmpeg cue without a final blank line',{timeout:1000},async()=>{
 const value=await parser.parse('WEBVTT\n\n00:01:40.021 --> 00:01:45.021\nLATE CAPTION\n');
 assert.deepEqual(value.times,[100021,105021]);assert.equal(value[100021][0].text,'LATE CAPTION');
});
test('malformed WebVTT rejects without hanging',{timeout:1000},async()=>{
 await assert.rejects(parser.parse('INVALID DOCUMENT'));
});
