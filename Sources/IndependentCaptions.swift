import Foundation
import GoogleCast
import MobileVLCKit
import AVFAudio

enum ReceiverConfiguration {
    static var applicationID:String {
        let value=(Bundle.main.object(forInfoDictionaryKey:"CastBridgeReceiverAppID") as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        return value.range(of:"^[A-F0-9]{8}$",options:.regularExpression) != nil ? value:kGCKDefaultMediaReceiverApplicationID
    }
    static var independent:Bool{applicationID != kGCKDefaultMediaReceiverApplicationID}
    static var preserveASS:Bool{UserDefaults.standard.bool(forKey:"cast.subtitle.originalASS")}
}

@MainActor final class CaptionChannel:GCKCastChannel {
    var receive:(([String:Any])->Void)?
    init(){super.init(namespace:"urn:x-cast:app.castbridge.captions")}
    override func didReceiveTextMessage(_ message:String){
        guard message.utf8.count<=16384,let data=message.data(using:.utf8),let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return}
        receive?(json)
    }
    @discardableResult func send(_ value:[String:Any])->Bool{
        guard isConnected,let data=try? JSONSerialization.data(withJSONObject:value),data.count<=16384,let text=String(data:data,encoding:.utf8) else{return false}
        var error:GCKError?;return sendTextMessage(text,error:&error)
    }
}

/// Owns only caption preparation and presentation. It cannot issue a video
/// LOAD, pause, seek or change source/audio. The receiver pulls immutable text
/// revisions using its own clock, independently of sender socket reconnects.
@MainActor final class IndependentCaptions {
    var onStatus:((Bool,String?)->Void)?
    private let channel=CaptionChannel()
    private weak var session:GCKCastSession?
    private var gateway:CaptionHTTPServer?
    private(set) var stateURL:URL?
    private var serverTask:Task<Void,Never>?
    private var helloTask:Task<Void,Never>?
    private var work:Task<Void,Never>?
    private var catalogTask:Task<CaptionCatalog,Error>?
    private let extractor=CaptionExtractor()
    private var source="",key="",epoch="",peer=""
    private var input:URL?
    private var sourceTracks:[RDTrack]=[]
    private var chosen="none",external:URL?,externalText:String?
    private var duration:Double=0,position:Double=0,offset:Double=0,delay:Double=0
    private var revision=0,choice=UUID(),snapshot:CaptionSnapshot?,snapshotURL:URL?
    private var fontURLs:[URL]=[],fontSource=""
    private var visibleRevision=0
    private var fallbackVTT=false
    private var helper:VLCMediaPlayer?
    private var pendingRefresh=false
    private var lastRestart=Date.distantPast
    private var failedUntil=Date.distantPast
    private var publishSerial=0

