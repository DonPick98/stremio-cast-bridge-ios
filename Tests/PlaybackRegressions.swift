import Foundation

@main struct PlaybackRegressions {
    static func main() {
        // Four real tap timings from build49: the old 150ms leading timer
        // launched at +60s. A trailing debounce must dispatch only +120s.
        var burst=PlaybackSeekIntent(),seekTimeline=PlaybackTimeline()
        let taps:[Double]=[0,0.168,0.354,0.535]
        var destination=2124.859
        var tokens:[UUID]=[]
        for time in taps {
            destination+=30;seekTimeline.queue(at:destination)
            burst.submit(now:time);tokens.append(burst.generation)
            precondition(abs((burst.delay(for:burst.generation,now:time) ?? -1)-0.3)<0.00001)
        }
        for obsolete in tokens.dropLast(){precondition(burst.delay(for:obsolete,now:1)==nil && !burst.accepts(obsolete))}
        let latest=tokens.last!
        precondition((burst.delay(for:latest,now:0.684) ?? 0)>0.14,"Do not launch from the first tap's deadline")
        precondition(burst.delay(for:latest,now:0.836)==0)
        let finalTarget=seekTimeline.consumeQueued()!
        precondition(abs(finalTarget-2244.859)<0.00001)
        burst.dispatched(latest);seekTimeline.begin(at:finalTarget)
        precondition(!burst.pending && burst.accepts(latest))

        // A fifth/back tap during prepare or LOAD supersedes the dispatched
        // operation. Its late acknowledgement cannot consume the newer intent.
        seekTimeline.queue(at:2214.859);burst.submit(now:1)
        let duringPrepare=burst.generation
        precondition(!burst.accepts(latest))
        burst.dispatched(latest)
        precondition(burst.pending,"An obsolete completion must not clear the new request")
        precondition(!seekTimeline.observe(0,ready:true))
        precondition(seekTimeline.queuedTarget==2214.859)
        seekTimeline.cancelActive()
        precondition(seekTimeline.consumeQueued()==2214.859)
        burst.dispatched(duringPrepare)
        seekTimeline.begin(at:2214.859)
        seekTimeline.queue(at:2274.859);burst.submit(now:2)
        precondition(!burst.accepts(duringPrepare))
        let beforeStop=burst.generation
        burst.cancel();seekTimeline.reset()
        precondition(!burst.accepts(beforeStop) && !burst.pending && seekTimeline.queuedTarget==nil)
        burst.submit(now:3);let newSource=burst.generation
        precondition(newSource != beforeStop && burst.delay(for:newSource,now:4)==0)

        var clock=ReceiverPlaybackClock()
        clock.load(offset:2184.859)
        precondition(abs(clock.capture(relative:4.255,loaded:true,suspended:false)!-2189.114)<0.00001)
        // The newest LOAD owns the mapping. Stop/release does not rewrite it.
        clock.load(offset:2244.859)
        precondition(clock.capture(relative:0.850,loaded:false,suspended:true)==nil)
        precondition(clock.capture(relative:0.850,loaded:false,suspended:false)==nil)
        precondition(clock.capture(relative:0.850,loaded:true,suspended:true)==nil)
        precondition(clock.offset==2244.859)
        precondition(clock.capture(relative:.nan,loaded:true,suspended:false)==nil)
        precondition(clock.capture(relative:-1,loaded:true,suspended:false)==nil)
        // Resume explicitly from the last confirmed original-media position.
        clock.load(offset:2123.731)
        precondition(abs(clock.capture(relative:0.850,loaded:true,suspended:false)!-2124.581)<0.00001)
        clock.load(offset:0)
        precondition(clock.capture(relative:2124.581,loaded:true,suspended:false)==2124.581)

        func probe(_ fields:String,codec:String="hevc",width:Int=1920,height:Int=1080)->VideoCadenceProbe? {
            VideoCadenceProbe.parse(Data(("{\"streams\":["+fields+"]}").utf8),codec:codec,width:width,height:height)
        }
        let fields=#""codec_type":"video","codec_name":"hevc","width":1920,"height":1080"#
        let exact=probe("{"+fields+",\"avg_frame_rate\":\"24000/1001\",\"r_frame_rate\":\"24000/1001\"}")!
        precondition(abs(exact.frameRate-24000.0/1001)<0.000001 && exact.fixedCadence)
        let unknown=probe("{"+fields+",\"avg_frame_rate\":\"0/0\",\"r_frame_rate\":\"24000/1001\"}")!
        precondition(!unknown.fixedCadence && unknown.frameRate==exact.frameRate)
        let variable=probe("{"+fields+",\"avg_frame_rate\":\"24/1\",\"r_frame_rate\":\"30/1\"}")!
        precondition(variable.frameRate==24 && !variable.fixedCadence)
        precondition(VideoFormat(codec:"hevc",width:1920,height:1080,frameRate:variable.frameRate,fixedCadence:variable.fixedCadence).vlcFrameRate==nil)
        for bad in ["0/0","-24/1","24/0","24/-1","nan","inf","100001/1","24/1/1","/24","24/"] {
            precondition(probe("{"+fields+",\"avg_frame_rate\":\""+bad+"\"}")==nil)
        }
        precondition(probe("{"+fields+",\"avg_frame_rate\":\"24/1\"}",codec:"h264")==nil)
        precondition(probe("{"+fields+",\"avg_frame_rate\":\"24/1\"}",width:1280)==nil)
        let cover=#"{"codec_type":"video","codec_name":"mjpeg","disposition":{"attached_pic":1}},"#
        precondition(probe(cover+"{"+fields+",\"avg_frame_rate\":\"25/1\",\"r_frame_rate\":\"25/1\"}")?.frameRate==25)
        precondition(VideoCadenceProbe.parse(Data(repeating:32,count:65537),codec:"hevc",width:1920,height:1080)==nil)
        precondition(VideoFormat(codec:"hevc",width:1920,height:1080,frameRate:24000.0/1001).conversionKeyframeInterval==48)
        precondition(VideoFormat(codec:"hevc",width:1920,height:1080,frameRate:30000.0/1001).conversionKeyframeInterval==60)
        precondition(VideoFormat(codec:"hevc",width:1280,height:720,frameRate:60000.0/1001).conversionKeyframeInterval==120)
        precondition(VideoFormat(codec:"hevc",width:1920,height:1080,frameRate:0).conversionKeyframeInterval==60)
        var publish=SystemMediaPublishPolicy()
        let origin=Date(timeIntervalSince1970:1_000)
        func accepts(_ t:Double,_ p:Double,playing:Bool=true,loading:Bool=false,foreground:Bool=false,step:Double=30)->Bool {
            publish.accept(title:"Synthetic video",device:"Synthetic receiver",position:p,duration:240,playing:playing,loading:loading,local:true,step:step,foreground:foreground,now:origin.addingTimeInterval(t))
        }
        var publishes=0
        for i in 0...60 {if accepts(Double(i),Double(i)){publishes+=1}}
        precondition(publishes==7,"A stable minute needs seven background publishes, not 61")
        precondition(accepts(60.1,60.1,playing:false),"Pause must publish immediately")
        precondition(!accepts(90,60.1,playing:false),"Paused clock must not cause writes")
        precondition(accepts(90.1,61,playing:false),"A small paused seek must publish immediately")
        precondition(accepts(90.2,61,playing:true),"Resume must publish immediately")
        precondition(accepts(90.3,91),"Seek must publish immediately")
        precondition(accepts(90.4,91.1,step:15),"Changed controls must publish immediately")
        precondition(accepts(90.5,91.2,foreground:true,step:15))
        precondition(!accepts(91,91.7,foreground:true,step:15))
        precondition(accepts(92.5,93.2,foreground:true,step:15))
        publish.reset();precondition(accepts(92.6,93.3,foreground:true,step:15),"Lifecycle recovery must refresh metadata")
        precondition(accepts(92.7,93.4,loading:true,foreground:true,step:15),"Buffering must freeze the system clock immediately")
        publish.reset();precondition(accepts(100,100,playing:false))
        publish.reset();precondition(accepts(100.01,100.01,playing:false),"An explicit tiny seek invalidates throttling")
        let ntsc=VideoFormat(codec:"h264",width:320,height:180,frameRate:29.9706288)
        precondition(ntsc.vlcFrameRate=="30000/1001")
        precondition(VideoFormat(codec:"h264",width:640,height:360,frameRate:24).vlcFrameRate=="24")
        precondition(VideoFormat(codec:"h264",width:640,height:360,frameRate:27.4).vlcFrameRate==nil)
        precondition(VideoFormat(codec:"h264",width:320,height:180,frameRate:25).vlcFrameRate=="25")
        precondition(VideoFormat(codec:"h264",width:1920,height:1080,frameRate:59.94).vlcFrameRate==nil)
        precondition(VideoFormat(codec:"h264",width:320,height:180,frameRate:0).vlcFrameRate==nil)
        var background=BackgroundPlaybackWork()
        precondition(!background.begin(duration:.nan,position:0))
        precondition(!background.begin(duration:100,position:100))
        precondition(!background.begin(duration:.infinity,position:0))
        precondition(!background.begin(duration:1e20,position:0))
        precondition(background.begin(duration:3113.556,position:695.930))
        precondition(!background.begin(duration:200,position:0),"Recovery must retain the foreground job")
        background.update(position:nil);background.update(position:.nan)
        precondition(background.completed==0,"No progress without a confirmed TV clock")
        background.update(position:709.989);let confirmed=background.completed
        precondition(confirmed>14000 && confirmed<14100)
        background.update(position:700);background.update(position:-1)
        precondition(background.completed==confirmed,"Backward seek cannot regress system progress")
        background.update(position:1e20)
        precondition(background.completed==background.total-1,"A seek cannot finish the job")
        background.finish();background.update(position:0)
        precondition(!background.active)
        precondition(background.begin(duration:100,position:0) && background.completed==0)
        let episode = PlaybackContent(type:"series",id:"tt1234567:1:1")
        precondition(PlaybackResume.validated(4600.572,duration:2915) == 0)
        precondition(PlaybackResume.validated(2914,duration:2915) == 0)
        precondition(PlaybackResume.validated(422.058,duration:2915) == 422.058)
        precondition(PlaybackResume.validated(.nan,duration:2915) == 0)
        precondition(!PlaybackReadiness.progressed(actual:21.664,start:21.660,paused:false))
        precondition(!PlaybackReadiness.progressed(actual:.nan,start:21.660,paused:false))
        precondition(PlaybackReadiness.progressed(actual:22,start:21.660,paused:false))
        precondition(PlaybackReadiness.progressed(actual:21.660,start:21.660,paused:true))
        precondition(episode.positionKey == PlaybackContent(type:"series",id:"tt1234567:1:1").positionKey)
        precondition(episode.positionKey != PlaybackContent(type:"series",id:"tt1234567:1:2").positionKey)
        precondition(episode.positionKey != PlaybackContent(type:"movie",id:"tt1234567").positionKey)
        var requests = PlaybackRequestState()
        let first = requests.generation
        precondition(requests.accepts(first))
        requests.invalidate()
        precondition(!requests.accepts(first),"A late error from an old source must be ignored")
        precondition(requests.accepts(requests.generation))
        var intent = PlaybackIntent()
        intent.request(false); intent.request(true)
        precondition(!intent.accepts(false),"A late PAUSED must not replace the latest PLAY")
        precondition(intent.pending == true)
        precondition(intent.accepts(true) && intent.pending == nil)
        intent.request(false); precondition(!intent.accepts(true))
        precondition(intent.accepts(false))

        // The reported outage: failure while disconnected, repeated failure
        // callbacks, then reconnect. Only the real restart consumes a retry.
        var recovery=PlaybackRecoveryState()
        precondition(recovery.retrySameProducer(mode:"ffmpegH264",code:-542398533))
        precondition(!recovery.retrySameProducer(mode:"softwareVP8",code:-542398533))
        precondition(!recovery.retrySameProducer(mode:"ffmpegH264",code:-32))
        precondition(!recovery.retrySameProducer(mode:"ffmpegH264",code:nil))
        precondition(recovery.request())
        precondition(!recovery.retrySameProducer(mode:"ffmpegH264",code:-542398533))
        precondition(!recovery.begin(connected:false,blocked:false))
        precondition(recovery.request() && recovery.attempts == 0)
        precondition(!recovery.begin(connected:true,blocked:true))
        precondition(recovery.begin(connected:true,blocked:false))
        precondition(!recovery.pending && recovery.attempts == 1)
        precondition(!recovery.retrySameProducer(mode:"ffmpegH264",code:-542398533),"Same producer retry must be bounded")
        precondition(!recovery.begin(connected:true,blocked:false))
        precondition(recovery.request() && recovery.begin(connected:true,blocked:false))
        precondition(!recovery.request(),"A persistent failure must not loop forever")
        recovery.reset();precondition(recovery.request())
        precondition(PlaybackCompletion.detachedEnd(finished:true,hasLoaded:true,pending:false,informationPresent:false,currentSession:12,lastSession:12))
        precondition(!PlaybackCompletion.detachedEnd(finished:true,hasLoaded:true,pending:false,informationPresent:false,currentSession:13,lastSession:12),"Another media session must not complete this episode")
        precondition(!PlaybackCompletion.detachedEnd(finished:true,hasLoaded:true,pending:true,informationPresent:false,currentSession:12,lastSession:12),"An old finish during replacement must be ignored")
        precondition(!PlaybackCompletion.detachedEnd(finished:true,hasLoaded:true,pending:false,informationPresent:true,currentSession:12,lastSession:12),"Known media still requires content ownership")
        precondition(!PlaybackCompletion.detachedEnd(finished:true,hasLoaded:true,pending:false,informationPresent:false,currentSession:0,lastSession:nil))

        // Transient PLAYING/BUFFERING acknowledgements without an advancing
        // receiver clock cannot conceal the second stall from the user log.
        var progress=PlaybackProgressMonitor()
        let start=Date(timeIntervalSince1970:1000)
        precondition(!progress.observe(position:2013.665,now:start,expectedToAdvance:true))
        for second in 1..<20 {
            precondition(!progress.observe(position:2013.665,now:start.addingTimeInterval(Double(second)),expectedToAdvance:true))
        }
        precondition(progress.observe(position:2013.665,now:start.addingTimeInterval(20),expectedToAdvance:true))
        precondition(!progress.observe(position:2013.665,now:start.addingTimeInterval(21),expectedToAdvance:false),"An intentional pause is not a stall")
        progress.reset()
        for second in 0...16 {
            precondition(!progress.observe(position:Double(second),now:start.addingTimeInterval(Double(second)),expectedToAdvance:true))
        }
        precondition(progress.stable,"Retry budget resets only after sustained real progress")
        precondition(!progress.observe(position:2,now:start.addingTimeInterval(17),expectedToAdvance:true),"A new backwards timeline restarts monitoring")
        precondition(!progress.stable)

        var timeline = PlaybackTimeline()
        timeline.begin(at:600)
        precondition(!timeline.observe(0,ready:false))
        precondition(!timeline.observe(0,ready:true))
        precondition(!timeline.observe(93,ready:true))
        precondition(timeline.target == 600)
        precondition(timeline.observe(600.25,ready:true))
        precondition(timeline.target == nil)
        timeline.begin(at:90)
        precondition(!timeline.observe(601,ready:true),"A backward seek must not be replaced by the old position")
        precondition(timeline.observe(90.5,ready:true))
        timeline.begin(at:0)
        precondition(!timeline.observe(500,ready:true))
        precondition(timeline.observe(0,ready:true))
        timeline.begin(at:25); timeline.begin(at:.nan)
        precondition(timeline.target == 25)
        timeline.reset(); precondition(timeline.target == nil)
        timeline.begin(at:100); timeline.queue(at:200); timeline.queue(at:450)
        precondition(!timeline.observe(0,ready:true))
        precondition(timeline.target == 100 && timeline.queuedTarget == 450)
        precondition(timeline.observe(100,ready:true))
        precondition(timeline.consumeQueued() == 450)
        timeline.begin(at:450); precondition(!timeline.observe(100,ready:true))
        precondition(timeline.observe(450,ready:true))
        timeline.queue(at:30); timeline.reset(); precondition(timeline.queuedTarget == nil)

        var checkpoint=PlaybackTimeline()
        checkpoint.begin(at:600)
        var failedReplacement=checkpoint
        failedReplacement.queue(at:900)
        let restored=failedReplacement.restoring(checkpoint)
        precondition(restored.target == nil && restored.queuedTarget == 900)
        var accepted=restored
        precondition(accepted.observe(100,ready:true),"Failed seek rollback must accept the still-playing old timeline")
        precondition(accepted.consumeQueued() == 900,"A newer queued seek must survive rollback")

        for rate in [24000.0/1001,24,25,30000.0/1001,30] {
            let video = VideoFormat(codec:"h264",width:1920,height:1080,frameRate:rate,profile:100,level:41)
            precondition(!video.requiresConversion)
            precondition(video.conversionFrameRate == nil,"Compatible frame rates must not be forced to 30")
            precondition(video.conversionBitrate >= 10000)
        }
        let sixty = VideoFormat(codec:"h264",width:1280,height:720,frameRate:60000.0/1001)
        precondition(!sixty.requiresConversion && sixty.conversionFrameRate == nil)
        let fullHD60 = VideoFormat(codec:"h264",width:1920,height:1080,frameRate:60)
        precondition(fullHD60.requiresConversion && fullHD60.conversionFrameRate == 30)
        precondition(!VideoFormat(codec:"h264",width:1920,height:1080,frameRate:0).requiresConversion)
        precondition(VideoFormat(codec:"hevc",width:1920,height:1080,frameRate:25).requiresConversion)
        precondition(VideoFormat(codec:"h264",width:1920,height:1080,frameRate:24,profile:110).requiresConversion)
        precondition(VideoFormat(codec:"h264",width:1920,height:1080,frameRate:24000.0/1001).frameRateLabel == "23.976 fps")
        var live=LiveActivityUpdatePolicy()
        let base=Date(timeIntervalSince1970:1000)
        precondition(live.accept(title:"A",status:"Play",playing:true,position:0,duration:100,step:30,now:base))
        precondition(!live.accept(title:"A",status:"Play",playing:true,position:1,duration:100,step:30,now:base.addingTimeInterval(1)))
        precondition(live.accept(title:"A",status:"Play",playing:true,position:30,duration:100,step:30,now:base.addingTimeInterval(30)))
        precondition(live.accept(title:"A",status:"Play",playing:true,position:5,duration:100,step:30,now:base.addingTimeInterval(31)))
        precondition(live.accept(title:"A",status:"Pause",playing:false,position:5,duration:100,step:30,now:base.addingTimeInterval(32)))
        precondition(!live.accept(title:"A",status:"Pause",playing:false,position:5,duration:100,step:30,now:base.addingTimeInterval(33)))
        precondition(live.accept(title:"B",status:"Pause",playing:false,position:5,duration:100,step:30,now:base.addingTimeInterval(34)))
        precondition(live.accept(title:"B",status:"Pause",playing:false,position:5,duration:100,step:15,now:base.addingTimeInterval(35)))
        precondition(!live.accept(title:"B",status:"Pause",playing:false,position:.nan,duration:100,step:15,now:base.addingTimeInterval(36)))
        print("Playback generation, seek confirmation and original frame-rate regressions passed")
    }
}


