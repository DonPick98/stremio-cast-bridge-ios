import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Protocol implementation based on Stremio/stremio-core 3417c2e7ed45cdbfd86b3226f69814c2dc4947ad:
// library_item.rs, request.rs and stremio-watched-bitfield. No upstream code copied.
enum StremioSyncError:Error {case identity,format,conflict,catalog,network,authentication,limit,storage,rateLimited(Int)}
struct StremioProgressEvent:Codable,Equatable {
    let type:String
    let videoID:String
    let title:String
    let position:Double
    let duration:Double
    let observedAt:Date
    let completed:Bool
    var itemID:String? {
        if type=="movie",videoID.range(of:"^tt[0-9]+$",options:.regularExpression) != nil{return videoID}
        if type=="series",videoID.count<=100,videoID.range(of:"^tt[0-9]+:[0-9]+:[0-9]+$",options:.regularExpression) != nil {
            return videoID.components(separatedBy:":").first
        }
        return nil
    }
    var valid:Bool {itemID != nil && position.isFinite && duration.isFinite && duration>0 && duration<604_800 && position>=0 && position<=duration+2 && !title.isEmpty && title.count<=500}
}
enum StremioWatchedField {
    private static let maxBytes=8192
    static func decode(_ field:String?,ids:[String])throws->[Bool] {
        guard !ids.isEmpty,ids.count<=4096,Set(ids).count==ids.count else{throw StremioSyncError.catalog}
        guard let field,!field.isEmpty else{return Array(repeating:false,count:ids.count)}
        guard field.utf8.count<65_536 else{throw StremioSyncError.limit}
        var parts=field.components(separatedBy:":")
        guard parts.count>=3,let compressed=Data(base64Encoded:parts.removeLast()),let length=Int(parts.removeLast()),(1...65536).contains(length),
              let anchor=ids.firstIndex(of:parts.joined(separator:":")),!compressed.isEmpty else{throw StremioSyncError.catalog}
        var raw=[UInt8](repeating:0,count:maxBytes),size=uLongf(maxBytes)
        let status=compressed.withUnsafeBytes{buffer in uncompress(&raw,&size,buffer.bindMemory(to:Bytef.self).baseAddress,uLong(compressed.count))}
        guard status==Z_OK,size>0,size<=maxBytes,Int(size)*8>=length else{throw StremioSyncError.format}
        let offset=length-anchor-1
        var result=Array(repeating:false,count:ids.count)
        for old in 0..<(Int(size)*8) where raw[old/8] & (1<<UInt8(old%8)) != 0 {
            let index=old-offset
            // Refuse to erase watched entries if a partial/changed catalogue no
            // longer represents them. Unknown anchors are also never reset.
            guard old<length,result.indices.contains(index) else{throw StremioSyncError.catalog}
            result[index]=true
        }
        return result
    }
    static func encode(_ watched:[Bool],ids:[String])throws->String {
        guard watched.count==ids.count,!ids.isEmpty,ids.count<=4096,Set(ids).count==ids.count,let last=watched.lastIndex(of:true) else{throw StremioSyncError.catalog}
        var raw=[UInt8](repeating:0,count:(ids.count+7)/8)
        for i in watched.indices where watched[i]{raw[i/8] |= 1<<UInt8(i%8)}
        var output=[UInt8](repeating:0,count:Int(compressBound(uLong(raw.count)))),size=uLongf(output.count)
        let status=raw.withUnsafeBytes{buffer in compress2(&output,&size,buffer.bindMemory(to:Bytef.self).baseAddress,uLong(raw.count),6)}
        guard status==Z_OK else{throw StremioSyncError.format}
        return ids[last]+":"+String(last+1)+":"+Data(output.prefix(Int(size))).base64EncodedString()
    }
    static func marking(_ field:String?,video:String,ids:[String])throws->(field:String,wasWatched:Bool) {
        guard let index=ids.firstIndex(of:video) else{throw StremioSyncError.catalog}
        var watched=try decode(field,ids:ids);let previous=watched[index];watched[index]=true
        return (try encode(watched,ids:ids),previous)
    }
}
enum StremioLibraryMerge {
    static func date(_ value:Any?)->Date? {
        guard let value=value as? String else{return nil}
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return formatter.date(from:value) ?? ISO8601DateFormatter().date(from:value)
    }
    static func stamp(_ value:Date)->String {
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return formatter.string(from:value)
    }
    static func resume(_ remote:[String:Any],videoID:String,localUpdated:Date)->Double? {
        guard let mtime=date(remote["_mtime"]),mtime>localUpdated,let state=remote["state"] as? [String:Any],
              state["video_id"] as? String==videoID,let ms=(state["timeOffset"] as? NSNumber)?.doubleValue,ms.isFinite,ms>0,ms<604_800_000 else{return nil}
        return ms/1000
    }
    static func applying(_ event:StremioProgressEvent,to remote:[String:Any]?,episodes:[String],now:Date=Date(),acceptedState:Data?=nil)throws->[String:Any] {
        guard event.valid,let id=event.itemID,event.observedAt<=now.addingTimeInterval(5) else{throw StremioSyncError.identity}
        var item:[String:Any]
        if let remote {
            guard remote["_id"] as? String==id,remote["type"] as? String==event.type,let mtime=date(remote["_mtime"]),remote["state"] is [String:Any] else{throw StremioSyncError.format}
            let currentState=try JSONSerialization.data(withJSONObject:remote["state"]!,options:.sortedKeys)
            guard mtime<=event.observedAt || (acceptedState != nil && currentState==acceptedState) else{throw StremioSyncError.conflict}
            item=remote
        } else {
            item=["_id":id,"name":event.title,"type":event.type,"posterShape":"poster","removed":true,"temp":true,"_ctime":stamp(event.observedAt),"behaviorHints":[:]]
        }
        var state=item["state"] as? [String:Any] ?? [:]
        func number(_ key:String)->Int64 {max(0,min(9_000_000_000_000,(state[key] as? NSNumber)?.int64Value ?? 0))}
        let changed=(state["video_id"] as? String) != event.videoID
        let time=number("timeWatched"),overall=number("overallTimeWatched"),count=number("timesWatched")
        state["overallTimeWatched"]=min(9_000_000_000_000,overall+(changed ? time:0))
        state["timeWatched"]=changed ? 0:time
        state["timesWatched"]=count
        state["flaggedWatched"]=changed ? 0:number("flaggedWatched")
        if event.completed {
            var already=count>0
            if event.type=="series" {
                let marked=try StremioWatchedField.marking(state["watched"] as? String,video:event.videoID,ids:episodes)
                state["watched"]=marked.field;already=marked.wasWatched
            }
            if !already{state["timesWatched"]=min(Int64(UInt32.max),count+1)}
            state["flaggedWatched"]=1
        }
        state["timeOffset"]=event.completed ? 0:Int64((event.position*1000).rounded())
        state["duration"]=Int64((event.duration*1000).rounded())
        state["video_id"]=event.videoID
        state["lastWatched"]=stamp(event.observedAt)
        if state["noNotif"]==nil{state["noNotif"]=false}
        item["state"]=state;item["_mtime"]=stamp(now)
        return item
    }
}