    init(){channel.receive={ [weak self] in self?.receive($0) }}
    var enabled:Bool{ReceiverConfiguration.independent}
    func attach(_ newSession:GCKCastSession?){
        guard enabled else{return}
        if session !== newSession{
            session?.remove(channel);session=newSession;newSession?.add(channel)
            helloTask?.cancel()
            if newSession != nil{
                helloTask=Task{for _ in 0..<10{guard !Task.isCancelled else{return};channel.send(["version":1,"type":"hello"]);configureReceiver();try? await Task.sleep(nanoseconds:1_000_000_000)}}
            }
        }
        if let address=newSession?.device.ipAddress,CastWire.localIPv4(address),gateway == nil || peer != address{
            peer=address;serverTask?.cancel();gateway?.stop();gateway=nil;stateURL=nil
            serverTask=Task{
                do{
                    let host=try EmbeddedMediaEngine.localAddress(to:address)
                    let server=CaptionHTTPServer(localIP:host,peer:address)
                    server.onPosition={ [weak self] epoch,time,_ in Task{@MainActor in self?.requested(epoch:epoch,position:time)} }
                    let url=try await server.start();guard !Task.isCancelled,peer==address else{server.stop();return}
                    gateway=server;stateURL=url;publishState();configureReceiver();if chosen != "none"{prepare(at:position)}
                }catch{if !Task.isCancelled{onStatus?(false,"Il collegamento dei sottotitoli non è pronto. Il video continua.")}}
            }
        }
    }
    func bind(epoch:String,offset:Double){
        guard enabled else{return};self.epoch=epoch;self.offset=offset
        publishState();configureReceiver()
    }
    var mediaData:[String:Any]{
        var data:[String:Any]=["epoch":epoch,"offset":offset]
        if let stateURL{data["stateURL"]=stateURL.absoluteString};return data
    }
    func synchronize(input:URL,tracks:[RDTrack],selected:String,extractedKey:String,external:URL?,externalText:String?,source:String,position:Double,duration:Double,delay:Double){
        guard enabled else{return}
        self.position=position;self.duration=duration;self.delay=delay
        let selection=selected == "embedded" ? extractedKey:selected
        let styleChoice=ReceiverConfiguration.preserveASS ? "ass":"vtt"
        let next=source+"|"+selection+"|"+(external?.absoluteString ?? "")+"|"+styleChoice
        if self.source != source{
            catalogTask?.cancel();catalogTask=nil;fontURLs=[];fontSource="";gateway?.clearAssets()
        }
        self.input=input;sourceTracks=tracks;self.external=external;self.externalText=externalText;self.source=source;chosen=selection
        keepAlive(selected != "none")
        if key != next{
            key=next;choice=UUID();work?.cancel();work=nil;extractor.stop();snapshot=nil;snapshotURL=nil;fallbackVTT=false;failedUntil = .distantPast
            publishState()
            if selected == "none"{onStatus?(false,nil);return}
            onStatus?(true,nil);prepare(at:position)
        }else{publishStateIfStyleChanged();if snapshot == nil,selected != "none",work==nil,Date()>=failedUntil{prepare(at:position)}}
    }
    private var lastStyle=""
    private func style()->[String:Any]{
        let value=SubtitleAppearance.load();return ["scale":value.scale,"color":value.color,"font":value.font,"background":value.background,"outline":value.outline,"position":0.08]
    }
    private func publishStateIfStyleChanged(){
        let stamp=String(describing:SubtitleAppearance.load())+"|"+String(delay)
        if stamp != lastStyle{lastStyle=stamp;publishState()}
    }
    private func publishState(){
        guard !epoch.isEmpty else{return}
        revision+=1
        var message:[String:Any]=["version":1,"epoch":epoch,"revision":revision,"request":UUID().uuidString,"type":"clear"]
        if chosen != "none",let snapshot,let snapshotURL{
            message.merge(["type":"select","track":trackID,"format":snapshot.format.rawValue,"url":snapshotURL.absoluteString,"rangeStart":snapshot.start,"rangeEnd":snapshot.coveredUntil,"complete":snapshot.sourceComplete,"delay":delay,"style":style(),"fonts":fontURLs.map{$0.absoluteString}],uniquingKeysWith:{_,new in new})
        }
        if let data=try? JSONSerialization.data(withJSONObject:message){gateway?.setState(epoch:epoch,data:data)}
        channel.send(message)
    }
    private var trackID:String{String(key.utf8.reduce(UInt64(1469598103934665603)){($0 ^ UInt64($1)) &* 1099511628211},radix:16)}
    private func configureReceiver(){guard !epoch.isEmpty,let stateURL else{return};channel.send(["version":1,"type":"configure","epoch":epoch,"stateURL":stateURL.absoluteString])}
    private func requested(epoch:String,position:Double){
        guard self.epoch==epoch,position.isFinite,position>=0,position<1e7,(duration<=0 || position<=duration+5),chosen != "none" else{return}
        self.position=position
        guard let snapshot else{if work==nil&&Date()>=failedUntil{prepare(at:position)};return}
        if (position<snapshot.start || (!snapshot.sourceComplete && position>=snapshot.coveredUntil-8)),Date().timeIntervalSince(lastRestart)>2,work==nil{
            prepare(at:position)
        }
    }
    private func prepare(at position:Double){
        guard enabled,chosen != "none",let input,let gateway,work==nil,Date()>=failedUntil else{return}
        let token=choice,selected=chosen,key=self.key;lastRestart=Date()
        work=Task{
            do{
                if selected == "external"{
                    let text:String
                    if let externalText{ text=externalText }
                    else if let external{ text=try await WebVTTTimeline.fetch(external) }
                    else{throw CaptionFailure.input}
                    guard !Task.isCancelled,choice==token else{return}
                    let value=CaptionSnapshot(data:Data(text.utf8),format:.vtt,start:0,coveredUntil:max(1,duration),sourceComplete:true,fonts:[])
                    await publish(value,gateway:gateway,token:token);work=nil;return
                }
                guard let ordinal=sourceTracks.firstIndex(where:{$0.key==selected}) else{throw CaptionFailure.track}
                let native=sourceTracks[ordinal]
                if catalogTask==nil{catalogTask=Task{try await CaptionExtractor.catalog(input)}}
                let catalog=try await catalogTask!.value
                try Task.checkCancellation();guard choice==token else{return}
                let track=try catalog.selected(ordinal:ordinal,vlcID:Int(selected.dropFirst(4)),language:native.language,codec:native.codec)
                let format:CaptionFormat=track.isASS&&ReceiverConfiguration.preserveASS && !fallbackVTT ? .ass:.vtt
                if format == .ass,fontSource != source{
                    let fonts=(try? await CaptionExtractor.fonts(input,catalog:catalog)) ?? []
                    try Task.checkCancellation();guard choice==token else{return}
                    fontURLs=[];for font in fonts{if let url=try? await gateway.publishFont(font){fontURLs.append(url)}};fontSource=source
                }
                try extractor.start(input:input,track:track,format:format,position:position,duration:duration,onUpdate:{ [weak self] value in
                    guard let self,self.choice==token,self.key==key else{return}
                    Task{@MainActor in await self.publish(value,gateway:gateway,token:token)}
                    if value.coveredUntil>=min(self.duration,value.start+90)-0.05{self.work=nil}
                },onFailure:{ [weak self] _ in
                    guard let self,self.choice==token else{return};self.work=nil;self.failedUntil=Date().addingTimeInterval(10)
                    self.onStatus?(false,"Non riesco a preparare questa traccia. Il video continua; puoi riprovare o scegliere un’altra traccia.")
                })
            }catch{
                guard !Task.isCancelled,choice==token else{return};work=nil;failedUntil=Date().addingTimeInterval(10)
                onStatus?(false,"Non riesco a leggere questa traccia. Il video continua; puoi scegliere un’altra traccia.")
            }
        }
    }
    private func publish(_ value:CaptionSnapshot,gateway:CaptionHTTPServer,token:UUID) async{
        guard choice==token else{return};publishSerial+=1;let serial=publishSerial
        do{let url:URL
            if let previous=snapshotURL,snapshot?.data==value.data,snapshot?.format==value.format{url=previous}
            else{url=try await gateway.publish(value.data,format:value.format)}
            guard choice==token,serial==publishSerial else{return};snapshot=value;snapshotURL=url;publishState();onStatus?(false,nil)
        }catch{if choice==token{onStatus?(false,"Il testo non è disponibile. Il video continua.")}}
    }
    private func receive(_ message:[String:Any]){
        guard message["version"] as? Int==1 else{return}
        if message["type"] as? String == "hello"{configureReceiver();return}
        guard message["epoch"] as? String==epoch else{return}
        if message["type"] as? String == "need",message["track"] as? String==trackID,let time=message["position"] as? Double{requested(epoch:epoch,position:time)}
        if message["type"] as? String == "state",message["track"] as? String==trackID,let state=message["state"] as? String,let received=message["revision"] as? Int,received>=visibleRevision{
            visibleRevision=received
            if state == "unavailable"{
                if snapshot?.format == .ass && !fallbackVTT{fallbackVTT=true;choice=UUID();extractor.stop();work?.cancel();work=nil;prepare(at:position)}
                else{onStatus?(false,"Il ricevitore non ha mostrato il testo. Il video continua.")}
            }
        }
    }
    func retry(){failedUntil = .distantPast;work?.cancel();work=nil;extractor.stop();catalogTask?.cancel();catalogTask=nil;choice=UUID();prepare(at:position)}
    private func keepAlive(_ active:Bool){
        if !active{helper?.stop();helper=nil;return}
        guard helper==nil else{return}
        try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback);try? AVAudioSession.sharedInstance().setActive(true)
        let player=VLCMediaPlayer(options:["--demux=rawaud"]);player.media=VLCMedia(path:"/dev/zero");helper=player;player.play()
    }
    func clearSource(){choice=UUID();work?.cancel();work=nil;extractor.stop();catalogTask?.cancel();catalogTask=nil;source="";key="";chosen="none";snapshot=nil;snapshotURL=nil;fontURLs=[];fontSource="";visibleRevision=0;gateway?.clearAssets();publishState();keepAlive(false)}
    func stop(){clearSource();helloTask?.cancel();serverTask?.cancel();session?.remove(channel);session=nil;gateway?.stop();gateway=nil;stateURL=nil;epoch=""}
}
