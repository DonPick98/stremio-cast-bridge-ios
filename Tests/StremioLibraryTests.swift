import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
private final class LibraryProtocol:URLProtocol,@unchecked Sendable {
    static var handler:((URLRequest)throws->(Int,String))?
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        do {
            let (status,body)=try Self.handler!(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
        }catch{client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading(){}
}
@main struct StremioLibraryTests {
    static func main()async throws {
        let ids=(1...5).map{"tt2934286:1:\($0)"}
        // Exact example in upstream watched_bitfield.rs; id contains colons.
        let field="tt2934286:1:5:5:eJyTZwAAAEAAIA=="
        let known=try StremioWatchedField.decode(field,ids:ids)
        precondition(known==Array(repeating:true,count:5))
        let shifted=try StremioWatchedField.decode(field,ids:["tt2934286:0:1"]+ids)
        precondition(shifted==[false,true,true,true,true,true])
        let encoded=try StremioWatchedField.encode([true,false,true,false,true],ids:ids)
        let decoded=try StremioWatchedField.decode(encoded,ids:ids)
        precondition(decoded==[true,false,true,false,true])
        let marked=try StremioWatchedField.marking(encoded,video:ids[1],ids:ids)
        precondition(!marked.wasWatched)
        let again=try StremioWatchedField.marking(marked.field,video:ids[1],ids:ids)
        precondition(again.wasWatched && again.field==marked.field)
        func reject(_ block:()throws->Void){do{try block();fatalError("Invalid library mutation accepted")}catch is StremioSyncError{}catch{fatalError("Unexpected error")}}
        for invalid in ["unknown:5:eJyTZwAAAEAAIA==","tt2934286:1:5:999999:eJyTZwAAAEAAIA==","tt2934286:1:5:5:invalid"] {
            reject{_ = try StremioWatchedField.decode(invalid,ids:ids)}
        }
        reject{_ = try StremioWatchedField.decode(field,ids:[ids.last!])}
        let now=Date(timeIntervalSince1970:1_700_000_000)
        let event=StremioProgressEvent(type:"series",videoID:ids[1],title:"Synthetic",position:42.25,duration:1200,observedAt:now,completed:false)
        let state:[String:Any]=["watched":encoded,"video_id":ids[0],"timeWatched":500,"overallTimeWatched":100,"timesWatched":3,"duration":900_000,"timeOffset":500,"noNotif":true,"futureField":"keep"]
        let remote:[String:Any]=["_id":"tt2934286","type":"series","name":"Existing title","removed":false,"temp":false,"state":state,"_mtime":StremioLibraryMerge.stamp(now.addingTimeInterval(-1)),"futureItem":["x":1]]
        let merged=try StremioLibraryMerge.applying(event,to:remote,episodes:ids,now:now)
        let updated=merged["state"] as! [String:Any]
        precondition((updated["timeOffset"] as? NSNumber)?.int64Value==42_250 && (updated["duration"] as? NSNumber)?.int64Value==1_200_000)
        precondition((updated["overallTimeWatched"] as? NSNumber)?.int64Value==600 && (updated["timeWatched"] as? NSNumber)?.int64Value==0)
        precondition(updated["watched"] as? String==encoded && updated["noNotif"] as? Bool==true && updated["futureField"] as? String=="keep")
        precondition(merged["name"] as? String=="Existing title" && merged["removed"] as? Bool==false && merged["futureItem"] != nil)
        let completed=StremioProgressEvent(type:event.type,videoID:event.videoID,title:event.title,position:event.duration,duration:event.duration,observedAt:now.addingTimeInterval(2),completed:true)
        let done=try StremioLibraryMerge.applying(completed,to:merged,episodes:ids,now:now.addingTimeInterval(2))
        let doneState=done["state"] as! [String:Any]
        precondition((doneState["timeOffset"] as? NSNumber)?.int64Value==0 && (doneState["timesWatched"] as? NSNumber)?.int64Value==4)
        let idempotent=try StremioLibraryMerge.applying(completed,to:done,episodes:ids,now:now.addingTimeInterval(2))
        precondition(((idempotent["state"] as! [String:Any])["timesWatched"] as? NSNumber)?.int64Value==4)
        reject{_ = try StremioLibraryMerge.applying(event,to:done,episodes:ids,now:now.addingTimeInterval(3))}
        let created=try StremioLibraryMerge.applying(event,to:nil,episodes:ids,now:now)
        precondition(created["removed"] as? Bool==true && created["temp"] as? Bool==true)
        precondition(StremioLibraryMerge.resume(merged,videoID:event.videoID,localUpdated:now.addingTimeInterval(-1))==42.25)
        precondition(StremioLibraryMerge.resume(merged,videoID:ids[2],localUpdated:now.addingTimeInterval(-1))==nil)
        precondition(StremioLibraryMerge.resume(merged,videoID:event.videoID,localUpdated:now)==nil)
        // Multiple offline episodes must survive coalescing. A receipt only
        // accepts our exact prior state, never a changed remote watched field.
        var queue=StremioOutbox()
        try queue.enqueue(completed,episodes:ids)
        let nextEpisode=StremioProgressEvent(type:"series",videoID:ids[2],title:"Synthetic",position:20,duration:1200,observedAt:now.addingTimeInterval(3),completed:false)
        try queue.enqueue(nextEpisode,episodes:ids)
        let later=StremioProgressEvent(type:"series",videoID:ids[2],title:"Synthetic",position:50,duration:1200,observedAt:now.addingTimeInterval(4),completed:false)
        try queue.enqueue(later,episodes:ids)
        precondition(queue.entries.count==2 && queue.entries[0].event.completed && queue.entries[1].event.position==50)
        let firstID=queue.entries[0].id
        let receipt=try JSONSerialization.data(withJSONObject:doneState,options:.sortedKeys)
        queue.acknowledge(firstID,itemID:"tt2934286",state:receipt)
        precondition(queue.entries.count==1 && queue.receipts["tt2934286"]==receipt)
        var uploaded=done;uploaded["_mtime"]=StremioLibraryMerge.stamp(now.addingTimeInterval(60))
        let offline=try StremioLibraryMerge.applying(later,to:uploaded,episodes:ids,now:now.addingTimeInterval(61),acceptedState:receipt)
        precondition(((offline["state"] as! [String:Any])["timeOffset"] as? NSNumber)?.int64Value==50_000)
        var changedRemote=uploaded;var changedState=doneState;changedState["timeOffset"]=100_000;changedRemote["state"]=changedState
        reject{_ = try StremioLibraryMerge.applying(later,to:changedRemote,episodes:ids,now:now.addingTimeInterval(61),acceptedState:receipt)}
        let restored=try JSONDecoder().decode(StremioOutbox.self,from:JSONEncoder().encode(queue))
        precondition(restored.entries.first?.event==later && restored.receipts==queue.receipts)
        let replacedID=queue.entries[0].id
        let newer=StremioProgressEvent(type:"series",videoID:ids[2],title:"Synthetic",position:60,duration:1200,observedAt:now.addingTimeInterval(5),completed:false)
        try queue.enqueue(newer,episodes:ids)
        queue.acknowledge(replacedID,itemID:"tt2934286",state:receipt)
        precondition(queue.entries.count==1 && queue.entries[0].event==newer)
        var rewatch=StremioOutbox();try rewatch.enqueue(completed,episodes:ids)
        let replay=StremioProgressEvent(type:event.type,videoID:event.videoID,title:event.title,position:10,duration:1200,observedAt:now.addingTimeInterval(5),completed:false)
        try rewatch.enqueue(replay,episodes:ids)
        precondition(rewatch.entries.count==2 && rewatch.entries[0].event.completed)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[LibraryProtocol.self]
        let api=StremioLibraryAPI(configuration:config)
        var requests:[String]=[]
        LibraryProtocol.handler={request in
            precondition(request.url!.host=="api.strem.io" && request.httpMethod=="POST")
            requests.append(request.url!.lastPathComponent)
            var data=request.httpBody ?? Data()
            if data.isEmpty,let stream=request.httpBodyStream{stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:4096);while true{let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};data.append(contentsOf:buffer.prefix(n))}}
            let body=try JSONSerialization.jsonObject(with:data) as! [String:Any]
            switch request.url!.lastPathComponent {
            case "login":
                precondition(body["type"] as? String=="Login" && body["facebook"] as? Bool==false && body["email"] as? String=="synthetic@example.test")
                return (200,#"{"result":{"authKey":"synthetic-key","user":{"_id":"synthetic-account"}}}"#)
            case "datastoreGet":
                precondition(body["authKey"] as? String=="synthetic-key" && body["collection"] as? String=="libraryItem" && body["ids"] as? [String]==["tt2934286"] && body["all"] as? Bool==false)
                return (200,"{\"result\":[]}")
            case "datastorePut":
                precondition((body["changes"] as? [[String:Any]])?.first?["_id"] as? String=="tt2934286")
                return (200,"{\"result\":{\"success\":true}}")
            default:fatalError("Unexpected API endpoint")
            }
        }
        let account=try await api.login(email:"synthetic@example.test",password:"synthetic-password")
        let empty=try await api.item("tt2934286",account:account);precondition(empty==nil)
        try await api.put(merged,account:account)
        precondition(requests==["login","datastoreGet","datastorePut"])
        LibraryProtocol.handler={_ in (200,"{\"error\":{\"code\":1,\"message\":\"must never enter logs\"}}")}
        do{_ = try await api.login(email:"synthetic@example.test",password:"x");fatalError("API error accepted")}catch StremioSyncError.authentication{}
        print("Stremio protocol passed: upstream bitfield sample, roundtrip/shift/idempotence, preserve unknown fields, units/conflicts, resume matching and mocked Login/Get/Put")
    }
}