struct StremioAccount:Codable {let authKey:String;let id:String;var email:String?=nil}
private final class StremioRedirectGuard:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
}
final class StremioLibraryAPI {
    private let configuration:URLSessionConfiguration
    init(configuration:URLSessionConfiguration = .ephemeral){self.configuration=configuration}
    func login(email:String,password:String) async throws->StremioAccount {
        guard !email.isEmpty,email.count<=320,!password.isEmpty,password.count<=1024 else{throw StremioSyncError.authentication}
        guard let result=try await call("login",["type":"Login","email":email,"password":password,"facebook":false]) as? [String:Any],
              let key=result["authKey"] as? String,!key.isEmpty,key.count<=4096,let user=result["user"] as? [String:Any],let id=user["_id"] as? String,!id.isEmpty,id.count<=256 else{throw StremioSyncError.authentication}
        return StremioAccount(authKey:key,id:id,email:user["email"] as? String)
    }
    func item(_ id:String,account:StremioAccount) async throws->[String:Any]? {
        let result=try await call("datastoreGet",["authKey":account.authKey,"collection":"libraryItem","ids":[id],"all":false])
        guard let items=result as? [[String:Any]],items.count<=1,items.allSatisfy({$0["_id"] as? String==id}) else{throw StremioSyncError.format}
        return items.first
    }
    func put(_ item:[String:Any],account:StremioAccount) async throws {
        let result=try await call("datastorePut",["authKey":account.authKey,"collection":"libraryItem","changes":[item]])
        guard let result=result as? [String:Any],result["success"] as? Bool==true else{throw StremioSyncError.format}
    }
    private func call(_ path:String,_ body:[String:Any]) async throws->Any {
        guard ["login","datastoreGet","datastorePut"].contains(path) else{throw StremioSyncError.identity}
        let config=configuration.copy() as! URLSessionConfiguration
        config.timeoutIntervalForRequest=10;config.timeoutIntervalForResource=15
        config.httpCookieStorage=nil;config.urlCredentialStorage=nil;config.urlCache=nil
        let session=URLSession(configuration:config,delegate:StremioRedirectGuard(),delegateQueue:nil)
        defer{session.invalidateAndCancel()}
        var request=URLRequest(url:URL(string:"https://api.strem.io/api/"+path)!)
        request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:body)
        guard request.httpBody!.count<=1_048_576 else{throw StremioSyncError.limit}
        let data:Data,response:URLResponse
        #if canImport(Darwin)
        let (bytes,received)=try await session.bytes(for:request);response=received
        guard response.expectedContentLength<=2_097_152 else{throw StremioSyncError.limit}
        var collected=Data()
        for try await byte in bytes{try Task.checkCancellation();guard collected.count<2_097_152 else{throw StremioSyncError.limit};collected.append(byte)}
        data=collected
        #else
        (data,response)=try await session.data(for:request)
        guard data.count<=2_097_152 else{throw StremioSyncError.limit}
        #endif
        guard let http=response as? HTTPURLResponse,http.url?.host=="api.strem.io",http.url?.scheme=="https" else{throw StremioSyncError.network}
        if http.statusCode==429 {
            let delay=Int(http.value(forHTTPHeaderField:"Retry-After") ?? "") ?? 60
            throw StremioSyncError.rateLimited(max(1,min(3600,delay)))
        }
        if [401,403].contains(http.statusCode){throw StremioSyncError.authentication}
        guard http.statusCode==200 else{throw StremioSyncError.network}
        guard let envelope=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw StremioSyncError.format}
        if envelope["error"] != nil{throw path=="login" ? StremioSyncError.authentication:StremioSyncError.network}
        guard envelope.count==1,let result=envelope["result"] else{throw StremioSyncError.format}
        return result
    }
}


struct StremioOutbox:Codable {
    struct Entry:Codable,Identifiable {let id:UUID;let event:StremioProgressEvent;let episodes:[String]}
    private(set) var entries:[Entry]=[]
    private(set) var receipts:[String:Data]=[:]
    mutating func enqueue(_ event:StremioProgressEvent,episodes:[String])throws {
        guard event.valid,episodes.count<=4096 else{throw StremioSyncError.identity}
        var updated=entries
        let same=updated.filter{$0.event.type==event.type && $0.event.videoID==event.videoID}
        if same.contains(where:{$0.event.observedAt>event.observedAt}){return}
        updated.removeAll{$0.event.type==event.type && $0.event.videoID==event.videoID && (event.completed || !$0.event.completed)}
        guard updated.count<32 else{throw StremioSyncError.limit}
        updated.append(Entry(id:UUID(),event:event,episodes:episodes))
        entries=updated.sorted{$0.event.observedAt<$1.event.observedAt}
    }
    mutating func acknowledge(_ id:UUID,itemID:String,state:Data) {
        entries.removeAll{$0.id==id}
        if state.count<=65536{receipts[itemID]=state}
        if receipts.count>128,let old=receipts.keys.sorted().first(where:{$0 != itemID}){receipts[old]=nil}
    }
    mutating func discard(_ ids:Set<UUID>){entries.removeAll{ids.contains($0.id)}}
}
